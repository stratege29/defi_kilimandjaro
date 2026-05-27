import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerProgress', () {
    test('initial state has 120 cauris, no titles', () {
      final p = PlayerProgress.initial();
      expect(p.cauris, 120);
      expect(p.totalLevelsCompleted, 0);
      expect(p.dailyStreak, 0);
      expect(p.completedLevelsByMountain, isEmpty);
      expect(p.consecutiveFailures, 0);
      expect(p.noAdsPurchased, isFalse);
    });

    test('toJson / fromJson round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        cauris: 200,
        totalLevelsCompleted: 12,
        completedLevelsByMountain: const {'tz_kilimanjaro': 3},
        dailyStreak: 5,
        consecutiveFailures: 2,
        noAdsPurchased: true,
        lastPlayDate: DateTime(2026, 5, 3),
      );
      final json = p.toJson();
      final back = PlayerProgress.fromJson(json);
      expect(back.cauris, 200);
      expect(back.totalLevelsCompleted, 12);
      expect(back.completedLevelsByMountain['tz_kilimanjaro'], 3);
      expect(back.dailyStreak, 5);
      expect(back.consecutiveFailures, 2);
      expect(back.noAdsPurchased, isTrue);
      expect(back.lastPlayDate, DateTime(2026, 5, 3));
    });

    test('levelsOn returns 0 by default', () {
      expect(PlayerProgress.initial().levelsOn('any_mountain'), 0);
    });

    test('fromJson tolerates missing fields', () {
      final p = PlayerProgress.fromJson(const <String, dynamic>{});
      expect(p.cauris, 120);
      expect(p.totalLevelsCompleted, 0);
      expect(p.consecutiveFailures, 0);
      expect(p.noAdsPurchased, isFalse);
    });

    test('fromJson reads legacy `coins` key (pre-rebrand saves)', () {
      final p = PlayerProgress.fromJson(const <String, dynamic>{'coins': 333});
      expect(p.cauris, 333);
    });

    test('starsByLevel persistance round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        starsByLevel: const <String, int>{
          'ci_nimba#1': 3,
          'ci_nimba#2': 2,
          'tz_kilimanjaro#8': 1,
        },
      );
      final back = PlayerProgress.fromJson(p.toJson());
      expect(back.starsByLevel['ci_nimba#1'], 3);
      expect(back.starsByLevel['ci_nimba#2'], 2);
      expect(back.starsByLevel['tz_kilimanjaro#8'], 1);
    });

    test('starsByLevel absent du JSON quand vide (économie de bytes)', () {
      final json = PlayerProgress.initial().toJson();
      expect(json.containsKey('stars_by_level'), isFalse);
    });

    test('starsOnLevel retourne 0 quand niveau jamais joué', () {
      final p = PlayerProgress.initial();
      expect(
        p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
        0,
      );
    });

    test('starsOnLevel lit la valeur persistée', () {
      final p = PlayerProgress.initial().copyWith(
        starsByLevel: const <String, int>{'ci_nimba#3': 2},
      );
      expect(
        p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        2,
      );
    });

    test('failsByLevel persistance round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        failsByLevel: const <String, int>{
          'ci_nimba#3': 2,
          'tz_kilimanjaro#5': 1,
        },
      );
      final back = PlayerProgress.fromJson(p.toJson());
      expect(back.failsByLevel['ci_nimba#3'], 2);
      expect(back.failsByLevel['tz_kilimanjaro#5'], 1);
    });

    test('failsByLevel absent du JSON quand vide (économie de bytes)', () {
      final json = PlayerProgress.initial().toJson();
      expect(json.containsKey('fails_by_level'), isFalse);
    });

    test('failsOnLevel retourne 0 par défaut', () {
      final p = PlayerProgress.initial();
      expect(
        p.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
        0,
      );
    });

    test('failsOnLevel lit la valeur persistée', () {
      final p = PlayerProgress.initial().copyWith(
        failsByLevel: const <String, int>{'ci_nimba#3': 2},
      );
      expect(
        p.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        2,
      );
    });

    test('totalStars somme toutes les étoiles persistées', () {
      final p = PlayerProgress.initial().copyWith(
        starsByLevel: const <String, int>{
          'gm_red_rocks#1': 3,
          'gm_red_rocks#2': 2,
          'sn_sambadougou#1': 1,
          'sn_sambadougou#2': 3,
        },
      );
      expect(p.totalStars, 9);
    });

    test('totalStars = 0 sur état initial', () {
      expect(PlayerProgress.initial().totalStars, 0);
    });
  });
}
