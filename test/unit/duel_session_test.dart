import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DuelSession.toQrPayload / parseQrPayload', () {
    test('round-trip with valid match id and secret', () {
      final session = DuelSession(
        matchId: 'K3M9P2',
        secret: '0123456789abcdef01234567',
        createdBy: 'uid-creator',
        createdAt: 0,
        phase: DuelPhase.waiting,
        rounds: const [],
        players: const {},
      );
      final payload = session.toQrPayload();
      expect(payload, contains('m=K3M9P2'));
      expect(payload, contains('s=0123456789abcdef01234567'));

      final parsed = DuelSession.parseQrPayload(payload);
      expect(parsed, isNotNull);
      expect(parsed!.matchId, 'K3M9P2');
      expect(parsed.secret, '0123456789abcdef01234567');
    });

    test('rejects invalid scheme', () {
      final parsed = DuelSession.parseQrPayload('https://kilimandjaro.app/x');
      expect(parsed, isNull);
    });

    test('rejects missing query params', () {
      final parsed = DuelSession.parseQrPayload('kilimandjaro://join?m=ABC');
      expect(parsed, isNull);
    });

    test('rejects garbage', () {
      expect(DuelSession.parseQrPayload(''), isNull);
      expect(DuelSession.parseQrPayload('not a uri at all'), isNull);
    });
  });

  group('DuelSession.fromJson / opponentOf', () {
    test('fromJson reconstructs players map and rounds', () {
      final s = DuelSession.fromJson('match-1', <String, dynamic>{
        'secret': 'sec',
        'created_by': 'a',
        'created_at': 1700000000,
        'phase': 'active',
        'current_round': 0,
        'total_rounds': 3,
        'rounds': <String, dynamic>{
          '0': <String, dynamic>{
            'answer': 'FOUTOU',
            'letters_pool': ['F', 'O', 'U', 'T', 'O', 'U'],
            'riddle': 'r',
            'explanation': 'e',
            'proverb': 'p',
            'difficulty': 'easy',
            'devinette_id': 'dev-1',
          },
        },
        'players': <String, dynamic>{
          'a': <String, dynamic>{
            'progress': 0.5,
            'found': false,
            'rounds_won': 0,
            'total_time_ms': 0,
            'rounds': <String, dynamic>{},
          },
          'b': <String, dynamic>{
            'progress': 1.0,
            'found': true,
            'rounds_won': 1,
            'total_time_ms': 12000,
            'rounds': <String, dynamic>{
              '0': <String, dynamic>{
                'progress': 1.0,
                'found': true,
                'finished_at': 1700000012000,
                'time_taken_ms': 12000,
              },
            },
          },
        },
      });
      expect(s.matchId, 'match-1');
      expect(s.phase, DuelPhase.active);
      expect(s.currentRound, 0);
      expect(s.rounds, hasLength(1));
      expect(s.answer, 'FOUTOU');
      expect(s.players.length, 2);
      expect(s.opponentOf('a')?.uid, 'b');
      expect(s.opponentOf('b')?.uid, 'a');
      expect(s.players['b']?.roundsWon, 1);
      expect(s.players['b']?.totalTimeMs, 12000);
    });

    test('opponentOf returns null if only one player', () {
      final s = DuelSession.fromJson('m2', <String, dynamic>{
        'secret': 's',
        'created_by': 'a',
        'created_at': 0,
        'phase': 'waiting',
        'current_round': 0,
        'total_rounds': 3,
        'rounds': <String, dynamic>{},
        'players': <String, dynamic>{
          'a': <String, dynamic>{
            'progress': 0.0,
            'found': false,
            'rounds_won': 0,
            'total_time_ms': 0,
            'rounds': <String, dynamic>{},
          },
        },
      });
      expect(s.opponentOf('a'), isNull);
    });
  });

  group('RoundData.fromJson', () {
    test('parses easy round correctly', () {
      final r = RoundData.fromJson(0, <String, dynamic>{
        'answer': 'KORA',
        'letters_pool': ['K', 'O', 'R', 'A'],
        'riddle': 'riddle',
        'explanation': 'exp',
        'proverb': 'prov',
        'difficulty': 'easy',
        'devinette_id': 'dev-42',
      });
      expect(r.answer, 'KORA');
      expect(r.difficulty, 'easy');
      expect(r.devinetteId, 'dev-42');
      expect(r.lettersPool, hasLength(4));
    });
  });

  group('RoundResult.fromJson', () {
    test('parses found round', () {
      final rr = RoundResult.fromJson(<String, dynamic>{
        'progress': 1.0,
        'found': true,
        'finished_at': 1700000012000,
        'time_taken_ms': 12000,
      });
      expect(rr.found, isTrue);
      expect(rr.timeTakenMs, 12000);
      expect(rr.finishedAtMs, 1700000012000);
    });

    test('parses unfound round (timeout)', () {
      final rr = RoundResult.fromJson(<String, dynamic>{
        'progress': 0.5,
        'found': false,
      });
      expect(rr.found, isFalse);
      expect(rr.timeTakenMs, isNull);
    });
  });

  group('DuelSession multi-round serialization', () {
    test('fromJson handles 3 rounds in correct order', () {
      final s = DuelSession.fromJson('m3', <String, dynamic>{
        'secret': 'sec',
        'created_by': 'u',
        'created_at': 0,
        'phase': 'active',
        'current_round': 1,
        'total_rounds': 3,
        'rounds': <String, dynamic>{
          '2': <String, dynamic>{
            'answer': 'CALEBASSE',
            'letters_pool': ['C', 'A', 'L', 'E', 'B', 'A', 'S', 'S', 'E'],
            'riddle': 'r3',
            'explanation': 'e3',
            'proverb': '',
            'difficulty': 'hard',
            'devinette_id': 'dev-3',
          },
          '0': <String, dynamic>{
            'answer': 'KORA',
            'letters_pool': ['K', 'O', 'R', 'A'],
            'riddle': 'r1',
            'explanation': 'e1',
            'proverb': 'p1',
            'difficulty': 'easy',
            'devinette_id': 'dev-1',
          },
          '1': <String, dynamic>{
            'answer': 'BAOBAB',
            'letters_pool': ['B', 'A', 'O', 'B', 'A', 'B'],
            'riddle': 'r2',
            'explanation': 'e2',
            'proverb': '',
            'difficulty': 'medium',
            'devinette_id': 'dev-2',
          },
        },
        'players': <String, dynamic>{},
      });
      expect(s.rounds, hasLength(3));
      expect(s.rounds[0].difficulty, 'easy');
      expect(s.rounds[1].difficulty, 'medium');
      expect(s.rounds[2].difficulty, 'hard');
      // currentRound=1 => active round is medium
      expect(s.answer, 'BAOBAB');
      expect(s.currentRoundData?.devinetteId, 'dev-2');
    });
  });
}
