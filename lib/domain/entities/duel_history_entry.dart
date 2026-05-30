import 'package:equatable/equatable.dart';

/// Entry in a player's duel history — one completed match record.
///
/// Persisted in Firestore at `profiles/{uid}/duel_history/{matchId}`.
/// Created by Cloud Function `endMatch` for both winner and loser.
class DuelHistoryEntry extends Equatable {
  const DuelHistoryEntry({
    required this.matchId,
    required this.opponentUid,
    required this.opponentName,
    required this.didWin,
    required this.eloDelta,
    required this.finishedAt,
  });

  factory DuelHistoryEntry.fromJson(String matchId, Map<String, dynamic> json) =>
      DuelHistoryEntry(
        matchId: matchId,
        opponentUid: json['opponent_uid'] as String? ?? '',
        opponentName: json['opponent_name'] as String? ?? 'Grimpeur anonyme',
        didWin: json['did_win'] as bool? ?? false,
        eloDelta: (json['elo_delta'] as num?)?.toInt() ?? 0,
        finishedAt: _parseTimestamp(json['finished_at']),
      );

  /// Parse robuste pour les timestamps lus depuis Firestore.
  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    try {
      // ignore: avoid_dynamic_calls
      final ms = (raw as dynamic).millisecondsSinceEpoch as int;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } on Object {
      return null;
    }
  }

  final String matchId;
  final String opponentUid;
  final String opponentName;
  final bool didWin;
  final int eloDelta;
  final DateTime? finishedAt;

  /// Timestamp in milliseconds for sorting.
  int get finishedAtMs =>
      finishedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;

  /// Display-friendly opponent name.
  String get displayOpponentName =>
      opponentName.isNotEmpty ? opponentName : 'Grimpeur anonyme';

  /// Badge label for result: "V" or "D".
  String get resultBadge => didWin ? 'V' : 'D';

  /// ELO delta as signed string (e.g., "+32 m", "-28 m").
  String get eloDeltaLabel {
    if (eloDelta == 0) return '±0 m';
    final sign = eloDelta > 0 ? '+' : '';
    return '$sign$eloDelta m';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'opponent_uid': opponentUid,
        'opponent_name': opponentName,
        'did_win': didWin,
        'elo_delta': eloDelta,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
      };

  @override
  List<Object?> get props => [
        matchId,
        opponentUid,
        opponentName,
        didWin,
        eloDelta,
        finishedAt,
      ];
}
