import 'package:equatable/equatable.dart';

/// Profil ELO d'un joueur — persisté dans Firestore `profiles/{uid}`.
///
/// L'ELO est exprimé en **mètres d'altitude** pour coller à la métaphore
/// Kilimandjaro. 1000 m = départ, 5895 m = "Maître du Kilimandjaro".
///
/// Règle : `elo`, `peakElo`, `totalDuels`, `wins`, `losses` ne sont JAMAIS
/// écrits depuis le client — uniquement via le Cloud Function `endMatch`.
/// `display_name` est l'exception : écrit côté client (rules Firestore
/// autorisent uniquement ce champ via `merge: true`).
class PlayerProfile extends Equatable {
  const PlayerProfile({
    required this.uid,
    required this.elo,
    required this.peakElo,
    required this.totalDuels,
    required this.wins,
    required this.losses,
    this.displayName,
    this.displayNameUpdatedAt,
    this.avatarId,
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
        displayName: json['display_name'] as String?,
        displayNameUpdatedAt: _parseTimestamp(json['display_name_updated_at']),
        avatarId: json['avatar_id'] as String?,
      );

  /// Parse robuste pour les timestamps lus depuis Firestore.
  ///
  /// Le champ peut etre :
  /// - `null` (jamais defini)
  /// - un `int`/`num` (milliseconds since epoch, ecrit cote client)
  /// - un `Timestamp` Firestore (ecrit via FieldValue.serverTimestamp()
  ///   ou par le serveur Admin SDK)
  ///
  /// Le `Timestamp` Firestore n'est PAS un num — le cast `as num` throw
  /// `_TypeError`. On lit defensivement via dynamic.millisecondsSinceEpoch
  /// pour eviter d'importer cloud_firestore dans la couche domain.
  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    try {
      // Firestore Timestamp expose .millisecondsSinceEpoch via dynamic.
      // ignore: avoid_dynamic_calls
      final ms = (raw as dynamic).millisecondsSinceEpoch as int;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } on Object {
      return null;
    }
  }

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

  /// Nom de grimpeur choisi par le joueur (leaderboard). Null = non défini.
  final String? displayName;

  /// Date de la dernière modification du displayName (anti-spam).
  final DateTime? displayNameUpdatedAt;

  /// Id de l'avatar choisi (cf. `AvatarCatalog`). Null = pas encore choisi
  /// → fallback initiale du pseudo dans l'UI.
  final String? avatarId;

  /// Taux de victoire [0.0 – 1.0]. Null si pas de duel joué.
  double? get winRate => totalDuels == 0 ? null : wins / totalDuels;

  /// True si le joueur a atteint le sommet symbolique du Kilimandjaro.
  bool get isMaster => elo >= eloMaster;

  /// Titre altitude — label affiché dans l'UI.
  String get altitudeLabel => '$elo m';

  /// Nom affiché dans le classement : displayName si défini, sinon anonyme.
  String get displayLabel =>
      (displayName?.isNotEmpty ?? false) ? displayName! : 'Grimpeur anonyme';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'elo': elo,
        'peakElo': peakElo,
        'totalDuels': totalDuels,
        'wins': wins,
        'losses': losses,
        if (displayName != null) 'display_name': displayName,
        if (avatarId != null) 'avatar_id': avatarId,
      };

  PlayerProfile copyWith({
    String? uid,
    int? elo,
    int? peakElo,
    int? totalDuels,
    int? wins,
    int? losses,
    String? displayName,
    DateTime? displayNameUpdatedAt,
    String? avatarId,
  }) {
    return PlayerProfile(
      uid: uid ?? this.uid,
      elo: elo ?? this.elo,
      peakElo: peakElo ?? this.peakElo,
      totalDuels: totalDuels ?? this.totalDuels,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      displayName: displayName ?? this.displayName,
      displayNameUpdatedAt: displayNameUpdatedAt ?? this.displayNameUpdatedAt,
      avatarId: avatarId ?? this.avatarId,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        elo,
        peakElo,
        totalDuels,
        wins,
        losses,
        displayName,
        displayNameUpdatedAt,
        avatarId,
      ];
}
