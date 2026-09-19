import 'dart:async';

import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_notification_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/manifest_sync_service.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé SharedPreferences : epoch ms de la dernière passe automatique
/// **complète** (non abandonnée) sur les packs possédés.
const String kOtaLastAutoSyncAtKey = 'ota_last_auto_sync_at';

/// Au-delà de cet âge, un signal de pression mémoire est considéré comme un
/// warning de boot périmé (preload audio + init Firebase) et n'empêche pas
/// l'auto-sync.
const Duration kOtaPressureStaleAfter = Duration(seconds: 60);

/// Report d'une passe automatique bloquée par une pression mémoire fraîche.
const Duration kOtaPressureRetryDelay = Duration(minutes: 2);

/// Nombre maximal de reports pour pression mémoire par session.
const int kOtaPressureMaxRetries = 3;

/// Backoff (en mémoire) après un échec du service (réseau, Firestore, App
/// Check, ou passe dont tous les packs sont en erreur) — évite de marteler
/// en boucle sur `resumed`.
const Duration kOtaFailureBackoff = Duration(minutes: 5);

/// Attente maximale du sas sur `bootReady` (App Check + Auth + Remote
/// Config). Au-delà, on continue avec la config courante (defaults RC) :
/// une attestation App Check qui pend ne doit pas rendre l'auto-sync
/// silencieusement inerte pour toute la session.
const Duration kOtaBootReadyTimeout = Duration(seconds: 90);

/// Cooldown en mémoire d'un pack déjà synchronisé (par n'importe quelle
/// passe) : une bascule de pack actif dans « Mes packs » ne doit pas coûter
/// une requête Firestore à chaque fois.
const Duration kOtaSinglePackCooldown = Duration(minutes: 10);

/// Paramètres de l'auto-sync résolus depuis Remote Config **au moment du
/// déclenchement** (jamais figés à la construction : le fetch RC termine
/// tard dans `_deferredBoot`).
class OtaAutoSyncConfig {
  const OtaAutoSyncConfig({
    required this.enabled,
    required this.delay,
    required this.minInterval,
  });

  factory OtaAutoSyncConfig.fromEconomy(GameEconomyConfig c) {
    return OtaAutoSyncConfig(
      enabled: c.otaAutoSyncEnabled,
      delay: Duration(seconds: c.otaAutoSyncDelaySeconds),
      minInterval: Duration(hours: c.otaAutoSyncMinIntervalHours),
    );
  }

  /// Kill-switch `ota_autosync_enabled`.
  final bool enabled;

  /// Délai minimal entre [OtaAutoSyncScheduler.start] et tout download.
  final Duration delay;

  /// Intervalle minimal entre deux passes sur les packs possédés.
  final Duration minInterval;
}

/// Déclenche la synchro OTA du contenu **sans action de l'utilisateur**,
/// hors du chemin critique du boot (cf. PR #15 — OOM iOS 26 et
/// `docs/ota_v2_design.md`).
///
/// Trois déclencheurs, tous soumis au même sas ([_gate]) :
/// 1. **différé** après [start] (appelé en fin de post-frame du `_BootGate`) ;
/// 2. **retour en premier plan** (`AppLifecycleState.resumed`) ;
/// 3. **activation d'un pack** ([syncActivePack], branché sur
///    `activePackIdProvider` / `ownedPacksProvider` par le provider).
///
/// Le sas attend que App Check + Auth + Remote Config soient prêts
/// (`bootReady`), lit le kill-switch, respecte le délai depuis [start],
/// puis honore un signal de pression mémoire **frais** (report) ou ignore
/// un signal périmé (reset). Les passes « packs possédés » (1 et 2) sont en
/// plus throttlées par [OtaAutoSyncConfig.minInterval] ; la première passe
/// après installation ne l'est jamais.
///
/// N'écrit jamais dans `manifestSyncStateProvider` : aucune bannière, la UI
/// de « Mes packs » ne voit que ses propres refreshs manuels. Tout est
/// fail-soft : aucune exception ne remonte au caller.
class OtaAutoSyncScheduler with WidgetsBindingObserver {
  OtaAutoSyncScheduler({
    required ManifestSyncService service,
    required MemoryPressureSignal pressure,
    required SharedPreferences prefs,
    required OtaAutoSyncConfig Function() config,
    required Set<String> Function() ownedPacks,
    required String? Function() activePackId,
    required Future<void> bootReady,
    void Function(SyncReport report)? onSynced,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    Logger? logger,
  })  : _service = service,
        _pressure = pressure,
        _prefs = prefs,
        _config = config,
        _ownedPacks = ownedPacks,
        _activePackId = activePackId,
        _bootReady = bootReady,
        _onSynced = onSynced,
        _now = now ?? DateTime.now,
        _delay = delay ?? _realDelay,
        _logger = logger ?? Logger();

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  final ManifestSyncService _service;
  final MemoryPressureSignal _pressure;
  final SharedPreferences _prefs;
  final OtaAutoSyncConfig Function() _config;
  final Set<String> Function() _ownedPacks;
  final String? Function() _activePackId;
  final Future<void> _bootReady;
  final void Function(SyncReport report)? _onSynced;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Logger _logger;

