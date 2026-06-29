import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Statut du cycle de vie d'un tournoi « arène ».
enum TournamentStatus {
  /// Programmé, pas encore démarré (compte à rebours en cours).
  scheduled,

  /// En cours — la fenêtre de jeu est ouverte.
  live,

  /// Terminé — classement figé, récompenses distribuées.
  finished,

  /// Annulé avant le démarrage.
  cancelled;

  static TournamentStatus fromString(String? raw) {
    switch (raw) {
      case 'live':
        return TournamentStatus.live;
      case 'finished':
        return TournamentStatus.finished;
      case 'cancelled':
        return TournamentStatus.cancelled;
      case 'scheduled':
      default:
        return TournamentStatus.scheduled;
    }
  }
}

/// Palier de récompense d'un tournoi (cauris + badge cosmétique) pour une
/// fourchette de rangs.
class RewardTier extends Equatable {
  const RewardTier({
    required this.rankMin,
    required this.rankMax,
    this.cauris = 0,
    this.badgeId,
  });

  factory RewardTier.fromMap(Map<String, dynamic> m) => RewardTier(
        rankMin: (m['rank_min'] as num?)?.toInt() ?? 1,
        rankMax: (m['rank_max'] as num?)?.toInt() ?? 1,
        cauris: (m['cauris'] as num?)?.toInt() ?? 0,
        badgeId: m['badge_id'] as String?,
      );

  final int rankMin;
  final int rankMax;
  final int cauris;
  final String? badgeId;

  @override
  List<Object?> get props => [rankMin, rankMax, cauris, badgeId];
}

/// Un tournoi « arène » : fenêtre temporisée pendant laquelle les inscrits
/// enchaînent des duels qui rapportent des points d'arène (classement live).
///
/// Mappe `tournaments/{id}` (cf `functions/src/tournament/`). Toutes les
/// écritures sont serveur-only ; le client lit uniquement.
class Tournament extends Equatable {
  const Tournament({
    required this.id,
    required this.name,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.durationMin,
    required this.participantCount,
    required this.pointsWin,
    required this.pointsDraw,
    required this.streakMin,
    required this.streakMult,
    required this.minParticipants,
    required this.maxParticipants,
    required this.rewards,
    this.packId,
  });

  factory Tournament.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return Tournament(
      id: id,
      name: (data['name'] as String?) ?? 'Tournoi',
      status: TournamentStatus.fromString(data['status'] as String?),
      startAt: _toDate(data['start_at']),
      endAt: _toDate(data['end_at']),
      durationMin: (data['duration_min'] as num?)?.toInt() ?? 0,
      participantCount: (data['participant_count'] as num?)?.toInt() ?? 0,
      pointsWin: (data['points_win'] as num?)?.toInt() ?? 3,
      pointsDraw: (data['points_draw'] as num?)?.toInt() ?? 1,
      streakMin: (data['streak_min'] as num?)?.toInt() ?? 2,
      streakMult: (data['streak_mult'] as num?)?.toInt() ?? 2,
      minParticipants: (data['min_participants'] as num?)?.toInt() ?? 2,
      maxParticipants: (data['max_participants'] as num?)?.toInt() ?? 200,
      packId: data['pack_id'] as String?,
      rewards: ((data['rewards'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RewardTier.fromMap)
          .toList(),
    );
  }

  final String id;
  final String name;
  final TournamentStatus status;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMin;
  final int participantCount;
  final int pointsWin;
  final int pointsDraw;
  final int streakMin;
  final int streakMult;
  final int minParticipants;
  final int maxParticipants;
  final String? packId;
  final List<RewardTier> rewards;

  /// Plus de place : le plafond d'inscrits est atteint.
  bool get isFull => participantCount >= maxParticipants;

  bool get isScheduled => status == TournamentStatus.scheduled;
  bool get isLive => status == TournamentStatus.live;
  bool get isFinished => status == TournamentStatus.finished;
  bool get isCancelled => status == TournamentStatus.cancelled;

  /// Temps restant avant le démarrage (>= zéro). `Duration.zero` si déjà passé.
  Duration startsIn(DateTime now) {
    final d = startAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// Temps restant avant la fin (>= zéro). `Duration.zero` si déjà passé.
  Duration endsIn(DateTime now) {
    final d = endAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// La fenêtre de jeu est-elle effectivement ouverte maintenant ?
  bool isOpenAt(DateTime now) =>
      isLive && now.isAfter(startAt) && now.isBefore(endAt);

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  List<Object?> get props => [
        id,
        name,
        status,
        startAt,
        endAt,
        participantCount,
        rewards,
      ];
}
