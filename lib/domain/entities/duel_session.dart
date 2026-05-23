import 'package:equatable/equatable.dart';

/// Phase d'un duel temps reel.
enum DuelPhase {
  waiting,
  intro,
  countdown,
  active,
  roundEnd,
  finished,
}

/// Contenu d'un round (cote client, recu depuis RTDB /matches/{id}/rounds/{n}).
///
/// Le serveur ecrit ces champs dans RTDB; le client ne les genere jamais.
class RoundData extends Equatable {
  const RoundData({
    required this.index,
    required this.answer,
    required this.lettersPool,
    required this.riddle,
    required this.explanation,
    required this.proverb,
    required this.difficulty,
    required this.devinetteId,
  });

  factory RoundData.fromJson(int index, Map<String, dynamic> json) {
    return RoundData(
      index: index,
      answer: (json['answer'] as String? ?? '').toUpperCase(),
      lettersPool:
          ((json['letters_pool'] as List<dynamic>?) ?? <dynamic>[])
              .cast<String>(),
      riddle: json['riddle'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      proverb: json['proverb'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'easy',
      devinetteId: json['devinette_id'] as String? ?? '',
    );
  }

  /// Index du round dans la session (0, 1, 2).
  final int index;

  /// Mot reponse en majuscules (ex: "BAOBAB").
  final String answer;

  /// Lettres melangees affichees dans la grille.
  final List<String> lettersPool;

  final String riddle;
  final String explanation;

  /// Optionnel — peut etre vide si la devinette n'en a pas.
  final String proverb;

  /// "easy" | "medium" | "hard"
  final String difficulty;

  /// Ref Firestore (pour stats cote serveur uniquement).
  final String devinetteId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'answer': answer,
        'letters_pool': lettersPool,
        'riddle': riddle,
        'explanation': explanation,
        'proverb': proverb,
        'difficulty': difficulty,
        'devinette_id': devinetteId,
      };

  @override
  List<Object?> get props => [
        index,
        answer,
        lettersPool,
        riddle,
        explanation,
        proverb,
        difficulty,
        devinetteId,
      ];
}

/// Resultat d'un joueur sur un round specifique.
class RoundResult extends Equatable {
  const RoundResult({
    required this.progress,
    required this.found,
    this.finishedAtMs,
    this.timeTakenMs,
  });

  factory RoundResult.fromJson(Map<String, dynamic> json) {
    return RoundResult(
      progress: ((json['progress'] as num?) ?? 0).toDouble(),
      found: (json['found'] as bool?) ?? false,
      finishedAtMs: (json['finished_at'] as num?)?.toInt(),
      timeTakenMs: (json['time_taken_ms'] as num?)?.toInt(),
    );
  }

  /// 0.0 a 1.0 : lettres correctement positionnees.
  final double progress;

  /// True si le joueur a trouve le mot dans les temps.
  final bool found;

  /// Timestamp ms epoch quand le mot a ete valide (null si non trouve).
  final int? finishedAtMs;

  /// Duree en ms pour trouver (null si timeout ou non trouve).
  final int? timeTakenMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'progress': progress,
        'found': found,
        if (finishedAtMs != null) 'finished_at': finishedAtMs,
        if (timeTakenMs != null) 'time_taken_ms': timeTakenMs,
      };

  @override
  List<Object?> get props => [progress, found, finishedAtMs, timeTakenMs];
}

/// Etat d'un participant a un duel multi-rounds.
class DuelPlayer extends Equatable {
  const DuelPlayer({
    required this.uid,
    required this.roundsWon,
    required this.totalTimeMs,
    required this.rounds,
    this.progress = 0,
    this.found = false,
    this.finishedAt,
  });

