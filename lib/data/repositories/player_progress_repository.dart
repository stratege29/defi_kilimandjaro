import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository de la progression du joueur.
///
/// Stockage en JSON sous une seule clé `player_progress` pour éviter les
/// race conditions multi-clés et faciliter la migration v2 (Firestore).
class PlayerProgressRepository {
  PlayerProgressRepository(this._prefs);

  static const String _key = 'player_progress';

  final SharedPreferences _prefs;

  /// Lit l'état actuel ou retourne l'état initial.
  PlayerProgress load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return PlayerProgress.initial();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PlayerProgress.fromJson(json);
    } on FormatException {
      return PlayerProgress.initial();
    }
  }

  /// Persiste un nouvel état.
  Future<void> save(PlayerProgress progress) async {
    await _prefs.setString(_key, jsonEncode(progress.toJson()));
  }

  /// Reset complet (utilisé par le bouton réinitialisation Profil Phase 3).
  Future<void> reset() async {
    await _prefs.remove(_key);
  }
}

/// Initialisé async au boot via override dans `main.dart`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart with the '
    'resolved SharedPreferences instance.',
  ),
);

final playerProgressRepositoryProvider =
    Provider<PlayerProgressRepository>((ref) {
  return PlayerProgressRepository(ref.watch(sharedPreferencesProvider));
});

/// État courant de la progression — lu une fois au boot puis muté via
/// [PlayerProgressNotifier].
class PlayerProgressNotifier extends StateNotifier<PlayerProgress> {
  PlayerProgressNotifier(this._repo) : super(_repo.load());

  final PlayerProgressRepository _repo;

  /// Récompense après une victoire sur une montagne donnée.
  ///
  /// `coinsAwarded` = base 30 + bonus vitesse (timeLeft × 2).
  /// Reset le compteur d'échecs consécutifs.
  Future<void> recordWin({
    required String? mountainId,
    required int coinsAwarded,
  }) async {
    final levels = Map<String, int>.from(state.completedLevelsByMountain);
    if (mountainId != null) {
      levels[mountainId] = (levels[mountainId] ?? 0) + 1;
    }

    final newState = state.copyWith(
      coins: state.coins + coinsAwarded,
      completedLevelsByMountain: levels,
      totalLevelsCompleted: state.totalLevelsCompleted + 1,
      lastPlayDate: DateTime.now(),
      consecutiveFailures: 0,
    );
    state = newState;
    await _repo.save(newState);
  }

  /// Incrémente le compteur d'échecs consécutifs (utilisé pour
  /// déclencher l'interstitielle toutes les 3 défaites).
  Future<int> recordFailure() async {
    final newCount = state.consecutiveFailures + 1;
    final newState = state.copyWith(consecutiveFailures: newCount);
    state = newState;
    await _repo.save(newState);
    return newCount;
  }

  /// Marque l'achat "No-Ads" comme accordé. Idempotent.
  Future<void> grantNoAds() async {
    if (state.noAdsPurchased) return;
    final newState = state.copyWith(noAdsPurchased: true);
    state = newState;
    await _repo.save(newState);
  }

  /// Déduit le coût d'un indice. Retourne `false` si solde insuffisant.
  Future<bool> spendOnHint(int cost) async {
    if (state.coins < cost) return false;
    final newState = state.copyWith(coins: state.coins - cost);
    state = newState;
    await _repo.save(newState);
    return true;
  }

  /// Ajoute des coins au solde (utilisé par les achats IAP et les pubs
  /// rewarded vidéo en Phase 4.2).
  Future<void> addCoins(int amount) async {
    if (amount <= 0) return;
    final newState = state.copyWith(coins: state.coins + amount);
    state = newState;
    await _repo.save(newState);
  }

  /// Réinitialisation depuis l'écran Profil.
  Future<void> reset() async {
    await _repo.reset();
    state = PlayerProgress.initial();
  }
}

final playerProgressProvider =
    StateNotifierProvider<PlayerProgressNotifier, PlayerProgress>((ref) {
  return PlayerProgressNotifier(ref.watch(playerProgressRepositoryProvider));
});
