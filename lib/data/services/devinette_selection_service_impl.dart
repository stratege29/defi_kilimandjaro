import 'dart:math';

import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:defi_kilimandjaro/domain/services/devinette_selection_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Implémentation par défaut du [DevinetteSelectionService].
///
/// S'appuie sur [DevinetteRepository.loadPack] : le chargement (et donc le
/// merge bundle+cache+remote) reste la responsabilité du repository.
/// Le service ne fait que sélectionner une devinette dans le pool combiné.
class WeightedDevinetteSelectionService implements DevinetteSelectionService {
  WeightedDevinetteSelectionService({
    required DevinetteRepository repository,
    Random? rng,
  }) : _repo = repository,
       _rng = rng ?? Random();

  final DevinetteRepository _repo;
  final Random _rng;

  /// Fallback maximal sur la distance de difficulté (±). 10 = largement
  /// au-dessus de toute échelle de difficulté envisagée (1–5 actuellement).
  static const int _maxDifficultyDelta = 10;

  @override
  Future<Devinette> nextDevinette({
    required PackMix mix,
    required int targetDifficulty,
    required Set<String> excludeIds,
    int? seed,
  }) async {
    if (mix.weights.isEmpty) {
      throw ArgumentError.value(mix, 'mix', 'PackMix is empty');
    }
    final rng = seed != null ? Random(seed) : _rng;

    // On essaie chaque pack du mix au plus une fois — d'abord celui tiré
    // par la roue, puis on tente les autres en cas d'épuisement total.
    final triedPacks = <String>{};
    final firstPick = _weightedPick(mix.weights, rng);
    final orderedPacks = <String>[firstPick];
    triedPacks.add(firstPick);

    while (orderedPacks.isNotEmpty) {
      final packId = orderedPacks.removeAt(0);
      final list = await _repo.loadPack(packId);

      final picked = _pickFromList(
        list: list,
        targetDifficulty: targetDifficulty,
        excludeIds: excludeIds,
        rng: rng,
      );
      if (picked != null) return picked;

      // Pack épuisé pour ce mix : on tente un autre pack restant
      // (recalcule la roue sur les non-essayés, pour préserver les poids
      // relatifs entre fallbacks).
      final remaining = <String, double>{
        for (final entry in mix.weights.entries)
          if (!triedPacks.contains(entry.key)) entry.key: entry.value,
      };
      if (remaining.isEmpty) break;
      final nextId = _weightedPick(remaining, rng);
      triedPacks.add(nextId);
      orderedPacks.add(nextId);
    }

    throw StateError(
      'DevinetteSelectionService: aucun pack du mix '
      '${mix.weights.keys.toList()} ne contient une devinette compatible '
      '(targetDifficulty=$targetDifficulty, excludeIds=${excludeIds.length}).',
    );
  }

  /// Sélectionne une devinette dans `list` en respectant la difficulté
  /// cible avec fallback progressif (±1, ±2, ...) et en excluant `excludeIds`.
  /// Renvoie `null` si aucune candidate n'est trouvée même au-delà du
  /// delta max.
  Devinette? _pickFromList({
    required List<Devinette> list,
    required int targetDifficulty,
    required Set<String> excludeIds,
    required Random rng,
  }) {
    if (list.isEmpty) return null;
    final filtered = list
        .where((d) => !excludeIds.contains(d.id))
        .toList(growable: false);
    if (filtered.isEmpty) return null;

    for (var delta = 0; delta <= _maxDifficultyDelta; delta++) {
      final pool = filtered.where((d) {
        return (d.difficulty - targetDifficulty).abs() == delta;
      }).toList(growable: false);
      if (pool.isNotEmpty) {
        return pool[rng.nextInt(pool.length)];
      }
    }
    // Dernier filet de sécurité : on a des candidates mais aucune dans
    // [target ± maxDelta] (cas pathologique). On rend la première dispo.
    return filtered.first;
  }

  /// Tirage pondéré classique par cumulative distribution.
  /// Pré-condition : `weights` non vide et tous strictement positifs.
  /// (Garantie par les invariants de [PackMix].)
  static String _weightedPick(Map<String, double> weights, Random rng) {
    final total = weights.values.fold<double>(0, (a, b) => a + b);
    final draw = rng.nextDouble() * total;
    var cumulative = 0.0;
    for (final entry in weights.entries) {
      cumulative += entry.value;
      if (draw <= cumulative) return entry.key;
    }
    // Filet : rounding flottant → renvoie le dernier.
    return weights.keys.last;
  }
}

/// Provider du service de tirage. Branché sur le repo composite par défaut ;
/// les tests peuvent l'overrider pour fournir un fake repo + seed fixe.
final devinetteSelectionServiceProvider = Provider<DevinetteSelectionService>(
  (ref) {
    return WeightedDevinetteSelectionService(
      repository: ref.watch(compositeDevinetteRepositoryProvider),
    );
  },
);
