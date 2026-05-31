import 'dart:async';

import 'package:defi_kilimandjaro/data/datasources/remote_catalog_datasource.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/repositories/pack_catalog_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository composite qui fusionne le catalogue bundle (offline-first) et
/// le catalogue distant (Firestore `catalog/index`, Phase 3 backoffice).
///
/// **Stratégie de fusion** :
///   - Bundle = source de vérité offline (toujours dispo dès le boot)
///   - Remote = override + extension (rules dynamiques + nouveaux packs)
///   - Pour un même `id` : `bundle.mergeWithRemote(remote)` (cf Pack.mergeWithRemote)
///   - Packs présents uniquement en bundle : conservés tels quels
///   - Packs présents uniquement en remote : ajoutés (PackSource.remote)
///   - Packs présents en remote avec `visible: false` : exclus du résultat
///   - Packs avec fenêtre `availability` expirée : exclus du résultat
///
/// **Pas d'auto-fetch au boot** (cf OTA v0.2). Le composite retourne d'abord
/// le bundle + cache disque s'il existe. Un fetch réel n'est déclenché que
/// par `refresh()` (appel manuel UI) ou par `watchLive()` (stream UI ouverte).
class CompositePackCatalogRepository implements PackCatalogRepository {
  CompositePackCatalogRepository({
    required this.bundle,
    required this.remote,
  });

  final BundledPackCatalogRepository bundle;
  final RemoteCatalogDatasource remote;

  /// Cache du dernier snapshot remote chargé (depuis disque OU fetch réseau).
  RemoteCatalogSnapshot? _remoteSnapshot;

  /// Cache mémoire du résultat fusionné. Invalidé par `refresh()`.
  List<Pack>? _mergedCache;

  /// Future en cours d'hydration depuis le cache disque (1 seule fois).
  Future<void>? _hydrating;

  /// Charge le snapshot remote depuis le cache disque s'il existe.
  /// Idempotent — appelle 1 seule fois en lazy.
  ///
  /// **Ne pas écraser** `_remoteSnapshot` s'il a déjà été setté par un
  /// `refresh()` réussi avant nous (sinon on annule le fetch réseau et on
  /// repart sur le cache disque potentiellement vide).
  Future<void> _hydrateFromDiskOnce() {
    return _hydrating ??= () async {
      try {
        final cached = await remote.loadCache();
        if (cached != null && _remoteSnapshot == null) {
          _remoteSnapshot = cached;
        }
      } catch (_) {
        // Best effort
      }
    }();
  }

  /// Snapshot remote courant (depuis cache disque OU dernier fetch réseau).
  /// Null si on n'a jamais vu de remote (premier lancement, ou erreur).
  RemoteCatalogSnapshot? get currentRemoteSnapshot => _remoteSnapshot;

  // ===========================================================================
  // PackCatalogRepository interface
  // ===========================================================================

  @override
  Future<List<Pack>> loadAll() async {
    final cached = _mergedCache;
    if (cached != null) return cached;

    await _hydrateFromDiskOnce();
    final result = await _merge();
    _mergedCache = List<Pack>.unmodifiable(result);
    return _mergedCache!;
  }

  @override
  Future<Pack?> byId(String packId) async {
    final all = await loadAll();
    for (final p in all) {
      if (p.id == packId) return p;
    }
    return null;
  }

  @override
  Future<List<Pack>> freeChoiceCandidates() async {
    final all = await loadAll();
    return all.where((p) => p.freeChoiceEligible).toList(growable: false);
  }

  // ===========================================================================
  // Sync explicite (déclenché par UI)
  // ===========================================================================

  /// Force un fetch réseau du remote catalog.
  ///
  /// Met à jour le snapshot remote en mémoire + cache disque, invalide le
  /// cache fusionné. Retourne le nouveau snapshot.
  ///
  /// Throw [Exception] si le fetch échoue — l'appelant doit catch pour
  /// décider de l'UX (snackbar erreur, fallback silencieux).
  Future<RemoteCatalogSnapshot?> refresh() async {
    final snapshot = await remote.fetch();
    if (snapshot != null) {
      _remoteSnapshot = snapshot;
      _mergedCache = null; // invalide pour forcer re-merge au prochain loadAll
    }
    return snapshot;
  }

