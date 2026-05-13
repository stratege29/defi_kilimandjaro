import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/data/datasources/bundled_devinette_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/sync/manifest_sync_service.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository qui fusionne :
///   - le starter pack **bundlé** (toujours disponible, offline-first) ;
///   - le **cache local** Drift (packs officiels téléchargés + pack
///     communautaire reconstruit côté serveur).
///
/// La règle de merge est : remote pack/community > bundled (en cas de doublon
/// d'`id`, l'entrée distante remplace celle bundlée). Ainsi un curateur peut
/// corriger une devinette du starter pack sans nouvelle release de l'app.
///
/// L'interface [DevinetteRepository] reste inchangée : aucun consommateur
/// existant n'a besoin de modification.
class CompositeDevinetteRepository implements DevinetteRepository {
  CompositeDevinetteRepository({
    required BundledDevinetteDatasource bundled,
    required LocalDevinetteCacheDatasource cache,
    Random? rng,
  })  : _bundled = bundled,
        _cache = cache,
        _rng = rng ?? Random();

  final BundledDevinetteDatasource _bundled;
  final LocalDevinetteCacheDatasource _cache;
  final Random _rng;

  @override
  Future<List<Devinette>> loadWorld(String worldId) async {
    final results = await Future.wait<List<Devinette>>([
      _bundled.loadWorld(worldId),
      _cache.loadByWorld(worldId),
    ]);
    final bundled = results[0];
    final cached = results[1];

    if (cached.isEmpty) return bundled;

    // Merge : `cached` peut contenir remotePack ET community ; on dédup par
    // `id`. Les entrées cached supplantent les bundlées.
    final byId = <String, Devinette>{
      for (final d in bundled) d.id: d,
    };
    for (final d in cached) {
      byId[d.id] = d;
    }
    return List<Devinette>.unmodifiable(byId.values);
  }

  @override
  Future<Devinette> randomFromWorld(String worldId) async {
    final list = await loadWorld(worldId);
    if (list.isEmpty) {
      throw StateError('Aucune devinette dans le monde "$worldId"');
    }
    return list[_rng.nextInt(list.length)];
  }

  @override
  Future<Devinette> atIndex(String worldId, int index) async {
    final list = await loadWorld(worldId);
    if (index < 0 || index >= list.length) {
      throw RangeError.index(index, list, 'devinette index for "$worldId"');
    }
    return list[index];
  }
}

// =====================================================================
// Riverpod wiring
// =====================================================================

/// Base de données Drift partagée — singleton applicatif.
final devinetteDatabaseProvider = Provider<DevinetteDatabase>((ref) {
  final db = DevinetteDatabase();
  ref.onDispose(db.close);
  return db;
});

final bundledDevinetteDatasourceProvider =
    Provider<BundledDevinetteDatasource>((ref) {
  return BundledDevinetteDatasource();
});

final localDevinetteCacheDatasourceProvider =
    Provider<LocalDevinetteCacheDatasource>((ref) {
  return LocalDevinetteCacheDatasource(ref.watch(devinetteDatabaseProvider));
});

/// Datasource Firestore + Storage. Tests : override avec un fake.
final remoteDevinettePackDatasourceProvider =
    Provider<RemoteDevinettePackDatasource>((ref) {
  return RemoteDevinettePackDatasource(
    firestore: FirebaseFirestore.instance,
  );
});

/// Service de synchro des manifests Firestore (+ download des packs Storage).
/// À déclencher en fire-and-forget après le first-frame.
final manifestSyncServiceProvider = Provider<ManifestSyncService>((ref) {
  FirebaseCrashlytics? crashlytics;
  try {
    crashlytics = FirebaseCrashlytics.instance;
  } on Object {
    crashlytics = null;
  }
  return ManifestSyncService(
    remote: ref.watch(remoteDevinettePackDatasourceProvider),
    cache: ref.watch(localDevinetteCacheDatasourceProvider),
    crashlytics: crashlytics,
  );
});

/// Provider du repository composite — c'est l'implémentation par défaut
/// utilisée à travers l'app via `devinetteRepositoryProvider` (cf.
/// `devinette_repository_impl.dart`).
final compositeDevinetteRepositoryProvider =
    Provider<DevinetteRepository>((ref) {
  return CompositeDevinetteRepository(
    bundled: ref.watch(bundledDevinetteDatasourceProvider),
    cache: ref.watch(localDevinetteCacheDatasourceProvider),
  );
});
