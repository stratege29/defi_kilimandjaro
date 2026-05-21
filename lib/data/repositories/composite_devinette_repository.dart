import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/data/datasources/bundled_devinette_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/sync/manifest_sync_service.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
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
  }) : _bundled = bundled,
       _cache = cache,
       _rng = rng ?? Random();

  final BundledDevinetteDatasource _bundled;
  final LocalDevinetteCacheDatasource _cache;
  final Random _rng;

  @override
  Future<List<Devinette>> loadPack(String packId) async {
    final results = await Future.wait<List<Devinette>>([
      _bundled.loadPack(packId),
      _cache.loadByPack(packId),
    ]);
    final bundled = results[0];
    final cached = results[1];

    if (cached.isEmpty) return bundled;

    // Merge : `cached` peut contenir remotePack ET community ; on dédup par
    // `id`. Les entrées cached supplantent les bundlées.
    final byId = <String, Devinette>{for (final d in bundled) d.id: d};
    for (final d in cached) {
      byId[d.id] = d;
    }
    return List<Devinette>.unmodifiable(byId.values);
  }

  @override
  Future<Devinette> randomFromPack(String packId) async {
    final list = await loadPack(packId);
    if (list.isEmpty) {
      throw StateError('Aucune devinette dans le pack "$packId"');
    }
    return list[_rng.nextInt(list.length)];
  }

  @override
  Future<Devinette> randomFromPackExcluding(
    String packId,
    Iterable<String> excludeIds,
  ) async {
    final list = await loadPack(packId);
    if (list.isEmpty) {
      throw StateError('Aucune devinette dans le pack "$packId"');
    }
    final exclude = excludeIds.toSet();
    final pool = list.where((d) => !exclude.contains(d.id)).toList();
    if (pool.isEmpty) return list[_rng.nextInt(list.length)];
    return pool[_rng.nextInt(pool.length)];
  }

  @override
  Future<Devinette> atIndex(String packId, int index) async {
    final list = await loadPack(packId);
    if (index < 0 || index >= list.length) {
      throw RangeError.index(index, list, 'devinette index for "$packId"');
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

final bundledDevinetteDatasourceProvider = Provider<BundledDevinetteDatasource>(
  (ref) {
    return BundledDevinetteDatasource();
  },
);

final localDevinetteCacheDatasourceProvider =
    Provider<LocalDevinetteCacheDatasource>((ref) {
      return LocalDevinetteCacheDatasource(
        ref.watch(devinetteDatabaseProvider),
      );
    });

/// Datasource Firestore + Storage. Tests : override avec un fake.
final remoteDevinettePackDatasourceProvider =
    Provider<RemoteDevinettePackDatasource>((ref) {
      return RemoteDevinettePackDatasource(
        firestore: FirebaseFirestore.instance,
      );
    });

/// Signal de pression mémoire iOS/Android. Singleton attaché au
/// `WidgetsBinding` — auto-dispose si plus de listener.
final memoryPressureSignalProvider = Provider<MemoryPressureSignal>((ref) {
  final signal = WidgetsBindingMemoryPressureSignal();
  ref.onDispose(signal.dispose);
  return signal;
});

/// Service de synchro des manifests Firestore (+ download des packs Storage).
/// **Ne plus déclencher au boot** (cf. PR #15 — OOM iOS 26). Trigger
/// manuel uniquement depuis `manifestSyncStateProvider` / `MyPacksView`.
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
    memoryPressure: ref.watch(memoryPressureSignalProvider),
    crashlytics: crashlytics,
  );
});

/// State notifier exposant l'état de sync à l'UI (`MyPacksView`).
/// Transitions : `Idle → Syncing → (Success | Error)`.
class ManifestSyncNotifier extends StateNotifier<SyncState> {
  ManifestSyncNotifier(this._service, [this._ref])
      : super(const SyncStateIdle());

  final ManifestSyncService _service;
  final Ref? _ref;

  /// Lance la sync si aucune n'est en cours. Idempotent côté UI : un
  /// double-tap n'enchaîne pas deux passes.
  Future<void> startRefresh() async {
    if (state is SyncStateSyncing) return;
    state = const SyncStateSyncing(progress: 0, currentPackId: null);
    try {
      final report = await _service.refresh(
        onProgress: (p) {
          if (!mounted) return;
          state = SyncStateSyncing(
            progress: p.overallFraction,
            currentPackId: p.currentPackId,
          );
        },
      );
      if (!mounted) return;
      // Si au moins un pack a changé, invalide les compteurs live pour que
      // `MyPacksView` réaffiche le nouveau nombre de devinettes (cache + bundle).
      if (report.hasChanges) {
        _ref?.invalidate(packLiveQuestionCountProvider);
      }
      state = SyncStateSuccess(report);
    } on Object catch (e) {
      if (!mounted) return;
      state = SyncStateError(e.toString());
    }
  }
}

final manifestSyncStateProvider =
    StateNotifierProvider<ManifestSyncNotifier, SyncState>((ref) {
      return ManifestSyncNotifier(
        ref.watch(manifestSyncServiceProvider),
        ref,
      );
    });

/// Compteur "live" du nombre de devinettes disponibles pour un pack —
/// reflète le merge bundle + cache OTA. Invalidé après chaque sync réussie.
final packLiveQuestionCountProvider =
    FutureProvider.family<int, String>((ref, packId) async {
      final repo = ref.watch(compositeDevinetteRepositoryProvider);
      final list = await repo.loadPack(packId);
      return list.length;
    });

/// Provider du repository composite — c'est l'implémentation par défaut
/// utilisée à travers l'app via `devinetteRepositoryProvider` (cf.
/// `devinette_repository_impl.dart`).
final compositeDevinetteRepositoryProvider = Provider<DevinetteRepository>((
  ref,
) {
  return CompositeDevinetteRepository(
    bundled: ref.watch(bundledDevinetteDatasourceProvider),
    cache: ref.watch(localDevinetteCacheDatasourceProvider),
  );
});
