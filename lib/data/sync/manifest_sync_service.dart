import 'dart:async';

import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:logger/logger.dart';

/// Orchestre la synchronisation des packs distants :
///   1. Liste les packs actifs (`content_index/global`).
///   2. Récupère leurs manifests.
///   3. Compare avec l'état local (cache Drift `pack_state`).
///   4. Télécharge les packs en retard, vérifie le hash, met à jour le cache.
///
/// Conçu pour être appelé en *fire-and-forget* après le first-frame :
/// `unawaited(ref.read(manifestSyncServiceProvider).refresh())`. Les échecs
/// sont loggés (Crashlytics + logger) mais ne propagent jamais — l'app
/// continue de fonctionner sur le starter pack bundlé.
class ManifestSyncService {
  ManifestSyncService({
    required RemoteDevinettePackDatasource remote,
    required LocalDevinetteCacheDatasource cache,
    Logger? logger,
    FirebaseCrashlytics? crashlytics,
  })  : _remote = remote,
        _cache = cache,
        _logger = logger ?? Logger(),
        _crashlytics = crashlytics;

  final RemoteDevinettePackDatasource _remote;
  final LocalDevinetteCacheDatasource _cache;
  final Logger _logger;
  final FirebaseCrashlytics? _crashlytics;

  /// Mutex global pour éviter les syncs concurrents au boot.
  Future<void>? _inFlight;

  /// Synchronise tous les packs actifs. No-op si une sync est déjà en cours.
  Future<void> refresh() {
    return _inFlight ??= _refreshImpl().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _refreshImpl() async {
    try {
      final packIds = await _remote.listActivePackIds();
      if (packIds.isEmpty) {
        _logger.i('ManifestSync: pas de pack actif déclaré.');
        return;
      }

      final manifests = await _remote.fetchManifests(packIds);
      _logger.i(
        'ManifestSync: ${manifests.length} manifests récupérés '
        '(${packIds.length} déclarés).',
      );

      // Déclenche les downloads en parallèle, mais bornés à 2 simultanés via
      // un sémaphore léger.
      const maxConcurrent = 2;
      final queue = List<ContentPackManifest>.from(manifests);
      final inFlight = <Future<void>>[];

      while (queue.isNotEmpty || inFlight.isNotEmpty) {
        while (inFlight.length < maxConcurrent && queue.isNotEmpty) {
          final manifest = queue.removeAt(0);
          inFlight.add(
            _syncSinglePack(manifest).catchError(_swallowAndLog),
          );
        }
        if (inFlight.isEmpty) break;
        await Future.any(inFlight);
        // Nettoie les terminés.
        inFlight.removeWhere(_isCompleted);
      }
    } on Object catch (e, st) {
      _swallowAndLog(e, st);
    }
  }

  /// Synchronise un pack précis (utile pour `onPackEntry` à priorité haute).
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

  Future<void> _syncSinglePack(ContentPackManifest manifest) async {
    final local = await _cache.packState(manifest.packId);
    await _cache.markManifestSync(manifest.packId);

    final upToDate = local != null &&
        local.packVersion == manifest.currentVersion &&
        local.hashSha256 == manifest.hashSha256;

    if (upToDate) {
      _logger.d('ManifestSync: ${manifest.packId} à jour (v${local.packVersion}).');
      return;
    }

    if (!manifest.enabled) {
      _logger.i('ManifestSync: ${manifest.packId} désactivé — skip.');
      return;
    }

    _logger.i(
      'ManifestSync: ${manifest.packId} '
      '${local == null ? "nouveau" : "v${local.packVersion}"} → v${manifest.currentVersion} (download)',
    );

    final List<Devinette> devinettes;
    try {
      devinettes = await _remote.downloadAndParse(manifest);
    } on RemotePackException catch (e, st) {
      _swallowAndLog(e, st);
      return;
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
  }

  bool _isCompleted(Future<void> f) {
    // Future doesn't expose synchronous completion state directly; we rely
    // on the fact that we attached `.catchError` so any error is swallowed
    // and the future resolves. We mark completion via a guard.
    var done = false;
    f.whenComplete(() => done = true);
    return done;
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