  factory DuelPlayer.fromJson(String uid, Map<String, dynamic> json) {
    final roundsRaw =
        (json['rounds'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final rounds = <int, RoundResult>{
      for (final e in roundsRaw.entries)
        int.parse(e.key.toString()): RoundResult.fromJson(
          (e.value as Map).cast<String, dynamic>(),
        ),
    };
    return DuelPlayer(
      uid: uid,
      roundsWon: (json['rounds_won'] as num?)?.toInt() ?? 0,
      totalTimeMs: (json['total_time_ms'] as num?)?.toInt() ?? 0,
      rounds: rounds,
      progress: ((json['progress'] as num?) ?? 0).toDouble(),
      found: (json['found'] as bool?) ?? false,
      finishedAt: (json['finished_at'] as num?)?.toInt(),
    );
  }

  /// Nombre de rounds remportes (0-3).
  final int roundsWon;

  /// Cumul des timeTakenMs sur les rounds trouves (tiebreaker).
  final int totalTimeMs;

  /// Resultats detailles par index de round.
  final Map<int, RoundResult> rounds;

  final String uid;

  /// Progression courante dans le round actif (0.0 a 1.0).
  final double progress;

  /// True si le joueur a valide le mot du round en cours.
  final bool found;

  /// Timestamp ms quand le mot du round actif a ete valide.
  final int? finishedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rounds_won': roundsWon,
        'total_time_ms': totalTimeMs,
        'progress': progress,
        'found': found,
        if (finishedAt != null) 'finished_at': finishedAt,
        'rounds': <String, dynamic>{
          for (final e in rounds.entries) '${e.key}': e.value.toJson(),
        },
      };

  @override
  List<Object?> get props =>
      [uid, roundsWon, totalTimeMs, rounds, progress, found, finishedAt];
}

/// Session de duel synchronisee via Firebase Realtime Database.
///
/// Stockage `/matches/{matchId}` :
/// - `secret`            : token requis pour rejoindre (transmis via QR)
/// - `created_by`        : UID du createur
/// - `created_at`        : ts ms
/// - `phase`             : voir [DuelPhase]
/// - `current_round`     : index du round en cours (0-2)
/// - `total_rounds`      : toujours 3
/// - `rounds/{0,1,2}`    : [RoundData] cote client (answer, letters_pool, riddle...)
/// - `players/{uid}`     : [DuelPlayer] state
/// - `winner`            : UID du vainqueur (set quand phase = finished)
/// - `is_ranked`         : true pour matchmaking ELO, false pour duel ami QR
/// - `phase_started_at`  : ts ms debut de la phase courante (countdown/roundEnd UI)
class DuelSession extends Equatable {
  // ignore: prefer_const_constructors_in_immutables
  DuelSession({
    required this.matchId,
    required this.secret,
    required this.createdBy,
    required this.createdAt,
    required this.phase,
    this.currentRound = 0,
    this.totalRounds = 3,
    this.rounds = const [],
    this.players = const {},
    this.winner,
    this.isRanked = false,
    this.phaseStartedAtMs,
    // Parametres de compatibilite Phase 2->3 : ignores silencieusement.
    // Les vues existantes passent ces valeurs dans le constructeur pour
    // construire un QR payload ; les donnees reelles viennent de
    // /matches/{matchId}/rounds dans RTDB.
    // ignore: avoid_unused_constructor_parameters
    String? answer,
    // ignore: avoid_unused_constructor_parameters
    List<String>? lettersPool,
    // ignore: avoid_unused_constructor_parameters
    String? riddle,
    // ignore: avoid_unused_constructor_parameters
    String? explanation,
    // ignore: avoid_unused_constructor_parameters
    String? proverb,
  });

