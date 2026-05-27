import 'package:defi_kilimandjaro/data/repositories/composite_daily_challenge_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/daily_challenge_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests du composite repo : chaînage Firestore → Bundle, gestion
/// d'erreurs, fallback déterministe.
///
/// Pas de mockito ici — fakes manuels suffisent pour cette mécanique
/// simple (interface à 1 méthode).
void main() {
  group('CompositeDailyChallengeRepository — chaînage', () {
    test('primary succès ⇒ retourne primary, ignore fallback', () async {
      final primaryDevinette = _fakeDevinette('remote');
      final fallbackDevinette = _fakeDevinette('local');
      final composite = CompositeDailyChallengeRepository(
        primary: _FakeRepo(returns: primaryDevinette),
        fallback: _FakeRepo(returns: fallbackDevinette),
      );
      final result =
          await composite.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, primaryDevinette);
    });

    test('primary null ⇒ fallback bundle', () async {
      final fallbackDevinette = _fakeDevinette('local');
      final composite = CompositeDailyChallengeRepository(
        primary: _FakeRepo(),
        fallback: _FakeRepo(returns: fallbackDevinette),
      );
      final result =
          await composite.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, fallbackDevinette);
    });

    test('primary throw ⇒ fallback bundle', () async {
      final fallbackDevinette = _fakeDevinette('local');
      final composite = CompositeDailyChallengeRepository(
        primary: _FakeRepo(throwsOnFetch: true),
        fallback: _FakeRepo(returns: fallbackDevinette),
      );
      final result =
          await composite.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, fallbackDevinette);
    });

    test('primary null + fallback null ⇒ null (cas pathologique)', () async {
      final composite = CompositeDailyChallengeRepository(
        primary: _FakeRepo(),
        fallback: _FakeRepo(),
      );
      final result =
          await composite.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, isNull);
    });

    test('primary throw + fallback null ⇒ null', () async {
      final composite = CompositeDailyChallengeRepository(
        primary: _FakeRepo(throwsOnFetch: true),
        fallback: _FakeRepo(),
      );
      final result =
          await composite.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, isNull);
    });
  });
}

/// Fake minimaliste pour le repo daily.
class _FakeRepo implements DailyChallengeRepository {
  _FakeRepo({this.returns, this.throwsOnFetch = false});

  final Devinette? returns;
  final bool throwsOnFetch;

  @override
  Future<Devinette?> fetchDevinetteForDate(DateTime date) async {
    if (throwsOnFetch) {
      throw StateError('simulated network error');
    }
    return returns;
  }
}

Devinette _fakeDevinette(String id) {
  return Devinette(
    id: id,
    pack: 'fake_pack',
    country: 'ci',
    answer: 'TEST',
    lettersPool: const <String>['T', 'E', 'S', 'T'],
    riddleByLang: const <String, String>{'fr': 'riddle'},
    explanationByLang: const <String, String>{'fr': 'explanation'},
    difficulty: 1,
    estimatedTimeS: 30,
    tags: const <String>['test'],
  );
}
