import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyChallengeService — dailyKeyForDate', () {
    test('format ISO yyyy-MM-dd avec padding zéros', () {
      expect(
        DailyChallengeService.dailyKeyForDate(DateTime(2026, 1, 5)),
        '2026-01-05',
      );
      expect(
        DailyChallengeService.dailyKeyForDate(DateTime(2026, 12, 31)),
        '2026-12-31',
      );
    });

    test("ignore l'heure", () {
      expect(
        DailyChallengeService.dailyKeyForDate(
          DateTime(2026, 5, 26, 23, 59, 58),
        ),
        '2026-05-26',
      );
    });
  });

  group('DailyChallengeService — pickDevinetteIdForDate', () {
    test('retourne null sur pool vide', () {
      final picked = DailyChallengeService.pickDevinetteIdForDate(
        date: DateTime(2026, 5, 26),
        candidates: const <String>[],
      );
      expect(picked, isNull);
    });

    test('déterminisme : même date + même pool ⇒ même résultat', () {
      const pool = <String>['foutou_civ', 'attieke', 'kedjenou', 'alloco'];
      final date = DateTime(2026, 5, 26);
      final a = DailyChallengeService.pickDevinetteIdForDate(
        date: date,
        candidates: pool,
      );
      final b = DailyChallengeService.pickDevinetteIdForDate(
        date: date,
        candidates: pool,
      );
      expect(a, equals(b));
      expect(pool, contains(a));
    });

    test("indépendant de l'ordre du pool en entrée (tri défensif)", () {
      const poolA = <String>['foutou_civ', 'attieke', 'kedjenou', 'alloco'];
      const poolB = <String>['kedjenou', 'alloco', 'foutou_civ', 'attieke'];
      final date = DateTime(2026, 5, 26);
      expect(
        DailyChallengeService.pickDevinetteIdForDate(
          date: date,
          candidates: poolA,
        ),
        DailyChallengeService.pickDevinetteIdForDate(
          date: date,
          candidates: poolB,
        ),
      );
    });

    test('dates différentes ⇒ probablement résultats différents', () {
      // Sur 7 jours consécutifs et 4 candidats, on devrait voir au moins
      // 2 mots différents — sinon le hash est dégénéré.
      const pool = <String>['foutou_civ', 'attieke', 'kedjenou', 'alloco'];
      final results = <String>{};
      for (var d = 1; d <= 7; d++) {
        final r = DailyChallengeService.pickDevinetteIdForDate(
          date: DateTime(2026, 5, d),
          candidates: pool,
        );
        if (r != null) results.add(r);
      }
      expect(results.length, greaterThanOrEqualTo(2));
    });

    test("pool d'1 candidat retourne toujours ce candidat", () {
      const pool = <String>['only_one'];
      for (var d = 1; d <= 30; d++) {
        expect(
          DailyChallengeService.pickDevinetteIdForDate(
            date: DateTime(2026, 5, d),
            candidates: pool,
          ),
          'only_one',
        );
      }
    });
  });

  group('DailyChallengeService — isPlayedOn', () {
    test('false quand jamais joué', () {
      final p = PlayerProgress.initial();
      expect(
        DailyChallengeService.isPlayedOn(
          progress: p,
          date: DateTime(2026, 5, 26),
        ),
        isFalse,
      );
    });

    test('true quand last == date (même jour)', () {
      final p = PlayerProgress.initial().copyWith(
        lastDailyChallengeDate: DateTime(2026, 5, 26, 14, 30),
      );
      expect(
        DailyChallengeService.isPlayedOn(
          progress: p,
          date: DateTime(2026, 5, 26, 9),
        ),
        isTrue,
      );
    });

    test('false quand last == date - 1 jour', () {
      final p = PlayerProgress.initial().copyWith(
        lastDailyChallengeDate: DateTime(2026, 5, 25),
      );
      expect(
        DailyChallengeService.isPlayedOn(
          progress: p,
          date: DateTime(2026, 5, 26),
        ),
        isFalse,
      );
    });
  });

  group('DailyChallengeService — bonusForStreak', () {
    test('paliers exacts 3/7/30 octroient leur bonus', () {
      expect(DailyChallengeService.bonusForStreak(3), 50);
      expect(DailyChallengeService.bonusForStreak(7), 200);
      expect(DailyChallengeService.bonusForStreak(30), 1000);
    });

    test('streaks hors palier retournent 0', () {
      for (final s in <int>[0, 1, 2, 4, 5, 6, 8, 15, 29, 31, 100]) {
        expect(
          DailyChallengeService.bonusForStreak(s),
          0,
          reason: 'streak $s ne doit pas être un palier',
        );
      }
    });

    test('streak négatif (cas pathologique) retourne 0 sans planter', () {
      expect(DailyChallengeService.bonusForStreak(-1), 0);
      expect(DailyChallengeService.bonusForStreak(-100), 0);
    });
  });

  group('DailyChallengeService — streakMilestones', () {
    test('expose les paliers ordonnés [3, 7, 30]', () {
      expect(DailyChallengeService.streakMilestones, <int>[3, 7, 30]);
    });
  });

  group('DailyChallengeService — isStreakBroken', () {
    test('false quand jamais joué', () {
      expect(
        DailyChallengeService.isStreakBroken(
          progress: PlayerProgress.initial(),
          today: DateTime(2026, 5, 26),
        ),
        isFalse,
      );
    });

    test('false quand joué hier (continuité possible)', () {
      final p = PlayerProgress.initial().copyWith(
        lastDailyChallengeDate: DateTime(2026, 5, 25),
      );
      expect(
        DailyChallengeService.isStreakBroken(
          progress: p,
          today: DateTime(2026, 5, 26),
        ),
        isFalse,
      );
    });

    test("false quand joué aujourd'hui", () {
      final p = PlayerProgress.initial().copyWith(
        lastDailyChallengeDate: DateTime(2026, 5, 26, 8),
      );
      expect(
        DailyChallengeService.isStreakBroken(
          progress: p,
          today: DateTime(2026, 5, 26, 20),
        ),
        isFalse,
      );
    });

    test('true quand gap ≥ 2 jours (skip)', () {
      final p = PlayerProgress.initial().copyWith(
        lastDailyChallengeDate: DateTime(2026, 5, 24),
      );
      expect(
        DailyChallengeService.isStreakBroken(
          progress: p,
          today: DateTime(2026, 5, 26),
        ),
        isTrue,
      );
    });
  });
}
