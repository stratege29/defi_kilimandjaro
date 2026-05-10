// Tests unitaires du parsing des résultats Cloud Functions et de l'entité
// DuelSession. Les tests du MatchmakingRepository proprement dit nécessitent
// un émulateur Firebase (voir firebase emulators:start) ; on teste ici la
// logique pure sans Firebase.

import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // DuelSession.isRanked — parsing sans Firebase
  // ---------------------------------------------------------------------------
  group('DuelSession.isRanked', () {
    test('is_ranked=true parsé correctement depuis JSON Realtime DB', () {
      final session = DuelSession.fromJson('M1', {
        'secret': 's',
        'created_by': 'u',
        'created_at': 0,
        'phase': 'active',
        'answer': 'KORA',
        'letters_pool': ['K', 'O', 'R', 'A'],
        'riddle': 'r',
        'explanation': 'e',
        'proverb': 'p',
        'players': <dynamic, dynamic>{},
        'is_ranked': true,
      });
      expect(session.isRanked, isTrue);
    });

    test('is_ranked absent → false par défaut (duel ami QR)', () {
      final session = DuelSession.fromJson('M2', {
        'secret': 's',
        'created_by': 'u',
        'created_at': 0,
        'phase': 'active',
        'answer': 'KORA',
        'letters_pool': ['K', 'O', 'R', 'A'],
        'riddle': 'r',
        'explanation': 'e',
        'proverb': 'p',
        'players': <dynamic, dynamic>{},
      });
      expect(session.isRanked, isFalse);
    });

    test('is_ranked=false parsé correctement', () {
      final session = DuelSession.fromJson('M3', {
        'secret': 's',
        'created_by': 'u',
        'created_at': 0,
        'phase': 'waiting',
        'answer': 'GRIOT',
        'letters_pool': ['G', 'R', 'I', 'O', 'T'],
        'riddle': 'r',
        'explanation': 'e',
        'proverb': 'p',
        'players': <dynamic, dynamic>{},
        'is_ranked': false,
      });
      expect(session.isRanked, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // EloDelta — modèle de retour
  // ---------------------------------------------------------------------------
  group('EloDelta', () {
    test('nouveau ELO positif pour le gagnant', () {
      const delta = EloDelta(newElo: 1032, delta: 32);
      expect(delta.newElo, 1032);
      expect(delta.delta, isPositive);
    });

    test('delta négatif pour le perdant', () {
      const delta = EloDelta(newElo: 984, delta: -16);
      expect(delta.delta, isNegative);
    });

    test('delta zéro pour un match non-ranked', () {
      const delta = EloDelta(newElo: 1000, delta: 0);
      expect(delta.delta, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // MatchmakingResult — sealed classes
  // ---------------------------------------------------------------------------
  group('MatchmakingResult types', () {
    test('MatchmakingWaiting est une MatchmakingResult', () {
      const result = MatchmakingWaiting();
      expect(result, isA<MatchmakingResult>());
    });

    test('MatchmakingMatched contient la session', () {
      final session = DuelSession.fromJson('X1', {
        'secret': 's',
        'created_by': 'u',
        'created_at': 0,
        'phase': 'waiting',
        'answer': 'BAOBAB',
        'letters_pool': ['B', 'A', 'O', 'B', 'A', 'B'],
        'riddle': 'r',
        'explanation': 'e',
        'proverb': 'p',
        'players': <dynamic, dynamic>{},
        'is_ranked': true,
      });
      final result = MatchmakingMatched(session: session);
      expect(result, isA<MatchmakingResult>());
      expect(result.session.answer, 'BAOBAB');
      expect(result.session.isRanked, isTrue);
    });

    test('switch exhaustif sur MatchmakingResult', () {
      const MatchmakingResult result = MatchmakingWaiting();
      final label = switch (result) {
        MatchmakingWaiting() => 'waiting',
        MatchmakingMatched() => 'matched',
      };
      expect(label, 'waiting');
    });
  });
}