  /// Origine du délai : instant de [start] (≈ première frame, ou plus tard
  /// si les dialogues consent/ATT ont retardé la fin du post-frame — ce qui
  /// ne fait que reculer davantage le premier download, donc sûr).
  DateTime? _startedAt;
  bool _started = false;
  bool _disposed = false;
  bool _ownedRunInFlight = false;
  DateTime? _notBefore;
  int _pressureRetries = 0;
  final Set<String> _singleInFlight = <String>{};

  /// Dernière sync réussie (ou « à jour ») par pack, toutes passes confondues.
  final Map<String, DateTime> _lastPackSyncAt = <String, DateTime>{};

  /// À appeler une fois, en fin de post-frame du `_BootGate`. Mémorise
  /// l'origine du délai, enregistre l'observer lifecycle et lance la passe
  /// différée sur les packs possédés.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _startedAt = _now();
    WidgetsBinding.instance.addObserver(this);
    unawaited(syncOwnedPacks(reason: 'boot'));
  }

  /// Passe throttlée sur les packs possédés (pack actif en tête).
  Future<void> syncOwnedPacks({required String reason}) async {
    if (_ownedRunInFlight || _disposed) return;
    _ownedRunInFlight = true;
    try {
      final cfg = await _gate(
        reason,
        retry: () => syncOwnedPacks(reason: 'pressure-retry'),
      );
      if (cfg == null) return;
      final now = _now();
      if (_isBackingOff(now)) return;
      final lastMs = _prefs.getInt(kOtaLastAutoSyncAtKey);
      if (lastMs != null) {
        final since =
            now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
        // `since` négatif = horloge reculée depuis le stamp : on ne bloque
        // pas sur une durée qui n'a pas de sens.
        if (since >= Duration.zero && since < cfg.minInterval) {
          _logger.d(
            'OtaAutoSync[$reason]: throttled (dernière passe il y a '
            '${since.inMinutes} min < ${cfg.minInterval.inHours} h).',
          );
          return;
        }
      }
      final owned = _ownedPacks();
      if (owned.isEmpty) {
        _logger.d('OtaAutoSync[$reason]: aucun pack possédé, rien à faire.');
        return;
      }
      _logger.i('OtaAutoSync[$reason]: sync de ${owned.length} pack(s).');
      final report = await _service.refresh(
        onlyPacks: owned,
        priorityPack: _activePackId(),
        resetPressureSignal: false,
      );
      _logger.i(
        'OtaAutoSync[$reason]: ${report.updated} maj, ${report.skipped} à '
        'jour, ${report.errors} erreur(s)'
        '${report.abortedByMemoryPressure ? ", abandonnée (pression)" : ""}.',
      );
      // Passe entièrement en échec (erreurs par pack avalées par le
      // service, donc pas d'exception ici) : pas de stamp, backoff court.
      final allFailed =
          report.errors > 0 && report.errors == report.totalProcessed;
      if (allFailed) {
        _onFailure(reason, 'tous les packs en erreur', StackTrace.empty);
        return;
      }
      if (!report.abortedByMemoryPressure) {
        await _prefs.setInt(kOtaLastAutoSyncAtKey, now.millisecondsSinceEpoch);
        for (final id in owned) {
          _lastPackSyncAt[id] = now;
        }
      }
      if (report.hasChanges) _onSynced?.call(report);
    } on Object catch (e, st) {
      _onFailure(reason, e, st);
    } finally {
      _ownedRunInFlight = false;
    }
  }

  /// Sync non bloquante d'un seul pack (activation, choix du pack gratuit,
  /// déblocage). Coalescée par pack et hors throttle « possédés », mais
  /// soumise à un cooldown court ([kOtaSinglePackCooldown]) si ce pack a
  /// déjà été synchronisé par n'importe quelle passe : une bascule de pack
  /// actif ne coûte alors rien.
  Future<void> syncActivePack(String packId) async {
    if (_disposed || !_singleInFlight.add(packId)) return;
    try {
      final last = _lastPackSyncAt[packId];
      if (last != null && _now().difference(last) < kOtaSinglePackCooldown) {
        _logger.d('OtaAutoSync[pack:$packId]: synchronisé récemment, skip.');
        return;
      }
      final cfg = await _gate(
        'pack:$packId',
        retry: () => syncActivePack(packId),
      );
      if (cfg == null) return;
      if (_isBackingOff(_now())) return;
      final report = await _service.refresh(
        onlyPacks: [packId],
        priorityPack: packId,
        resetPressureSignal: false,
      );
      if (report.errors > 0 && report.errors == report.totalProcessed) {
        _onFailure('pack:$packId', 'pack en erreur', StackTrace.empty);
        return;
      }
      if (!report.abortedByMemoryPressure) _lastPackSyncAt[packId] = _now();
      if (report.hasChanges) _onSynced?.call(report);
    } on Object catch (e, st) {
      _onFailure('pack:$packId', e, st);
    } finally {
      _singleInFlight.remove(packId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncOwnedPacks(reason: 'resumed'));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }

  /// Sas commun à tous les déclencheurs. Retourne la config résolue, ou
  /// `null` si la sync ne doit pas avoir lieu maintenant. [retry] est
  /// rejoué (même déclencheur, mêmes packs) après un report pour pression
  /// mémoire fraîche.
  Future<OtaAutoSyncConfig?> _gate(
    String reason, {
    required Future<void> Function() retry,
  }) async {
    // Borné : une attestation App Check qui pend ne doit pas suspendre le
    // sas (et donc tous les déclencheurs) pour la session entière.
    await _bootReady.timeout(
      kOtaBootReadyTimeout,
      onTimeout: () => _logger.w(
        'OtaAutoSync[$reason]: bootReady non résolu après '
        '${kOtaBootReadyTimeout.inSeconds} s, on continue avec la config '
        'courante.',
      ),
    );
    if (_disposed) return null;

    final cfg = _config();
    if (!cfg.enabled) {
      _logger.i('OtaAutoSync[$reason]: désactivé par Remote Config.');
      return null;
    }

    // Horloge murale : un recul d'horloge après start() gonflerait
    // `remaining` ; on le borne au délai configuré.
    final origin = _startedAt ?? _now();
    var remaining = cfg.delay - _now().difference(origin);
    if (remaining > cfg.delay) remaining = cfg.delay;
    if (remaining > Duration.zero) {
      await _delay(remaining);
      if (_disposed) return null;
    }

    if (_pressure.isUnderPressure) {
      final at = _pressure.lastPressureAt;
      final fresh =
          at != null && _now().difference(at) < kOtaPressureStaleAfter;
      if (fresh) {
        _logger.w('OtaAutoSync[$reason]: pression mémoire fraîche, report.');
        _scheduleRetry(retry);
        return null;
      }
      // Signal périmé (boot) : on l'efface pour ne pas bloquer la session.
      _pressure.reset();
    }
    return cfg;
  }

  void _scheduleRetry(Future<void> Function() retry) {
    if (_pressureRetries >= kOtaPressureMaxRetries) return;
    _pressureRetries++;
    unawaited(
      _delay(kOtaPressureRetryDelay).then((_) {
        if (!_disposed) unawaited(retry());
      }),
    );
  }

  bool _isBackingOff(DateTime now) {
    final until = _notBefore;
    if (until == null || !now.isBefore(until)) return false;
    _logger.d("OtaAutoSync: backoff jusqu'à $until.");
    return true;
  }

  void _onFailure(String reason, Object error, StackTrace stack) {
    _notBefore = _now().add(kOtaFailureBackoff);
    // Le service a déjà remonté à Crashlytics les erreurs par pack ; ici ce
    // sont les échecs top-level (manifests / réseau) ou une passe sans
    // aucun pack réussi.
    _logger.w('OtaAutoSync[$reason]: échec, backoff 5 min — $error');
  }
}

