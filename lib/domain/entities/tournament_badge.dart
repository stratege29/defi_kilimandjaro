import 'package:equatable/equatable.dart';

/// Badge cosmétique gagné dans un tournoi, affiché sur le profil.
///
/// Mappe `profiles/{uid}/badges/{tournamentId}` (écrit par le `tournamentTicker`
/// à la finalisation). Un badge par tournoi.
class TournamentBadge extends Equatable {
  const TournamentBadge({
    required this.tournamentId,
    required this.badgeId,
    required this.label,
    required this.rank,
  });

  factory TournamentBadge.fromFirestore(String id, Map<String, dynamic> data) {
    return TournamentBadge(
      tournamentId: id,
      badgeId: (data['badge_id'] as String?) ?? 'tournament',
      label: (data['label'] as String?) ?? 'Tournoi',
      rank: (data['rank'] as num?)?.toInt() ?? 0,
    );
  }

  final String tournamentId;
  final String badgeId;

  /// Nom du tournoi.
  final String label;

  /// Rang final obtenu (1 = vainqueur).
  final int rank;

  @override
  List<Object?> get props => [tournamentId, badgeId, label, rank];
}
