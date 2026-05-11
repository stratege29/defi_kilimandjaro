import 'package:defi_kilimandjaro/core/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