  /// Stream live du catalogue fusionné. Émet à chaque update du remote.
  ///
  /// Utile pour les écrans ouverts longtemps (MyPacksView) — si un admin
  /// publie une nouvelle version pendant la session, l'UI se rafraîchit
  /// automatiquement.
  Stream<List<Pack>> watchLive() {
    return remote.watch().asyncMap((snapshot) async {
      if (snapshot != null) {
        _remoteSnapshot = snapshot;
        _mergedCache = null;
      }
      return loadAll();
    });
  }

  // ===========================================================================
  // Logique de merge
  // ===========================================================================

  Future<List<Pack>> _merge() async {
    final bundlePacks = await bundle.loadAll();
    final remoteSnapshot = _remoteSnapshot;

    if (remoteSnapshot == null) {
      // Pas de remote — retourne bundle tel quel (offline-first)
      return _applyVisibilityFilters(bundlePacks);
    }

    final bundleById = {for (final p in bundlePacks) p.id: p};
    final remoteById = {for (final p in remoteSnapshot.packs) p.id: p};
    final allIds = {...bundleById.keys, ...remoteById.keys};

    final merged = <Pack>[];
    for (final id in allIds) {
      final b = bundleById[id];
      final r = remoteById[id];
      if (b != null && r != null) {
        merged.add(b.mergeWithRemote(r));
      } else if (b != null) {
        // Bundle only — pas dans remote. Si remote dispo mais pack absent,
        // c'est probablement un retrait → on respecte `visible: true` par
        // défaut, mais le composite peut être configuré pour exclure (TODO).
        merged.add(b);
      } else if (r != null) {
        merged.add(r);
      }
    }

    // Tri par ordering (asc) — le remote a la priorité, le bundle a 100 par défaut
    merged.sort((a, b) => a.ordering.compareTo(b.ordering));

    return _applyVisibilityFilters(merged);
  }

  /// Filtre : `visible: true` ET dans fenêtre `availability`.
  List<Pack> _applyVisibilityFilters(List<Pack> packs) {
    return packs
        .where((p) => p.visible && p.isWithinAvailability)
        .toList(growable: false);
  }
}

// ===========================================================================
// Providers Riverpod
// ===========================================================================

/// Datasource Firestore + cache disque pour le catalog remote.
final remoteCatalogDatasourceProvider = Provider<RemoteCatalogDatasource>((ref) {
  return RemoteCatalogDatasource();
});

/// Le repository composite (bundle + remote).
///
/// Override le `packCatalogRepositoryProvider` original pour que tous les
/// consumers existants (my_packs, pack_chooser, packs_section, news_carousel)
/// utilisent automatiquement le composite sans aucun changement de code.
final compositePackCatalogRepositoryProvider =
    Provider<CompositePackCatalogRepository>((ref) {
  return CompositePackCatalogRepository(
    bundle: BundledPackCatalogRepository(),
    remote: ref.watch(remoteCatalogDatasourceProvider),
  );
});

/// Override du provider historique pour pointer sur le composite.
/// Active automatiquement le remote pour tous les consumers existants.
final packCatalogRepositoryOverride =
    packCatalogRepositoryProvider.overrideWith((ref) {
  return ref.watch(compositePackCatalogRepositoryProvider);
});

/// Action UI : déclenche un refresh remote + invalide les providers en aval.
///
/// Usage : `await ref.read(refreshRemoteCatalogProvider.future);`
/// Throw l'exception réseau si fetch échoue — l'UI doit la catch.
final refreshRemoteCatalogProvider = FutureProvider.autoDispose<
    RemoteCatalogSnapshot?>((ref) async {
  final composite = ref.read(compositePackCatalogRepositoryProvider);
  final snapshot = await composite.refresh();
  // Invalide les providers en aval pour rebuild les UI consumers
  ref.invalidate(packCatalogProvider);
  ref.invalidate(freePackCandidatesProvider);
  return snapshot;
});

/// Snapshot remote courant (cache + dernier fetch). Pour afficher
/// "Synchronisé il y a X min" dans MyPacksView.
final currentRemoteCatalogSnapshotProvider =
    Provider<RemoteCatalogSnapshot?>((ref) {
  return ref.watch(compositePackCatalogRepositoryProvider).currentRemoteSnapshot;
});
