import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/repositories/pack_catalog_repository.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Charge le catalogue des packs depuis `assets/data/devinettes/starter/_index.json`.
///
/// Format attendu (v3) :
/// ```json
/// {
///   "format_version": 3,
///   "packs": {
///     "<packId>": {
///       "file": "<packId>.json",
///       "count": <int>,
///       "name_key": "pack.<packId>.name",
///       "description_key": "pack.<packId>.description",
///       "free_choice_eligible": <bool>,
///       "price_eur": <num>,
///       "price_cauris": <int>
///     }
///   }
/// }
/// ```
///
/// Cache mémoire (le fichier ne change pas au runtime). Pour les tests,
/// passer un `assetLoader` pour bypass `rootBundle`.
class BundledPackCatalogRepository implements PackCatalogRepository {
  BundledPackCatalogRepository({
    String indexPath = 'assets/data/devinettes/starter/_index.json',
    Future<String> Function(String path)? assetLoader,
  }) : _indexPath = indexPath,
       _loadAsset = assetLoader ?? rootBundle.loadString;

  final String _indexPath;
  final Future<String> Function(String path) _loadAsset;

  List<Pack>? _cache;

  @override
  Future<List<Pack>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _loadAsset(_indexPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      _cache = const <Pack>[];
      return _cache!;
    }
    final packsNode = decoded['packs'];
    if (packsNode is! Map<String, dynamic>) {
      _cache = const <Pack>[];
      return _cache!;
    }

    final packs = <Pack>[];
    for (final entry in packsNode.entries) {
      final body = entry.value;
      if (body is! Map<String, dynamic>) continue;
      packs.add(Pack.fromIndexEntry(entry.key, body));
    }
    _cache = List<Pack>.unmodifiable(packs);
    return _cache!;
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
}

final packCatalogRepositoryProvider = Provider<PackCatalogRepository>((ref) {
  return BundledPackCatalogRepository();
});

/// Liste complète des packs disponibles dans le bundle. AsyncValue pour
/// que la couche présentation puisse afficher un loader/erreur sans coupler
/// à `rootBundle`.
final packCatalogProvider = FutureProvider<List<Pack>>((ref) {
  return ref.watch(packCatalogRepositoryProvider).loadAll();
});

/// Packs éligibles au choix gratuit — branché à l'écran d'onboarding.
final freePackCandidatesProvider = FutureProvider<List<Pack>>((ref) {
  return ref.watch(packCatalogRepositoryProvider).freeChoiceCandidates();
});
