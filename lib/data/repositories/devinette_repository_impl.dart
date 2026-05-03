import 'dart:convert';
import 'dart:math';

import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Implémentation par défaut : charge les devinettes depuis les assets JSON
/// bundlés dans `assets/data/devinettes/<worldId>.json`.
///
/// Cache mémoire — les fichiers sont chargés une fois puis réutilisés
/// pour toutes les sessions de jeu.
class AssetDevinetteRepository implements DevinetteRepository {
  AssetDevinetteRepository();

  final Map<String, List<Devinette>> _cache = <String, List<Devinette>>{};
  final Random _rng = Random();

  static const String _basePath = 'assets/data/devinettes';

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
  Future<Devinette> atIndex(String worldId, int index) async {
    final list = await loadWorld(worldId);
    if (index < 0 || index >= list.length) {
      throw RangeError.index(index, list, 'devinette index for "$worldId"');
    }
    return list[index];
  }
}

/// Riverpod singleton.
final devinetteRepositoryProvider = Provider<DevinetteRepository>((ref) {
  return AssetDevinetteRepository();
});
