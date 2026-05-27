import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/daily_challenge_repository.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Implémentation **bundle** du repo daily : lit le seed embarqué dans
/// l'APK (`assets/data/daily_challenges_seed.json`), applique un shuffle
/// annuel déterministe et indexe par `dayOfYear`.
///
/// Pourquoi un shuffle annuel ? Si on indexait directement par
/// `dayOfYear % pool.length`, les joueurs anciens reverraient les mêmes
/// mots aux mêmes dates (ex. "FOUTOU le 1er janvier de chaque année").
/// La permutation seedée sur l'année casse ce pattern tout en restant
/// reproductible (tous les joueurs du monde voient le même mot le
/// même jour).
///
/// Pool actuel : 15 entrées seed. À étendre à 90 via `devinette-curator`
/// (effort éditorial hors scope de cette PR).
class BundleDailyChallengeRepository implements DailyChallengeRepository {
  BundleDailyChallengeRepository({
    String assetPath = _defaultAssetPath,
  }) : _assetPath = assetPath;

  static const String _defaultAssetPath =
      'assets/data/daily_challenges_seed.json';

  final String _assetPath;

  /// Cache mémoire (load 1×/session). Pas de TTL — le bundle ne change
  /// pas pendant la session.
  List<Devinette>? _cache;

  /// Cache par année (year → permutation d'indices). Évite de
  /// recalculer le shuffle à chaque appel. Reset si l'année change
  /// pendant la session (cas pathologique : passage minuit du
  /// 31 décembre).
  final Map<int, List<int>> _permCacheByYear = <int, List<int>>{};

  @override
  Future<Devinette?> fetchDevinetteForDate(DateTime date) async {
    final pool = await _loadPool();
    if (pool.isEmpty) return null;
    final perm = _permutationForYear(date.year, pool.length);
    final dayIdx = _dayOfYear(date) - 1; // 0-based
    final selected = perm[dayIdx % perm.length];
    return pool[selected];
  }

  Future<List<Devinette>> _loadPool() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final parsed = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Devinette.fromJson)
          .toList();
      _cache = parsed;
      return parsed;
    } on Object {
      // Asset manquant ou JSON corrompu — on retourne un pool vide
      // plutôt que de propager une exception au call-site UI.
      _cache = const <Devinette>[];
      return _cache!;
    }
  }

  /// Génère une permutation déterministe de `[0, poolLen)` pour `year`.
  /// Algorithme : Fisher-Yates seedé par le hash FNV-1a de l'année.
  /// Bit-identique cross-platform.
  List<int> _permutationForYear(int year, int poolLen) {
    final cached = _permCacheByYear[year];
    if (cached != null && cached.length == poolLen) return cached;

    final perm = List<int>.generate(poolLen, (i) => i);
    var hash = _fnv1a32(year.toString());
    // Fisher-Yates : pour chaque position de la fin vers le début,
    // on échange avec une position aléatoire ≤ courante.
    for (var i = poolLen - 1; i > 0; i--) {
      // PRNG simple basé sur le hash (multiplicateur LCG standard).
      hash = (hash * 1664525 + 1013904223) & 0xFFFFFFFF;
      final j = hash % (i + 1);
      final tmp = perm[i];
      perm[i] = perm[j];
      perm[j] = tmp;
    }

    _permCacheByYear[year] = perm;
    return perm;
  }

  /// Jour de l'année (1..366). Gère les années bissextiles via
  /// `DateTime.difference`.
  static int _dayOfYear(DateTime date) {
    final yearStart = DateTime(date.year);
    return date.difference(yearStart).inDays + 1;
  }

  static int _fnv1a32(String input) {
    const fnvOffset = 0x811c9dc5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final code in input.codeUnits) {
      hash ^= code;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}
