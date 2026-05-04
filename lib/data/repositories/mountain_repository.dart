import 'dart:convert';

import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Source des montagnes africaines (51 entrées, une par pays).
///
/// Triées par altitude croissante, du Red Rocks de Gambie (53 m)
/// jusqu'au Kilimandjaro (5 895 m, Tanzanie) — boss final.
/// Charge les 51 montagnes d'Afrique depuis le JSON bundlé.
class MountainRepository {
  MountainRepository();

  static const String _path = 'assets/data/mountains.json';
  List<Mountain>? _cache;

  /// Charge la liste brute (triée par altitude croissante, sans état).
  /// L'état unlocked/completed est dérivé dans [mountainsProvider].
  Future<List<Mountain>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_path);
    final parsed = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(Mountain.fromJson)
        .toList()
      ..sort((a, b) => a.altitude.compareTo(b.altitude));

    _cache = parsed;
    return parsed;
  }
}

final mountainRepositoryProvider = Provider<MountainRepository>((ref) {
  return MountainRepository();
});

/// Liste brute des 51 montagnes triées par altitude (sans état joueur).
final _rawMountainsProvider = FutureProvider<List<Mountain>>((ref) async {
  return ref.watch(mountainRepositoryProvider).loadAll();
});

/// Liste prête à afficher : altitude croissante + statut unlocked/completed
/// dérivé de la progression du joueur.
///
/// Règle d'ouverture : rang 0 toujours ouvert ; rang N ouvert si le rang
/// N-1 a tous ses niveaux complétés.
final mountainsProvider = FutureProvider<List<Mountain>>((ref) async {
  final raw = await ref.watch(_rawMountainsProvider.future);
  final progress = ref.watch(playerProgressProvider);

  final result = <Mountain>[];
  var previousCompleted = true; // permet d'ouvrir le rang 0
  for (final m in raw) {
    final completed = progress.levelsOn(m.id);
    final isUnlocked = previousCompleted;
    result.add(
      m.copyWith(
        completedLevels: completed,
        unlocked: isUnlocked,
      ),
    );
    previousCompleted = completed >= m.totalLevels;
  }
  return result;
});
