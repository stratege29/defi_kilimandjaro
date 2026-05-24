import 'package:equatable/equatable.dart';

/// Entrée du classement — vue aplatie d'un profil joueur pour l'affichage.
///
/// [rank] est calculé côté repository (index dans le top-100 ou estimation
/// via count-query pour les joueurs hors top-100).
class LeaderboardEntry extends Equatable {
  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.elo,
    required this.rank,
    this.avatarId,
  });

  final String uid;
  final String displayName;

  /// Score ELO = altitude en mètres dans l'univers Kilimandjaro.
  final int elo;

  /// Position dans le classement (1-based).
  final int rank;

  /// Id de l'avatar choisi (cf. `AvatarCatalog`). Null = fallback initiale.
  final String? avatarId;

  /// Libellé de l'altitude affiché dans l'UI : "1247 m".
  String get altitudeLabel => '$elo m';

  @override
  List<Object?> get props => [uid, displayName, elo, rank, avatarId];
}
