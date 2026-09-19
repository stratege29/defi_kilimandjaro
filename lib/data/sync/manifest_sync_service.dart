import 'dart:async';

import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:logger/logger.dart';

/// Orchestre la synchronisation des packs distants :
///   1. Liste les packs actifs (`content_index/global`).
///   2. Récupère leurs manifests.
///   3. Compare avec l'état local (cache Drift `pack_state`).
///   4. Télécharge les packs en retard **un par un** (séquentiel), vérifie
///      le hash, met à jour le cache.
///
/// v0.2 — voir `docs/ota_v2_design.md`. La boucle est séquentielle avec
/// yield au scheduler entre packs, abort sur memory pressure, et un
/// `SyncReport` détaillé en retour. **Jamais dans le chemin critique du
/// boot** (cf. PR #15 — OOM iOS 26).
///
/// Deux déclencheurs :
/// - manuel, tous les packs (`ManifestSyncNotifier`, bouton de
///   `MyPacksView`) : `refresh()` sans scope ;
/// - automatique, différé et scopé aux packs possédés
///   (`OtaAutoSyncScheduler`, cf. `ota_auto_sync.dart`) : `refresh(onlyPacks:
///   …, priorityPack: …, resetPressureSignal: false)`.
class ManifestSyncService {
  ManifestSyncService({
    required RemoteDevinettePackDatasource remote,
    required LocalDevinetteCacheDatasource cache,
    required MemoryPressureSignal memoryPressure,
    Logger? logger,
    FirebaseCrashlytics? crashlytics,
  })  : _remote = remote,
        _cache = cache,
        _memoryPressure = memoryPressure,
        _logger = logger ?? Logger(),
        _crashlytics = crashlytics;

  final RemoteDevinettePackDatasource _remote;
  final LocalDevinetteCacheDatasource _cache;
  final MemoryPressureSignal _memoryPressure;
  final Logger _logger;
  final FirebaseCrashlytics? _crashlytics;

  /// Dernier maillon de la file de syncs (mutex FIFO).
  Future<SyncReport>? _inFlight;

  /// Synchronise les packs distants.
  ///
  /// - [onlyPacks] : packs logiques (sans suffixe `_community`) à traiter ;
  ///   `null` = tous les packs déclarés dans `content_index/global`.
  /// - [priorityPack] : placé en tête de boucle (pack actif du joueur).
  /// - [resetPressureSignal] : `true` pour le déclencheur manuel (un warning
  ///   émis au boot ne doit pas bloquer l'utilisateur), `false` pour
  ///   l'auto-sync qui doit honorer un signal frais.
  ///
  /// Mutex FIFO : un appel pendant une sync en vol est **chaîné** après
  /// elle et exécute toujours son propre scope avec ses propres paramètres
  /// (jamais de partage de Future : chaque appelant reçoit un rapport qui
  /// porte sur ses packs). Un pack déjà traité par la passe précédente est
  /// skippé par version + hash, donc une passe redondante coûte un
  /// `whereIn` et zéro download. Un seul download à la fois, garanti.
  Future<SyncReport> refresh({
    Iterable<String>? onlyPacks,
    String? priorityPack,
    bool resetPressureSignal = true,
    void Function(SyncProgress)? onProgress,
  }) {
    final scope = onlyPacks?.toSet();
    final pending = _inFlight;

    Future<SyncReport> run() => _refreshImpl(
          scope: scope,
          priorityPack: priorityPack,
          resetPressureSignal: resetPressureSignal,
          onProgress: onProgress,
        );

    late final Future<SyncReport> next;
    next = (pending == null
            ? run()
            : pending.then<SyncReport>(
                (_) => run(),
                onError: (Object _, StackTrace __) => run(),
              ))
        .whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
    _inFlight = next;
    return next;
  }

