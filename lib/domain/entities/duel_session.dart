import 'package:equatable/equatable.dart';

/// Phase d'un duel temps réel.
enum DuelPhase { waiting, active, finished }

/// État d'un participant à un duel.
class DuelPlayer extends Equatable {
  const DuelPlayer({
    required this.uid,
    required this.progress,
    this.finishedAt,
    this.found = false,
  });

  factory DuelPlayer.fromJson(String uid, Map<String, dynamic> json) =>
      DuelPlayer(
        uid: uid,
        progress: ((json['progress'] as num?) ?? 0).toDouble(),
        finishedAt: json['finished_at'] as int?,
        found: (json['found'] as bool?) ?? false,
      );

  final String uid;

  /// 0.0 → 1.0 (lettres correctement positionnées sur l'answer).
  final double progress;

  /// Timestamp ms epoch quand le joueur a validé (ou null si en cours).
  final int? finishedAt;

  /// Vrai si le joueur a validé le mot correct.
  final bool found;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'progress': progress,
        if (finishedAt != null) 'finished_at': finishedAt,
        'found': found,
      };

  @override
  List<Object?> get props => [uid, progress, finishedAt, found];
}

/// Session de duel synchronisée via Firebase Realtime Database.
///
/// Stockage `/matches/{matchId}` :
/// - `secret` : token requis pour rejoindre (transmis via QR)
/// - `created_by` : UID du créateur
/// - `created_at` : ts ms
/// - `phase` : waiting / active / finished
/// - `answer` : mot solution (UPPERCASE)
/// - `letters_pool` : list lettres mélangées
/// - `riddle` / `explanation` / `proverb` : contenu de la devinette
/// - `players/{uid}` : DuelPlayer state
/// - `winner` : UID du gagnant (set quand phase = finished)
/// - `is_ranked` : true pour matchmaking ELO, false pour duel ami QR (Phase 6)
class DuelSession extends Equatable {
  const DuelSession({
    required this.matchId,
    required this.secret,
    required this.createdBy,
    required this.createdAt,
    required this.phase,
    required this.answer,
    required this.lettersPool,
    required this.riddle,
    required this.explanation,
    required this.proverb,
    required this.players,
    this.winner,
    this.isRanked = false,
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
    return DuelSession(
      matchId: matchId,
      secret: json['secret'] as String? ?? '',
      createdBy: json['created_by'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      phase: DuelPhase.values.firstWhere(
        (p) => p.name == (json['phase'] as String? ?? 'waiting'),
        orElse: () => DuelPhase.waiting,
      ),
      answer: (json['answer'] as String? ?? '').toUpperCase(),
      lettersPool:
          ((json['letters_pool'] as List<dynamic>?) ?? <dynamic>[])
              .cast<String>(),
      riddle: json['riddle'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      proverb: json['proverb'] as String? ?? '',
      players: players,
      winner: json['winner'] as String?,
      isRanked: (json['is_ranked'] as bool?) ?? false,
    );
  }

  final String matchId;
  final String secret;
  final String createdBy;
  final int createdAt;
  final DuelPhase phase;
  final String answer;
  final List<String> lettersPool;
  final String riddle;
  final String explanation;
  final String proverb;
  final Map<String, DuelPlayer> players;
  final String? winner;

  /// True si le match a été créé par le matchmaking ELO (Phase 6).
  /// False pour les duels ami via QR code.
  final bool isRanked;

  /// Représentation compressée pour QR : `kilimandjaro://join?m=<id>&s=<secret>`.
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
        answer,
        lettersPool,
        riddle,
        explanation,
        proverb,
        players,
        winner,
        isRanked,
      ];
}
