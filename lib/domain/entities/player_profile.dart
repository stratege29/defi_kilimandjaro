import 'package:equatable/equatable.dart';

/// Profil ELO d'un joueur — persisté dans Firestore `profiles/{uid}`.
///
/// L'ELO est exprimé en **mètres d'altitude** pour coller à la métaphore
/// Kilimandjaro. 1000 m = départ, 5895 m = "Maître du Kilimandjaro".
///
/// Règle : ce modèle n'est JAMAIS écrit depuis le client.
/// Seul le Cloud Function `endMatch` peut modifier `elo` via Admin SDK.
class PlayerProfile extends Equatable {
  const PlayerProfile({
    required this.uid,
    required this.elo,
    required this.peakElo,
    required this.totalDuels,
    required this.wins,
    required this.losses,
  });

  factory PlayerProfile.initial(String uid) => PlayerProfile(
        uid: uid,
        elo: eloInitial,
        peakElo: eloInitial,
        totalDuels: 0,
        wins: 0,
        losses: 0,
      );

  factory PlayerProfile.fromJson(String uid, Map<String, dynamic> json) =>
      PlayerProfile(
        uid: uid,
        elo: (json['elo'] as num?)?.toInt() ?? eloInitial,
        peakElo: (json['peakElo'] as num?)?.toInt() ?? eloInitial,
        totalDuels: (json['totalDuels'] as num?)?.toInt() ?? 0,
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        losses: (json['losses'] as num?)?.toInt() ?? 0,
      );

  /// ELO initial : 1000 m (altitude de départ symbolique).
  static const int eloInitial = 1000;

  /// ELO "Maître du Kilimandjaro" — sommet du boss final.
  static const int eloMaster = 5895;

  final String uid;

  /// ELO actuel en mètres d'altitude.
  final int elo;

  /// Record personnel (meilleure altitude atteinte).
  final int peakElo;

  final int totalDuels;
  final int wins;
  final int losses;

  /// Taux de victoire [0.0 – 1.0]. Null si pas de duel joué.
  double? get winRate => totalDuels == 0 ? null : wins / totalDuels;

  /// True si le joueur a atteint le sommet symbolique du Kilimandjaro.
  bool get isMaster => elo >= eloMaster;

  /// Titre altitude — label affiché dans l'UI.
  String get altitudeLabel => '$elo m';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'elo': elo,
        'peakElo': peakElo,
        'totalDuels': totalDuels,
        'wins': wins,
        'losses': losses,
      };

  PlayerProfile copyWith({
    String? uid,
    int? elo,
    int? peakElo,
    int? totalDuels,
    int? wins,
    int? losses,
  }) {
    return PlayerProfile(
      uid: uid ?? this.uid,
      elo: elo ?? this.elo,
      peakElo: peakElo ?? this.peakElo,
      totalDuels: totalDuels ?? this.totalDuels,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
    );
  }

  @override
  List<Object?> get props => [uid, elo, peakElo, totalDuels, wins, losses];
}
