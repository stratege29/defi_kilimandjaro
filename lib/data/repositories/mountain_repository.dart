import 'dart:convert';

import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/services/star_gate.dart';
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
/// Une montagne est déverrouillée si **les deux conditions** sont remplies :
/// 1. **Progression** — la montagne précédente est 100 % complétée (rang 0
///    toujours ouvert pour amorcer).
/// 2. **Star-gate** — les étoiles cumulées du joueur permettent d'accéder
///    au tier de cette montagne (cf. `StarGate.computeUnlockedTier`).
///    Pas de porte entre Tier 1 et Tier 2 ; portes à 30/120/250 ★ pour
///    franchir vers T3/T4/T5.
///
/// Quand seule la star-gate bloque (progression OK mais étoiles
/// insuffisantes), [Mountain.starsRequiredToUnlock] expose le nombre
/// d'étoiles manquantes pour que l'UI affiche le bon message.
final mountainsProvider = FutureProvider<List<Mountain>>((ref) async {
  final raw = await ref.watch(_rawMountainsProvider.future);
  final progress = ref.watch(playerProgressProvider);
  final totalStars = progress.totalStars;
  final unlockedTier = StarGate.computeUnlockedTier(totalStars);

  final result = <Mountain>[];
  var previousCompleted = true; // permet d'ouvrir le rang 0
  for (final m in raw) {
    final completed = progress.levelsOn(m.id);
    final progressionOk = previousCompleted;
    final mountainTier = LevelDifficultyResolver.tierForAltitude(m.altitude);
    final starGateOk = mountainTier <= unlockedTier;

    final isUnlocked = progressionOk && starGateOk;
    // On expose le nombre d'étoiles manquantes uniquement quand
    // **seule la star-gate bloque** — sinon l'UX cumule deux messages
    // contradictoires ("termine le sommet précédent" + "il te manque
    // N ★") qui brouillent la cause réelle.
    final starsRequired = (progressionOk && !starGateOk)
        ? StarGate.starsNeededForTier(
            targetTier: mountainTier,
            currentTotal: totalStars,
          )
        : null;

    result.add(
      m.copyWith(
        completedLevels: completed,
        unlocked: isUnlocked,
        starsRequiredToUnlock: starsRequired,
      ),
    );
    previousCompleted = completed >= m.totalLevels;
  }
  return result;
});
