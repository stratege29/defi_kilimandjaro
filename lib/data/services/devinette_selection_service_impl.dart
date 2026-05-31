import 'dart:math';

import 'package:defi_kilimandjaro/data/local/seen_devinette_store.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:defi_kilimandjaro/domain/services/devinette_selection_service.dart';
import 'package:defi_kilimandjaro/domain/services/seen_devinette_tracker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Implémentation par défaut du [DevinetteSelectionService].
///
/// S'appuie sur [DevinetteRepository.loadPack] : le chargement (et donc le
/// merge bundle+cache+remote) reste la responsabilité du repository.
/// Le service ne fait que sélectionner une devinette dans le pool combiné.
class WeightedDevinetteSelectionService implements DevinetteSelectionService {
  WeightedDevinetteSelectionService({
    required DevinetteRepository repository,
    SeenDevinetteTracker? seenTracker,
    Random? rng,
  }) : _repo = repository,
       _seenTracker = seenTracker,
       _rng = rng ?? Random();

  final DevinetteRepository _repo;

  /// Tracker anti-répétition (optionnel). Quand présent, ses exclusions
  /// "déjà vu" (scopées au pack, avec garantie de fraîcheur ≥ 20 %) sont
  /// fusionnées avec les `excludeIds` du caller pour chaque pack tenté.
  /// Nullable pour rester injectable par les tests sans dépendance prefs.
  final SeenDevinetteTracker? _seenTracker;

  final Random _rng;

  /// Fallback maximal sur la distance de difficulté (±). 10 = largement
  /// au-dessus de toute échelle de difficulté envisagée (1–5 actuellement).
  static const int _maxDifficultyDelta = 10;

  @override
  Future<Devinette> nextDevinette({
    required PackMix mix,
    required int targetDifficulty,
    required Set<String> excludeIds,
    int? wordLengthBucket,
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

      // Fusionne les exclusions "déjà vu" (scopées à ce pack, avec
      // garantie de fraîcheur ≥ 20 % via le tracker) avec celles du
      // caller (`recentDevinetteIds`). `list.length` = packTotalCount
      // effectif post-merge bundle+OTA pour ce pack.
      final effectiveExclude = _seenTracker == null
          ? excludeIds
          : <String>{
              ...excludeIds,
              ..._seenTracker.effectiveExclusions(
                packId: packId,
                packTotalCount: list.length,
              ),
            };

      final picked = _pickFromList(
        list: list,
        targetDifficulty: targetDifficulty,
        wordLengthBucket: wordLengthBucket,
        excludeIds: effectiveExclude,
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
  ///
  /// Quand [wordLengthBucket] est fourni, raffine chaque palier de
  /// difficulté par distance croissante au bucket cible de longueur
  /// de mot (avant de remonter au palier suivant). Préserve donc le
  /// matching de difficulté en priorité sur la longueur — la cohérence
  /// de difficulté pèse davantage que la longueur exacte.
  Devinette? _pickFromList({
    required List<Devinette> list,
    required int targetDifficulty,
    required Set<String> excludeIds,
    required Random rng,
    int? wordLengthBucket,
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
      if (pool.isEmpty) continue;

      // Pas de filtrage secondaire : on tire dans le pool de difficulté.
      if (wordLengthBucket == null) {
        return pool[rng.nextInt(pool.length)];
      }

      // Raffinement par bucket de longueur de mot, distance croissante.
      // _maxBucketDelta = 4 suffit (buckets 1..5).
      for (var bucketDelta = 0; bucketDelta <= 4; bucketDelta++) {
        final subPool = pool.where((d) {
          final bucket = _wordLengthBucketFor(d.answer.length);
          return (bucket - wordLengthBucket).abs() == bucketDelta;
        }).toList(growable: false);
        if (subPool.isNotEmpty) {
          return subPool[rng.nextInt(subPool.length)];
        }
      }
      // Filet : pool de difficulté non vide mais aucune longueur ne
      // matche (théoriquement impossible avec bucketDelta jusqu'à 4).
      return pool[rng.nextInt(pool.length)];
    }
    // Dernier filet de sécurité : on a des candidates mais aucune dans
    // [target ± maxDelta] (cas pathologique). On rend la première dispo.
    return filtered.first;
  }

  /// Inverse de `LevelDifficultyResolver._expectedWordLengthForBucket` :
  /// classe une longueur de mot dans un bucket 1..5. Tenu en sync manuel
  /// avec le resolver (un test garde-fou couvre l'aller-retour).
  static int _wordLengthBucketFor(int wordLength) {
    if (wordLength <= 4) return 1;
    if (wordLength <= 6) return 2;
    if (wordLength == 7) return 3;
    if (wordLength == 8) return 4;
    return 5;
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
      seenTracker: ref.watch(seenDevinetteTrackerProvider),
    );
  },
);
