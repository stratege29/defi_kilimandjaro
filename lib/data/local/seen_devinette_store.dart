import 'dart:convert';

import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/services/seen_devinette_tracker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implémentation [SeenDevinetteTracker] persistée via SharedPreferences.
///
/// Stockage : une **unique clé** [_storageKey] = JSON objet
/// `{packId: [devinetteId, ...]}`. L'ordre de la liste = ordre d'insertion
/// = ordre FIFO d'éviction (le 0-ème est le plus ancien).
///
/// Pourquoi une seule clé plutôt qu'une clé par pack :
/// - reset atomique (un `remove`) ;
/// - migration v2 → Firestore plus simple (un seul document à syncer) ;
/// - SharedPreferences n'aime pas la prolifération de clés.
///
/// Pourquoi un cache mémoire éager :
/// - [effectiveExclusions] est appelé sur chaque tirage : O(décode JSON)
///   par appel serait inacceptable.
/// - Le cache est sourcé une seule fois au boot (constructeur), puis muté
///   en mémoire à chaque `markSolved`. La persistance est best-effort
///   (await, mais une erreur SharedPreferences ne casse pas le tirage —
///   au pire on perd l'historique au prochain reboot).
class SeenDevinetteStore implements SeenDevinetteTracker {
  /// Construit le store en lisant immédiatement l'état persisté.
  /// L'instance est utilisable dès la sortie du constructeur (lecture
  /// synchrone via [SharedPreferences]).
  SeenDevinetteStore(this._prefs) {
    _loadFromPrefs();
  }

  static const String _storageKey = 'seen_devinettes_v1';

  /// Cap dur de stockage par pack — protège SharedPreferences d'un
  /// ballonnement à long terme (utilisateur ultra-actif).
  /// 1000 ≫ taille de tout pack envisagé (le plus gros, `culture_ci`,
  /// est à 180). Au-delà, on évince les plus anciennes en FIFO.
  static const int _hardCapPerPack = 1000;

  /// Seuil sous lequel le pool "non-vu" doit rester pour éviter la
  /// monotonie. `0.20` = 20 % minimum de fraîcheur garantie. Valeur
  /// d'invariant produit verrouillée (pas un paramètre de runtime).
  static const double _freshPoolRatio = 0.20;

  final SharedPreferences _prefs;

  /// Cache mémoire : packId -> liste d'IDs (ordre FIFO).
  /// Mutable in-place pour les appends ; les copies défensives sont
  /// faites au moment d'exposer (cf. [seenForPack]).
  final Map<String, List<String>> _cache = <String, List<String>>{};

  void _loadFromPrefs() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      for (final entry in json.entries) {
        final value = entry.value;
        if (value is! List) continue;
        _cache[entry.key] = <String>[
          for (final v in value)
            if (v is String) v,
        ];
      }
    } on FormatException {
      // Corruption stockage : on repart à zéro plutôt que de crasher.
      _cache.clear();
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_cache);
    await _prefs.setString(_storageKey, encoded);
  }

  @override
  Future<void> markSolved({
    required String packId,
    required String devinetteId,
  }) async {
    if (packId.isEmpty || devinetteId.isEmpty) return;
    // Idempotence : si déjà présent, on le retire pour le ré-insérer en
    // fin de liste (devient le plus récent). Promotion explicite pour que
    // la FIFO reflète bien la dernière interaction.
    final list = _cache.putIfAbsent(packId, () => <String>[])
      ..remove(devinetteId)
      ..add(devinetteId);

    // Cap dur : on évince les plus anciennes au-delà de [_hardCapPerPack].
    while (list.length > _hardCapPerPack) {
      list.removeAt(0);
    }
    await _persist();
  }

  @override
  Set<String> effectiveExclusions({
    required String packId,
    required int packTotalCount,
  }) {
    if (packTotalCount <= 0) return const <String>{};
    final seen = _cache[packId];
    if (seen == null || seen.isEmpty) return const <String>{};

    // Seuil max d'IDs exclus : on garantit `freshPoolRatio` de fraîcheur.
    // `floor` plutôt que `round` pour rester strictement >= seuil produit.
    final maxExcluded = (packTotalCount * (1 - _freshPoolRatio)).floor();

    if (seen.length <= maxExcluded) {
      // Pool non-vu encore ≥ 20 % du total → exclusion stricte de tout.
      return Set<String>.unmodifiable(seen);
    }

    // Pool sous le seuil : on garde uniquement les `maxExcluded` plus
    // récentes (queue de la liste). Les plus anciennes sont
    // ré-introduites dans le pool éligible.
    if (maxExcluded <= 0) return const <String>{};
    final keepFrom = seen.length - maxExcluded;
    return Set<String>.unmodifiable(seen.sublist(keepFrom));
  }

  @override
  List<String> seenForPack(String packId) {
    final list = _cache[packId];
    if (list == null) return const <String>[];
    return List<String>.unmodifiable(list);
  }

  @override
  Future<void> clearAll() async {
    _cache.clear();
    await _prefs.remove(_storageKey);
  }
}

/// Provider du tracker — partage la même instance [SharedPreferences]
/// que [playerProgressRepositoryProvider]. Lazy : la première lecture
/// déclenche le chargement synchrone du cache.
final seenDevinetteTrackerProvider = Provider<SeenDevinetteTracker>((ref) {
  return SeenDevinetteStore(ref.watch(sharedPreferencesProvider));
});
