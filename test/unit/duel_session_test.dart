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
        answer: '',
        lettersPool: const [],
        riddle: '',
        explanation: '',
        proverb: '',
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
    test('fromJson reconstructs players map', () {
      final s = DuelSession.fromJson('match-1', <String, dynamic>{
        'secret': 'sec',
        'created_by': 'a',
        'created_at': 1700000000,
        'phase': 'active',
        'answer': 'foutou',
        'letters_pool': const ['F', 'O', 'U', 'T', 'O', 'U'],
        'riddle': 'r',
        'explanation': 'e',
        'proverb': 'p',
        'players': <String, dynamic>{
          'a': <String, dynamic>{'progress': 0.5, 'found': false},
          'b': <String, dynamic>{'progress': 1.0, 'found': true},
        },
      });
      expect(s.matchId, 'match-1');
      expect(s.phase, DuelPhase.active);
      expect(s.answer, 'FOUTOU');
      expect(s.players.length, 2);
      expect(s.opponentOf('a')?.uid, 'b');
      expect(s.opponentOf('b')?.uid, 'a');
      expect(s.opponentOf('unknown'), isNotNull);
    });
  });
}
