import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerProgress', () {
    test('initial state has 120 coins, no titles', () {
      final p = PlayerProgress.initial();
      expect(p.coins, 120);
      expect(p.totalLevelsCompleted, 0);
      expect(p.dailyStreak, 0);
      expect(p.completedLevelsByMountain, isEmpty);
      expect(p.consecutiveFailures, 0);
      expect(p.noAdsPurchased, isFalse);
    });

    test('toJson / fromJson round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        coins: 200,
        totalLevelsCompleted: 12,
        completedLevelsByMountain: const {'tz_kilimanjaro': 3},
        dailyStreak: 5,
        consecutiveFailures: 2,
        noAdsPurchased: true,
        lastPlayDate: DateTime(2026, 5, 3),
      );
      final json = p.toJson();
      final back = PlayerProgress.fromJson(json);
      expect(back.coins, 200);
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
      final p = PlayerProgress.fromJson(<String, dynamic>{});
      expect(p.coins, 120);
      expect(p.totalLevelsCompleted, 0);
      expect(p.consecutiveFailures, 0);
      expect(p.noAdsPurchased, isFalse);
    });
  });
}
