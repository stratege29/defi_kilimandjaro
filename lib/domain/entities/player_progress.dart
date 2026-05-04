import 'package:equatable/equatable.dart';

/// Snapshot persistant de la progression du joueur.
///
/// Persisté via shared_preferences (Phase 2.3, v1).
/// Évolution v2 : sync Firestore quand authentifié (Phase 4 + multijoueur).
class PlayerProgress extends Equatable {
  const PlayerProgress({
    required this.coins,
    required this.completedLevelsByMountain,
    required this.totalLevelsCompleted,
    required this.dailyStreak,
    this.lastPlayDate,
    this.consecutiveFailures = 0,
    this.noAdsPurchased = false,
  });

  /// État initial pour un nouveau joueur.
  factory PlayerProgress.initial() => const PlayerProgress(
        coins: 120,
        completedLevelsByMountain: <String, int>{},
        totalLevelsCompleted: 0,
        dailyStreak: 0,
      );

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    return PlayerProgress(
      coins: (json['coins'] as int?) ?? 120,
      completedLevelsByMountain:
          ((json['levels'] as Map<String, dynamic>?) ?? <String, dynamic>{})
              .map((k, v) => MapEntry(k, v as int)),
      totalLevelsCompleted: (json['total'] as int?) ?? 0,
      dailyStreak: (json['streak'] as int?) ?? 0,
      lastPlayDate: json['last_play'] == null
          ? null
          : DateTime.tryParse(json['last_play'] as String),
      consecutiveFailures: (json['consecutive_failures'] as int?) ?? 0,
      noAdsPurchased: (json['no_ads'] as bool?) ?? false,
    );
  }

  /// Solde de Coins de Sagesse.
  final int coins;

  /// Niveaux complétés par montagne (mountainId → count).
  final Map<String, int> completedLevelsByMountain;

  /// Total cumul de niveaux gagnés (utile pour titres honorifiques).
  final int totalLevelsCompleted;

  /// Streak quotidienne.
  final int dailyStreak;

  /// Dernière date de jeu (jour calendaire, sans heure).
  final DateTime? lastPlayDate;

  /// Compteur d'échecs consécutifs (reset à chaque victoire).
  /// Sert de trigger pour l'interstitielle (cf. plan.md §4 — 1 sur 3 échecs).
  final int consecutiveFailures;

  /// Achat non-consumable "Supprimer les pubs" (4,99 €).
  final bool noAdsPurchased;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'coins': coins,
        'levels': completedLevelsByMountain,
        'total': totalLevelsCompleted,
        'streak': dailyStreak,
        'last_play': lastPlayDate?.toIso8601String(),
        'consecutive_failures': consecutiveFailures,
        'no_ads': noAdsPurchased,
      };

  /// Combien de niveaux complétés sur cette montagne.
  int levelsOn(String mountainId) =>
      completedLevelsByMountain[mountainId] ?? 0;

  PlayerProgress copyWith({
    int? coins,
    Map<String, int>? completedLevelsByMountain,
    int? totalLevelsCompleted,
    int? dailyStreak,
    DateTime? lastPlayDate,
    int? consecutiveFailures,
    bool? noAdsPurchased,
  }) {
    return PlayerProgress(
      coins: coins ?? this.coins,
      completedLevelsByMountain:
          completedLevelsByMountain ?? this.completedLevelsByMountain,
      totalLevelsCompleted: totalLevelsCompleted ?? this.totalLevelsCompleted,
      dailyStreak: dailyStreak ?? this.dailyStreak,
      lastPlayDate: lastPlayDate ?? this.lastPlayDate,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      noAdsPurchased: noAdsPurchased ?? this.noAdsPurchased,
    );
  }

  @override
  List<Object?> get props => [
        coins,
        completedLevelsByMountain,
        totalLevelsCompleted,
        dailyStreak,
        lastPlayDate,
        consecutiveFailures,
        noAdsPurchased,
      ];
}
