import 'package:equatable/equatable.dart';

/// Fiche d'un participant à un tournoi — vue du classement live et final.
///
/// Mappe `tournaments/{tid}/participants/{uid}`. `rank` / `rewardCauris` /
/// `rewardBadge` ne sont renseignés qu'après la finalisation (server-side).
class TournamentParticipant extends Equatable {
  const TournamentParticipant({
    required this.uid,
    required this.displayName,
    required this.points,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.currentStreak,
    this.avatarId,
    this.rank,
    this.rewardCauris,
    this.rewardBadge,
  });

  factory TournamentParticipant.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) {
    final rawName = data['display_name'] as String?;
    return TournamentParticipant(
      uid: uid,
      displayName:
          (rawName?.isNotEmpty ?? false) ? rawName! : 'Grimpeur anonyme',
      avatarId: data['avatar_id'] as String?,
      points: (data['points'] as num?)?.toInt() ?? 0,
      matchesPlayed: (data['matches_played'] as num?)?.toInt() ?? 0,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      losses: (data['losses'] as num?)?.toInt() ?? 0,
      currentStreak: (data['current_streak'] as num?)?.toInt() ?? 0,
      rank: (data['rank'] as num?)?.toInt(),
      rewardCauris: (data['reward_cauris'] as num?)?.toInt(),
      rewardBadge: data['reward_badge'] as String?,
    );
  }

  final String uid;
  final String displayName;
  final String? avatarId;
  final int points;
  final int matchesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int currentStreak;

  /// Rang final (1-based), null tant que le tournoi n'est pas finalisé.
  final int? rank;
  final int? rewardCauris;
  final String? rewardBadge;

  /// Série en cours active (« on fire ») — utilisée pour l'icône flamme.
  bool get onFire => currentStreak >= 2;

  @override
  List<Object?> get props => [
        uid,
        displayName,
        avatarId,
        points,
        matchesPlayed,
        wins,
        draws,
        losses,
        currentStreak,
        rank,
        rewardCauris,
        rewardBadge,
      ];
}
