import 'package:defi_kilimandjaro/core/deep_links.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
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

  group('parseDeepLinkJoin', () {
    // Le QR de duel peut être scanné par l'appareil photo du téléphone :
    // l'URL arrive alors comme deep link, et non par le scanner in-app.

    // --- Cas valides ---

    test('extrait matchId et secret', () {
      final uri = Uri.parse('kilimandjaro://join?m=A2B3C4&s=deadbeef');
      final parsed = parseDeepLinkJoin(uri);
      expect(parsed, isNotNull);
      expect(parsed!.matchId, 'A2B3C4');
      expect(parsed.secret, 'deadbeef');
    });

    test('lit le payload réellement encodé par toQrPayload', () {
      // Le QR affiché à l'écran et ce parseur doivent rester d'accord.
      const matchId = 'UNCUWW';
      const secret = 'fc448d5bc7f0ded67863fca5';
      final payload = DuelSession(
        matchId: matchId,
        secret: secret,
        createdBy: 'uid',
        createdAt: 0,
        phase: DuelPhase.waiting,
      ).toQrPayload();

      final parsed = parseDeepLinkJoin(Uri.parse(payload));
      expect(parsed, isNotNull);
      expect(parsed!.matchId, matchId);
      expect(parsed.secret, secret);

      // Et le scanner in-app lit exactement la même chose.
      final scanned = DuelSession.parseQrPayload(payload);
      expect(scanned?.matchId, parsed.matchId);
      expect(scanned?.secret, parsed.secret);
    });

    // --- Cas invalides (retournent null) ---

    test('retourne null si le secret manque', () {
      expect(parseDeepLinkJoin(Uri.parse('kilimandjaro://join?m=A2B3C4')),
          isNull);
    });

    test('retourne null si le matchId manque', () {
      expect(parseDeepLinkJoin(Uri.parse('kilimandjaro://join?s=abc')), isNull);
    });

    test('retourne null si un paramètre est vide', () {
      expect(parseDeepLinkJoin(Uri.parse('kilimandjaro://join?m=&s=abc')),
          isNull);
      expect(parseDeepLinkJoin(Uri.parse('kilimandjaro://join?m=A2B3C4&s=')),
          isNull);
    });

    test('retourne null pour un autre host', () {
      expect(parseDeepLinkJoin(Uri.parse('kilimandjaro://duel/A2B3C4')), isNull);
      expect(
          parseDeepLinkJoin(Uri.parse('kilimandjaro://friend/uid')), isNull);
    });

    test('retourne null pour un scheme différent', () {
      expect(
        parseDeepLinkJoin(Uri.parse('https://kilimandjaro.app/join?m=A&s=B')),
        isNull,
      );
    });

    // --- Les trois schémas restent distincts ---

    test('les parseurs ne se marchent pas dessus', () {
      final join = Uri.parse('kilimandjaro://join?m=A2B3C4&s=abc');
      expect(parseDeepLinkMatchId(join), isNull);
      expect(parseDeepLinkFriendUid(join), isNull);

      final duel = Uri.parse('kilimandjaro://duel/A2B3C4');
      expect(parseDeepLinkJoin(duel), isNull);

      final friend = Uri.parse('kilimandjaro://friend/uid123');
      expect(parseDeepLinkJoin(friend), isNull);
    });
  });

  group('AppRoutes.duelJoinPath', () {
    test('sans secret : path nu', () {
      expect(AppRoutes.duelJoinPath('A2B3C4'), '/duel/join/A2B3C4');
    });

    test('avec secret : secret en query', () {
      expect(
        AppRoutes.duelJoinPath('A2B3C4', secret: 'deadbeef'),
        '/duel/join/A2B3C4?s=deadbeef',
      );
    });

    test('un secret vide ne laisse pas de query pendante', () {
      // Cas réel : la route lit `queryParameters['s'] ?? ''`, donc la vue
      // rappelle ce builder avec une chaîne vide quand le QR n'en portait pas.
      // ignore: avoid_redundant_argument_values
      expect(AppRoutes.duelJoinPath('A2B3C4', secret: ''), '/duel/join/A2B3C4');
    });

    test('le secret est encodé', () {
      final path = AppRoutes.duelJoinPath('A2B3C4', secret: 'a b&c=d');
      expect(path, isNot(contains(' ')));
      expect(Uri.parse(path).queryParameters['s'], 'a b&c=d');
    });

    test('bout en bout : QR → route → secret relu', () {
      const payload = 'kilimandjaro://join?m=ADJSUR&s=57147738d36f8b408b32e893';
      final parsed = parseDeepLinkJoin(Uri.parse(payload))!;
      final path = AppRoutes.duelJoinPath(parsed.matchId,
          secret: parsed.secret);
      final route = Uri.parse(path);
      expect(route.path, '/duel/join/ADJSUR');
      expect(route.queryParameters['s'], '57147738d36f8b408b32e893');
    });
  });
}