  Future<SyncReport> _refreshImpl({
    required Set<String>? scope,
    required String? priorityPack,
    required bool resetPressureSignal,
    required void Function(SyncProgress)? onProgress,
  }) async {
    // Déclencheur manuel : reset le signal de pression avant la sync — un
    // `didHaveMemoryPressure` émis au boot (AudioEngine preload + Firebase
    // init) ne doit pas empêcher une sync demandée par l'utilisateur.
    // L'auto-sync (`resetPressureSignal: false`) gère lui-même la
    // fraîcheur du signal via `lastPressureAt`.
    if (resetPressureSignal) _memoryPressure.reset();

    // Fetch top-level : on laisse l'erreur remonter pour que la UI affiche
    // un état d'erreur explicite (réseau / Firestore down / App Check).
    final List<String> packIds;
    if (scope == null) {
      packIds = await _remote.listActivePackIds();
    } else {
      // Scope : pas de lecture de `content_index`, un seul `whereIn` sur
      // les packs demandés + leur variante communautaire éventuelle (les
      // docs absents ne sont simplement pas retournés).
      packIds = [
        for (final p in scope) ...[p, '${p}_community'],
      ];
    }
    if (packIds.isEmpty) {
      _logger.i('ManifestSync: pas de pack actif déclaré.');
      return const SyncReport(updated: 0, skipped: 0, errors: 0);
    }

    final manifests = _prioritize(
      await _remote.fetchManifests(packIds),
      priorityPack,
    );
    _logger.i(
      'ManifestSync: ${manifests.length} manifests récupérés '
      '(${packIds.length} déclarés${scope == null ? "" : ", scopé"}).',
    );

    var updated = 0;
    var skipped = 0;
    var errors = 0;
    var aborted = false;

    for (var i = 0; i < manifests.length; i++) {
      if (_memoryPressure.isUnderPressure) {
        _logger.w(
          'ManifestSync: pression mémoire détectée, abort après '
          '$i/${manifests.length} packs.',
        );
        aborted = true;
        break;
      }

      final manifest = manifests[i];
      try {
        final outcome = await _syncSinglePack(manifest);
        switch (outcome) {
          case _PackOutcome.updated:
            updated++;
          case _PackOutcome.skipped:
            skipped++;
          case _PackOutcome.error:
            errors++;
        }
      } on Object catch (e, st) {
        errors++;
        _swallowAndLog(e, st);
      }

      onProgress?.call(
        SyncProgress(
          packIndex: i + 1,
          packTotal: manifests.length,
          currentPackId: manifest.packId,
        ),
      );

      // Yield au scheduler iOS pour qu'il puisse paginer la mémoire entre
      // packs (sinon une sync de N packs apparaît comme un seul pic).
      await Future<void>.delayed(Duration.zero);
    }

    return SyncReport(
      updated: updated,
      skipped: skipped,
      errors: errors,
      abortedByMemoryPressure: aborted,
    );
  }

  /// Ordre stable : le pack prioritaire (officiel puis communautaire) en
  /// tête, les autres dans l'ordre reçu. `List.sort` n'étant pas stable,
  /// on partitionne.
  static List<ContentPackManifest> _prioritize(
    List<ContentPackManifest> manifests,
    String? priorityPack,
  ) {
    if (priorityPack == null) return manifests;
    final head = <ContentPackManifest>[];
    final tail = <ContentPackManifest>[];
    for (final m in manifests) {
      (m.pack == priorityPack ? head : tail).add(m);
    }
    if (head.isEmpty) return manifests;
    head.sort((a, b) => (a.isCommunity ? 1 : 0) - (b.isCommunity ? 1 : 0));
    return [...head, ...tail];
  }

  Future<_PackOutcome> _syncSinglePack(ContentPackManifest manifest) async {
    final local = await _cache.packState(manifest.packId);
    await _cache.markManifestSync(manifest.packId);

    final upToDate = local != null &&
        local.packVersion == manifest.currentVersion &&
        local.hashSha256 == manifest.hashSha256;

    if (upToDate) {
      _logger.d(
        'ManifestSync: ${manifest.packId} à jour (v${local.packVersion}).',
      );
      return _PackOutcome.skipped;
    }

    if (!manifest.enabled) {
      _logger.i('ManifestSync: ${manifest.packId} désactivé — skip.');
      return _PackOutcome.skipped;
    }

    _logger.i(
      'ManifestSync: ${manifest.packId} '
      '${local == null ? "nouveau" : "v${local.packVersion}"} → '
      'v${manifest.currentVersion} (download)',
    );

    final List<Devinette> devinettes;
    try {
      devinettes = await _remote.downloadAndParse(manifest);
    } on RemotePackException catch (e, st) {
      _swallowAndLog(e, st);
      return _PackOutcome.error;
    }

    final source = manifest.isCommunity
        ? DevinetteSource.community
        : DevinetteSource.remotePack;

    await _cache.replacePackContents(
      pack: manifest.pack,
      source: source,
      devinettes: devinettes,
      packVersion: manifest.currentVersion,
    );

    await _cache.upsertPackState(
      packId: manifest.packId,
      pack: manifest.pack,
      packVersion: manifest.currentVersion,
      hashSha256: manifest.hashSha256,
      sizeBytes: manifest.sizeBytes,
      count: devinettes.length,
    );

    _logger.i(
      'ManifestSync: ${manifest.packId} v${manifest.currentVersion} '
      'installé (${devinettes.length} entrées).',
    );
    return _PackOutcome.updated;
  }

  void _swallowAndLog(Object error, StackTrace stack) {
    _logger.w('ManifestSync error: $error');
    _crashlytics?.recordError(
      error,
      stack,
      reason: 'ManifestSyncService',
    );
  }
}

enum _PackOutcome { updated, skipped, error }