/// Complété quand `_deferredBoot` a terminé App Check + Auth + Remote
/// Config. Overridé dans `main.dart` ; déjà résolu par défaut (tests,
/// widgets isolés).
final deferredBootReadyProvider = Provider<Future<void>>(
  (_) => Future<void>.value(),
);

/// Scheduler de l'auto-sync OTA. Lu une fois par le `_BootGate` (qui appelle
/// [OtaAutoSyncScheduler.start]) ; les `ref.listen` ci-dessous branchent le
/// déclencheur « pack activé » sans toucher à `PlayerProgressNotifier` ni
/// aux écrans.
final otaAutoSyncSchedulerProvider = Provider<OtaAutoSyncScheduler>((ref) {
  final scheduler = OtaAutoSyncScheduler(
    service: ref.watch(manifestSyncServiceProvider),
    pressure: ref.watch(memoryPressureSignalProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    // `current` (et non `gameEconomyConfigProvider`) : lu à chaque
    // déclenchement, après le fetch Remote Config.
    config: () => OtaAutoSyncConfig.fromEconomy(
      ref.read(remoteConfigServiceProvider).current,
    ),
    ownedPacks: () => ref.read(ownedPacksProvider),
    activePackId: () => ref.read(activePackIdProvider),
    bootReady: ref.watch(deferredBootReadyProvider),
    onSynced: (_) {
      ref
        ..invalidate(packLiveQuestionCountProvider)
        ..invalidate(packUpdatesProvider);
    },
  );

  ref
    // Activation / choix du pack gratuit → sync prioritaire du pack actif.
    ..listen<String?>(activePackIdProvider, (prev, next) {
      if (next != null && next != prev) {
        unawaited(scheduler.syncActivePack(next));
      }
    })
    // Déblocage d'un pack → sync du (des) pack(s) ajouté(s).
    ..listen<Set<String>>(ownedPacksProvider, (prev, next) {
      for (final id in next.difference(prev ?? const <String>{})) {
        unawaited(scheduler.syncActivePack(id));
      }
    })
    ..onDispose(scheduler.dispose);
  return scheduler;
});
