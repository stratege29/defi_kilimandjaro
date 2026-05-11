import 'package:defi_kilimandjaro/core/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDeepLinkFriendUid', () {
    // --- Cas valides ---

    test('extrait le uid depuis un lien standard', () {
      final uri = Uri.parse('kilimandjaro://friend/abc123uid456');
      expect(parseDeepLinkFriendUid(uri), 'abc123uid456');
    });

    test('extrait le uid avec slash final', () {
      final uri = Uri.parse('kilimandjaro://friend/uid28charslonguid12345678/');
      expect(parseDeepLinkFriendUid(uri), 'uid28charslonguid12345678');
    });

    // --- Cas invalides (retournent null) ---

    test('retourne null pour scheme https', () {
      final uri = Uri.parse('https://kilimandjaro.app/friend/uid');
      expect(parseDeepLinkFriendUid(uri), isNull);
    });

    test('retourne null pour host duel', () {
      final uri = Uri.parse('kilimandjaro://duel/ABC123');
      expect(parseDeepLinkFriendUid(uri), isNull);
    });

    test('retourne null si uid vide', () {
      final uri = Uri.parse('kilimandjaro://friend/');
      expect(parseDeepLinkFriendUid(uri), isNull);
    });

    test('retourne null pour scheme différent', () {
      final uri = Uri.parse('https://example.com/friend/uid');
      expect(parseDeepLinkFriendUid(uri), isNull);
    });

    test('retourne null pour kilimandjaro://friend sans path', () {
      final uri = Uri.parse('kilimandjaro://friend');
      expect(parseDeepLinkFriendUid(uri), isNull);
    });

    test('retourne null pour le flow QR duel (host=join)', () {
      final uri = Uri.parse('kilimandjaro://join?m=ABC123&s=secret');
      expect(parseDeepLinkFriendUid(uri), isNull);
    });

    // --- UIDs réels Firebase (28 chars alphanumériques) ---

    test('accepte un uid Firebase de 28 chars', () {
      const uid = 'WFqkLmXzABCdef01234567ghij';
      final uri = Uri.parse('kilimandjaro://friend/$uid');
      expect(parseDeepLinkFriendUid(uri), uid);
    });
  });

  group('parseDeepLinkMatchId', () {
    // --- Cas valides ---

    test('extrait le matchId depuis un lien standard', () {
      final uri = Uri.parse('kilimandjaro://duel/ABC123');
      expect(parseDeepLinkMatchId(uri), 'ABC123');
    });

    test('extrait le matchId avec un slash final', () {
      final uri = Uri.parse('kilimandjaro://duel/K3M9P2/');
      expect(parseDeepLinkMatchId(uri), 'K3M9P2');
    });

    test('extrait correctement un matchId long', () {
      final uri = Uri.parse('kilimandjaro://duel/ABCDEFGH');
      expect(parseDeepLinkMatchId(uri), 'ABCDEFGH');
    });

    // --- Cas invalides (retournent null) ---

    test('retourne null pour un scheme https', () {
      final uri = Uri.parse('https://kilimandjaro.app/duel/ABC123');
      expect(parseDeepLinkMatchId(uri), isNull);
    });

    test('retourne null pour le flow QR (host=join)', () {
      final uri = Uri.parse('kilimandjaro://join?m=ABC123&s=secret');
      expect(parseDeepLinkMatchId(uri), isNull);
    });

    test('retourne null si le host est absent', () {
      final uri = Uri.parse('kilimandjaro:///ABC123');
      expect(parseDeepLinkMatchId(uri), isNull);
    });

    test('retourne null si le matchId est vide', () {
      final uri = Uri.parse('kilimandjaro://duel/');
      expect(parseDeepLinkMatchId(uri), isNull);
    });

    test('retourne null pour un scheme différent', () {
      final uri = Uri.parse('https://example.com/duel/ABC123');
      expect(parseDeepLinkMatchId(uri), isNull);
    });

    test('retourne null pour kilimandjaro://duel sans path', () {
      final uri = Uri.parse('kilimandjaro://duel');
      expect(parseDeepLinkMatchId(uri), isNull);
    });

    // --- Caractères spéciaux ---

    test('accepte un matchId avec chiffres et majuscules (format réel)', () {
      // Format réel du repo : 6 chars [A-Z2-9]
      for (final id in ['A2B3C4', 'ZZZZZZ', '222222', 'QR5T6U']) {
        final uri = Uri.parse('kilimandjaro://duel/$id');
        expect(parseDeepLinkMatchId(uri), id, reason: 'matchId=$id');
      }
    });
  });
}
