// Tests unitaires de `OtaAutoSyncScheduler` (auto-sync OTA v0.3 : différé,
// gaté, scopé). Horloge et délai injectés ; fakes par `implements`.

import 'dart:async';

import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/manifest_sync_service.dart';
import 'package:defi_kilimandjaro/data/sync/ota_auto_sync.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSyncService service;
  late _FakePressure pressure;
  late SharedPreferences prefs;
  late _Clock clock;
  late OtaAutoSyncConfig config;
  late Set<String> owned;
  late String? active;
  late Completer<void> bootReady;
  late List<SyncReport> synced;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    service = _FakeSyncService();
    pressure = _FakePressure();
    clock = _Clock(DateTime(2026, 9, 19, 12));
    config = const OtaAutoSyncConfig(
      enabled: true,
      delay: Duration(seconds: 20),
      minInterval: Duration(hours: 6),
    );
    owned = {'culture_ci', 'crack_nouchi'};
    active = 'culture_ci';
    bootReady = Completer<void>()..complete();
    synced = [];
  });

  OtaAutoSyncScheduler build() {
    final s = OtaAutoSyncScheduler(
      service: service,
      pressure: pressure,
      prefs: prefs,
      config: () => config,
      ownedPacks: () => owned,
      activePackId: () => active,
      bootReady: bootReady.future,
      onSynced: synced.add,
      now: clock.now,
      delay: clock.wait,
      logger: Logger(level: Level.off),
    );
    addTearDown(s.dispose);
    return s;
  }

  group('syncOwnedPacks — sas', () {
    test('kill-switch off → aucun appel au service', () async {
      config = const OtaAutoSyncConfig(
        enabled: false,
        delay: Duration.zero,
        minInterval: Duration.zero,
      );
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, isEmpty);
    });

    test('attend bootReady avant de lire la config', () async {
      bootReady = Completer<void>();
      var configReads = 0;
      final s = OtaAutoSyncScheduler(
        service: service,
        pressure: pressure,
        prefs: prefs,
        config: () {
          configReads++;
          return config;
        },
        ownedPacks: () => owned,
        activePackId: () => active,
        bootReady: bootReady.future,
        now: clock.now,
        delay: clock.wait,
        logger: Logger(level: Level.off),
      );
      addTearDown(s.dispose);

      final run = s.syncOwnedPacks(reason: 'test');
      await Future<void>.delayed(Duration.zero);
      expect(configReads, 0);
      expect(service.calls, isEmpty);

      bootReady.complete();
      await run;
      expect(configReads, 1);
      expect(service.calls, hasLength(1));
    });

    test('respecte le délai depuis start() (20 s − écoulé)', () async {
      final s = build();
      clock.advance(const Duration(seconds: 5));
      // start() fixe l'origine à T+5 ; la passe attend 20 s pleines.
      s.start();
      await _settle();
      expect(clock.waits, [const Duration(seconds: 20)]);
      expect(service.calls, hasLength(1));
    });

    test("délai partiellement écoulé → n'attend que le reste", () async {
      final s = build()..start();
      await _settle();
      service.calls.clear();
      clock.waits.clear();
      // Nouvelle passe 15 s après start (throttle désactivé pour isoler).
      config = const OtaAutoSyncConfig(
        enabled: true,
        delay: Duration(seconds: 20),
        minInterval: Duration.zero,
      );
      clock.advance(const Duration(seconds: 15));
      // Le premier start avait déjà avancé l'horloge de 20 s via wait :
      // ici l'origine est start(), donc plus aucun délai n'est requis.
      await s.syncOwnedPacks(reason: 'test');
      expect(clock.waits, isEmpty);
      expect(service.calls, hasLength(1));
    });
  });

  group('syncOwnedPacks — scope, throttle, stamp', () {
    test('scope = packs possédés, actif en tête, sans reset pression',
        () async {
      await build().syncOwnedPacks(reason: 'test');
      final call = service.calls.single;
      expect(call.onlyPacks, {'culture_ci', 'crack_nouchi'});
      expect(call.priorityPack, 'culture_ci');
      expect(call.resetPressureSignal, isFalse);
    });

    test('première passe (pas de clé) → sync + stamp écrit', () async {
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, hasLength(1));
      expect(
        prefs.getInt(kOtaLastAutoSyncAtKey),
        clock.now().millisecondsSinceEpoch,
      );
    });

    test('throttle : dernière passe il y a 1 h < 6 h → rien', () async {
      await prefs.setInt(
        kOtaLastAutoSyncAtKey,
        clock.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, isEmpty);
    });

    test('throttle : dernière passe il y a 7 h → sync', () async {
      await prefs.setInt(
        kOtaLastAutoSyncAtKey,
        clock.now().subtract(const Duration(hours: 7)).millisecondsSinceEpoch,
      );
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, hasLength(1));
    });

    test('aucun pack possédé → rien et pas de stamp', () async {
      owned = {};
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, isEmpty);
      expect(prefs.getInt(kOtaLastAutoSyncAtKey), isNull);
    });

    test('abandon pour pression pendant la sync → pas de stamp', () async {
      service.report = const SyncReport(
        updated: 0,
        skipped: 0,
        errors: 0,
        abortedByMemoryPressure: true,
      );
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, hasLength(1));
      expect(prefs.getInt(kOtaLastAutoSyncAtKey), isNull);
    });

    test('onSynced appelé seulement si hasChanges', () async {
      service.report = const SyncReport(updated: 0, skipped: 2, errors: 0);
      await build().syncOwnedPacks(reason: 'a');
      expect(synced, isEmpty);

      config = const OtaAutoSyncConfig(
        enabled: true,
        delay: Duration.zero,
        minInterval: Duration.zero,
      );
      service.report = const SyncReport(updated: 1, skipped: 1, errors: 0);
      await build().syncOwnedPacks(reason: 'b');
      expect(synced, hasLength(1));
    });

    test('tous les packs en erreur → pas de stamp, backoff 5 min', () async {
      service.report = const SyncReport(updated: 0, skipped: 0, errors: 2);
      config = const OtaAutoSyncConfig(
        enabled: true,
        delay: Duration.zero,
        minInterval: Duration.zero,
      );
      final s = build();
      await s.syncOwnedPacks(reason: 'a');
      expect(service.calls, hasLength(1));
      expect(prefs.getInt(kOtaLastAutoSyncAtKey), isNull);

      // Backoff court : la passe suivante est ignorée…
      await s.syncOwnedPacks(reason: 'b');
      expect(service.calls, hasLength(1));
      // …puis reprend après 5 min, sans attendre 6 h.
      clock.advance(kOtaFailureBackoff + const Duration(seconds: 1));
      service.report = const SyncReport(updated: 1, skipped: 1, errors: 0);
      await s.syncOwnedPacks(reason: 'c');
      expect(service.calls, hasLength(2));
      expect(prefs.getInt(kOtaLastAutoSyncAtKey), isNotNull);
    });

    test('erreurs partielles → stamp écrit (au moins un pack OK)', () async {
      service.report = const SyncReport(updated: 1, skipped: 0, errors: 1);
      await build().syncOwnedPacks(reason: 'a');
      expect(prefs.getInt(kOtaLastAutoSyncAtKey), isNotNull);
    });

    test('réentrance : un second appel pendant la passe est ignoré',
        () async {
      service.gate = Completer<void>();
      final s = build();
      final first = s.syncOwnedPacks(reason: 'a');
      await _settle();
      await s.syncOwnedPacks(reason: 'b');
      service.gate!.complete();
      await first;
      expect(service.calls, hasLength(1));
    });
  });

  group('pression mémoire', () {
    test('signal frais → report, aucun appel', () async {
      pressure
        ..underPressure = true
        ..lastPressureAt = clock.now();
      await build().syncOwnedPacks(reason: 'test');
      expect(service.calls, isEmpty);
      expect(pressure.underPressure, isTrue);
    });

    test('signal périmé (> 60 s) → reset puis sync', () async {
      pressure
        ..underPressure = true
        ..lastPressureAt = clock.now().subtract(const Duration(minutes: 5));
      await build().syncOwnedPacks(reason: 'test');
      expect(pressure.resets, 1);
      expect(service.calls, hasLength(1));
    });

    test('signal frais sur syncActivePack → retentative du MÊME pack, '
        'hors throttle', () async {
      // Passe possédés récente : la retentative ne doit pas être throttlée.
      await prefs.setInt(
        kOtaLastAutoSyncAtKey,
        clock.now().millisecondsSinceEpoch,
      );
      pressure
        ..underPressure = true
        ..lastPressureAt = clock.now();
      final s = build();
      await s.syncActivePack('football_ci');
      expect(service.calls, isEmpty);
      await _settle();
      expect(service.calls.map((c) => c.onlyPacks), [
        {'football_ci'},
      ]);
    });

    test('signal frais → retentative planifiée après 2 min', () async {
      pressure
        ..underPressure = true
        ..lastPressureAt = clock.now();
      final s = build();
      await s.syncOwnedPacks(reason: 'test');
      expect(service.calls, isEmpty);
      // Le report est un `delay(2 min)` : le fake avance l'horloge de 2 min,
      // le signal devient périmé, la retentative synchronise.
      await _settle();
      expect(clock.waits, contains(kOtaPressureRetryDelay));
      expect(service.calls, hasLength(1));
    });
  });

  group('syncActivePack', () {
    test('scopé au pack, prioritaire, ignore le throttle', () async {
      final stamp = clock.now().millisecondsSinceEpoch;
      await prefs.setInt(kOtaLastAutoSyncAtKey, stamp);
      await build().syncActivePack('football_ci');
      final call = service.calls.single;
      expect(call.onlyPacks, {'football_ci'});
      expect(call.priorityPack, 'football_ci');
      expect(call.resetPressureSignal, isFalse);
      // Pas de stamp : seule la passe « possédés » l'écrit.
      expect(prefs.getInt(kOtaLastAutoSyncAtKey), stamp);
    });

    test('cooldown : pack synchronisé il y a < 10 min → aucun appel',
        () async {
      final s = build();
      await s.syncActivePack('p');
      expect(service.calls, hasLength(1));

      clock.advance(const Duration(minutes: 3));
      await s.syncActivePack('p');
      expect(service.calls, hasLength(1), reason: 'cooldown');

      clock.advance(const Duration(minutes: 8));
      await s.syncActivePack('p');
      expect(service.calls, hasLength(2));
    });

    test('cooldown alimenté par la passe possédés', () async {
      final s = build();
      await s.syncOwnedPacks(reason: 'boot');
      // culture_ci vient d'être couvert par la passe possédés.
      await s.syncActivePack('culture_ci');
      expect(service.calls, hasLength(1));
      // Un pack non possédé n'est pas couvert.
      await s.syncActivePack('football_ci');
      expect(service.calls, hasLength(2));
    });

    test("recul d'horloge après start() → attente bornée au délai",
        () async {
      final s = build()..start();
      await _settle();
      service.calls.clear();
      clock.waits.clear();
      config = const OtaAutoSyncConfig(
        enabled: true,
        delay: Duration(seconds: 20),
        minInterval: Duration.zero,
      );
      clock.advance(const Duration(hours: -2));
      await s.syncOwnedPacks(reason: 'skew');
      expect(clock.waits, [const Duration(seconds: 20)]);
      expect(service.calls, hasLength(1));
    });

    test('coalescé par pack : deux appels concurrents → un seul', () async {
      service.gate = Completer<void>();
      final s = build();
      final a = s.syncActivePack('p');
      await _settle();
      final b = s.syncActivePack('p');
      service.gate!.complete();
      await Future.wait([a, b]);
      expect(service.calls, hasLength(1));
    });

    test('respecte le même délai que la passe boot', () async {
      final s = build()..start();
      // start() lance la passe boot qui attend 20 s ; une activation à
      // T+6 s doit attendre le reste, pas partir immédiatement.
      await Future<void>.delayed(Duration.zero);
      await s.syncActivePack('p');
      expect(clock.waits, everyElement(greaterThan(Duration.zero)));
      expect(service.calls.last.onlyPacks, {'p'});
    });
  });

  group('lifecycle', () {
    test('resumed → passe possédés (throttlée)', () async {
      final s = build()..start();
      await _settle();
      expect(service.calls, hasLength(1));

      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      // Stamp écrit à l'instant → throttle 6 h → pas de second appel.
      expect(service.calls, hasLength(1));

      clock.advance(const Duration(hours: 7));
      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(service.calls, hasLength(2));
    });

    test('paused / inactive → rien', () async {
      final s = build()..start();
      await _settle();
      service.calls.clear();
      s
        ..didChangeAppLifecycleState(AppLifecycleState.paused)
        ..didChangeAppLifecycleState(AppLifecycleState.inactive);
      await _settle();
      expect(service.calls, isEmpty);
    });

    test('dispose avant la fin du délai → aucun appel', () async {
      bootReady = Completer<void>();
      build()
        ..start()
        ..dispose();
      bootReady.complete();
      await _settle();
      expect(service.calls, isEmpty);
    });
  });

  group('otaAutoSyncSchedulerProvider — câblage Riverpod', () {
    test('choix du pack gratuit puis déblocage → syncActivePack', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          manifestSyncServiceProvider.overrideWithValue(service),
          memoryPressureSignalProvider.overrideWithValue(pressure),
          remoteConfigServiceProvider.overrideWithValue(_ImmediateRc()),
          playerProgressProvider.overrideWith(
            (ref) => PlayerProgressNotifier(PlayerProgressRepository(prefs)),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Instancie le scheduler (et ses `ref.listen`) sans `start()`.
      container.read(otaAutoSyncSchedulerProvider);
      final progress = container.read(playerProgressProvider.notifier);

      await progress.chooseFreePack('culture_ci');
      await _settle();
      expect(service.calls, isNotEmpty);
      expect(
        service.calls.map((c) => c.onlyPacks),
        everyElement({'culture_ci'}),
      );
      expect(service.calls.first.priorityPack, 'culture_ci');

      service.calls.clear();
      await progress.grantPack('crack_nouchi');
      await _settle();
      expect(service.calls.map((c) => c.onlyPacks), [
        {'crack_nouchi'},
      ]);
    });
  });

  group('échecs', () {
    test('exception du service → avalée, backoff 5 min', () async {
      service.throwOnCall = StateError('firestore down');
      config = const OtaAutoSyncConfig(
        enabled: true,
        delay: Duration.zero,
        minInterval: Duration.zero,
      );
      final s = build();
      await s.syncOwnedPacks(reason: 'a'); // ne throw pas
      expect(service.calls, hasLength(1));

      service.throwOnCall = null;
      await s.syncOwnedPacks(reason: 'b');
      expect(service.calls, hasLength(1), reason: 'backoff actif');

      clock.advance(kOtaFailureBackoff + const Duration(seconds: 1));
      await s.syncOwnedPacks(reason: 'c');
      expect(service.calls, hasLength(2));
    });
  });
}

