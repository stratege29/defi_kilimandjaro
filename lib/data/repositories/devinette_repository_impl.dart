import 'dart:convert';
import 'dart:math';

import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Legacy : charge les devinettes depuis les assets JSON bundlés dans
/// `assets/data/devinettes/<worldId>.json` (format v1 ou v2).
///
/// **Conservé pour les tests et comme filet de sécurité.** L'implémentation
/// par défaut en production est désormais [CompositeDevinetteRepository]
/// (bundle starter + cache Drift + packs distants).
///
/// Cache mémoire — les fichiers sont chargés une fois puis réutilisés
/// pour toutes les sessions de jeu.
class AssetDevinetteRepository implements DevinetteRepository {
  AssetDevinetteRepository({String basePath = 'assets/data/devinettes'})
    : _basePath = basePath;

  final String _basePath;
  final Map<String, List<Devinette>> _cache = <String, List<Devinette>>{};
  final Random _rng = Random();

  @override
  Future<List<Devinette>> loadWorld(String worldId) async {
    final cached = _cache[worldId];
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('$_basePath/$worldId.json');
    final list = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(Devinette.fromJson)
        .toList(growable: false);

    _cache[worldId] = list;
    return list;
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
  Future<Devinette> randomFromWorldExcluding(
    String worldId,
    Iterable<String> excludeIds,
  ) async {
    final list = await loadWorld(worldId);
    if (list.isEmpty) {
      throw StateError('Aucune devinette dans le monde "$worldId"');
    }
    final exclude = excludeIds.toSet();
    final pool = list.where((d) => !exclude.contains(d.id)).toList();
    // Pool trop petit : fallback sur la liste complète (mieux que de
    // bloquer le jeu).
    if (pool.isEmpty) return list[_rng.nextInt(list.length)];
    return pool[_rng.nextInt(pool.length)];
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

/// Provider public du repository — délègue à la composite (bundled + cache
/// + remote). Les tests peuvent overrider avec [AssetDevinetteRepository]
/// pour rester complètement offline et déterministe.
final devinetteRepositoryProvider = Provider<DevinetteRepository>((ref) {
  return ref.watch(compositeDevinetteRepositoryProvider);
});