  factory DuelSession.fromJson(String matchId, Map<String, dynamic> json) {
    final playersRaw =
        (json['players'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final players = <String, DuelPlayer>{
      for (final e in playersRaw.entries)
        e.key as String: DuelPlayer.fromJson(
          e.key as String,
          (e.value as Map).cast<String, dynamic>(),
        ),
    };

    // Rounds stockes sous /rounds/{0,1,2} dans RTDB (Map ou List).
    final roundsRaw = json['rounds'];
    final rounds = <RoundData>[];
    if (roundsRaw is Map) {
      final sorted = roundsRaw.entries.toList()
        ..sort(
          (a, b) =>
              int.parse(a.key.toString())
                  .compareTo(int.parse(b.key.toString())),
        );
      for (final e in sorted) {
        final idx = int.parse(e.key.toString());
        rounds.add(
          RoundData.fromJson(idx, (e.value as Map).cast<String, dynamic>()),
        );
      }
    } else if (roundsRaw is List) {
      for (var i = 0; i < roundsRaw.length; i++) {
        if (roundsRaw[i] != null) {
          rounds.add(
            RoundData.fromJson(
              i,
              (roundsRaw[i] as Map).cast<String, dynamic>(),
            ),
          );
        }
      }
    }

    return DuelSession(
      matchId: matchId,
      secret: json['secret'] as String? ?? '',
      createdBy: json['created_by'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      phase: DuelPhase.values.firstWhere(
        (p) => p.name == (json['phase'] as String? ?? 'waiting'),
        orElse: () => DuelPhase.waiting,
      ),
      currentRound: (json['current_round'] as num?)?.toInt() ?? 0,
      totalRounds: (json['total_rounds'] as num?)?.toInt() ?? 3,
      rounds: rounds,
      players: players,
      winner: json['winner'] as String?,
      isRanked: (json['is_ranked'] as bool?) ?? false,
      phaseStartedAtMs: (json['phase_started_at'] as num?)?.toInt(),
    );
  }

  final String matchId;
  final String secret;
  final String createdBy;
  final int createdAt;
  final DuelPhase phase;

  /// Index du round en cours (0, 1, 2).
  final int currentRound;

  /// Toujours 3 pour cette version.
  final int totalRounds;

  /// Les 3 rounds pre-tires au debut du match.
  final List<RoundData> rounds;

  final Map<String, DuelPlayer> players;
  final String? winner;

  /// True si le match a ete cree par le matchmaking ELO.
  /// False pour les duels ami via QR code.
  final bool isRanked;

  /// Timestamp ms du debut de la phase courante (utile pour countdown/roundEnd).
  final int? phaseStartedAtMs;

  /// Donne les donnees du round actif (null si index hors limites).
  RoundData? get currentRoundData =>
      (currentRound >= 0 && currentRound < rounds.length)
          ? rounds[currentRound]
          : null;

  // ---------------------------------------------------------------------------
  // Accesseurs de compatibilite — deleguent au round actif.
  // Utilises par les vues existantes en attendant la refonte UI Phase 3.
  // ---------------------------------------------------------------------------

  /// Mot reponse du round courant.
  String get answer => currentRoundData?.answer ?? '';

  /// Lettres de la grille du round courant.
  List<String> get lettersPool => currentRoundData?.lettersPool ?? const [];

  /// Devinette du round courant.
  String get riddle => currentRoundData?.riddle ?? '';

  /// Explication du round courant.
  String get explanation => currentRoundData?.explanation ?? '';

  /// Proverbe du round courant.
  String get proverb => currentRoundData?.proverb ?? '';

  /// Representation compressee pour QR : `kilimandjaro://join?m=<id>&s=<secret>`.
  String toQrPayload() => 'kilimandjaro://join?m=$matchId&s=$secret';

  /// Parsing inverse — null si payload invalide.
  static ({String matchId, String secret})? parseQrPayload(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme != 'kilimandjaro' || uri.host != 'join') return null;
    final m = uri.queryParameters['m'];
    final s = uri.queryParameters['s'];
    if (m == null || m.isEmpty || s == null || s.isEmpty) return null;
    return (matchId: m, secret: s);
  }

  /// Adversaire du joueur courant. Null tant que pas de second joueur.
  DuelPlayer? opponentOf(String selfUid) {
    for (final p in players.values) {
      if (p.uid != selfUid) return p;
    }
    return null;
  }

  @override
  List<Object?> get props => [
        matchId,
        secret,
        createdBy,
        createdAt,
        phase,
        currentRound,
        totalRounds,
        rounds,
        players,
        winner,
        isRanked,
        phaseStartedAtMs,
      ];
}