/// Laisse tourner les microtasks et les délais simulés.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _Clock {
  _Clock(this._now);
  DateTime _now;
  final List<Duration> waits = [];

  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);

  /// Délai simulé : avance l'horloge et rend la main au scheduler.
  Future<void> wait(Duration d) async {
    waits.add(d);
    _now = _now.add(d);
    await Future<void>.delayed(Duration.zero);
  }
}

class _SyncCall {
  const _SyncCall({
    required this.onlyPacks,
    required this.priorityPack,
    required this.resetPressureSignal,
  });
  final Set<String>? onlyPacks;
  final String? priorityPack;
  final bool resetPressureSignal;
}

class _FakeSyncService implements ManifestSyncService {
  final List<_SyncCall> calls = [];
  SyncReport report = const SyncReport(updated: 1, skipped: 0, errors: 0);
  Completer<void>? gate;
  Error? throwOnCall;

  @override
  Future<SyncReport> refresh({
    Iterable<String>? onlyPacks,
    String? priorityPack,
    bool resetPressureSignal = true,
    void Function(SyncProgress)? onProgress,
  }) async {
    calls.add(
      _SyncCall(
        onlyPacks: onlyPacks?.toSet(),
        priorityPack: priorityPack,
        resetPressureSignal: resetPressureSignal,
      ),
    );
    if (throwOnCall != null) throw throwOnCall!;
    if (gate != null) await gate!.future;
    return report;
  }

}

/// Remote Config sans réseau : défauts avec délai nul, pour que le test de
/// câblage n'attende pas 20 s réelles.
class _ImmediateRc extends RemoteConfigService {
  @override
  GameEconomyConfig get current => GameEconomyConfig.defaults.copyWith(
        otaAutoSyncDelaySeconds: 0,
        otaAutoSyncMinIntervalHours: 0,
      );
}

class _FakePressure implements MemoryPressureSignal {
  bool underPressure = false;
  int resets = 0;

  @override
  DateTime? lastPressureAt;

  @override
  bool get isUnderPressure => underPressure;

  @override
  void reset() {
    resets++;
    underPressure = false;
  }

  @override
  void dispose() {}
}
