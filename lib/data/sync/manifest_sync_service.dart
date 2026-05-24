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
/// v0.2 — voir `docs/ota_v2_design.md`. Le boucle est désormais séquentielle
/// avec yield au scheduler entre packs, abort sur memory pressure, et un
/// `SyncReport` détaillé en retour. **Ne doit jamais être appelé au boot**
/// (cf. PR #15 — OOM iOS 26). Trigger manuel uniquement depuis
/// `ManifestSyncNotifier` (bouton dans `MyPacksView`).
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

  /// Mutex global pour éviter les syncs concurrents (e.g. user double-tap).
  Future<SyncReport>? _inFlight;

  /// Synchronise tous les packs actifs. No-op si une sync est déjà en cours
  /// (retourne le Future de la sync existante).
  Future<SyncReport> refresh({void Function(SyncProgress)? onProgress}) {
    return _inFlight ??= _refreshImpl(onProgress).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<SyncReport> _refreshImpl(
    void Function(SyncProgress)? onProgress,
  ) async {
    // Reset le signal de pression avant chaque sync : un `didHaveMemoryPressure`
    // émis au boot (AudioEngine preload + Firebase init) ne doit pas empêcher
    // les syncs ultérieures déclenchées par l'utilisateur.
    _memoryPressure.reset();

    // Fetch top-level : on laisse l'erreur remonter pour que la UI affiche
    // un état d'erreur explicite (réseau / Firestore down / App Check).
    final packIds = await _remote.listActivePackIds();
    if (packIds.isEmpty) {
      _logger.i('ManifestSync: pas de pack actif déclaré.');
      return const SyncReport(updated: 0, skipped: 0, errors: 0);
    }

    final manifests = await _remote.fetchManifests(packIds);
    _logger.i(
      'ManifestSync: ${manifests.length} manifests récupérés '
      '(${packIds.length} déclarés).',
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

  /// Synchronise un pack précis (utilisé par `onPackEntry` à priorité haute).
  Future<void> syncPack(String pack) async {
    try {
      final manifest = await _remote.fetchManifest(pack);
      if (manifest != null) {
        await _syncSinglePack(manifest);
      }
      // Tente aussi le pack communautaire si présent.
      final community = await _remote.fetchManifest('${pack}_community');
      if (community != null) {
        await _syncSinglePack(community);
      }
    } on Object catch (e, st) {
      _swallowAndLog(e, st);
    }
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
