import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du défi du jour côté state : `recordDailyChallengeResult`
/// gère streak, day-skip et octroi de cauris correctement.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PlayerProgressNotifier — recordDailyChallengeResult succès', () {
    test('premier succès jamais joué : streak=1, +100 cauris', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(notifier.state.cauris, 120);
      expect(notifier.state.dailyChallengeStreak, 0);

      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(awarded, 100);
      expect(notifier.state.cauris, 220);
      expect(notifier.state.dailyChallengeStreak, 1);
      expect(
        notifier.state.lastDailyChallengeDate?.toIso8601String(),
        contains('2026-05-26'),
      );
    });

    test('succès consécutifs : streak incrémente', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 24),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 25),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(notifier.state.dailyChallengeStreak, 3);
      // 120 initial + 100 (J1) + 100 (J2) + 150 (J3 = palier bonus +50).
      // Cf. group "bonus série paliers 3/7/30" pour la décomposition.
      expect(notifier.state.cauris, 120 + 100 + 100 + 150);
    });
  });

  group('PlayerProgressNotifier — recordDailyChallengeResult échec', () {
    test('échec : streak reset à 0, aucun cauris', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      // Build une streak de 3 d'abord.
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 24),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 25),
        success: true,
      );
      expect(notifier.state.dailyChallengeStreak, 2);

      final balanceBefore = notifier.state.cauris;
      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: false,
      );
      expect(awarded, 0);
      expect(notifier.state.dailyChallengeStreak, 0);
      expect(notifier.state.cauris, balanceBefore);
    });
  });

  group('PlayerProgressNotifier — day-skip handling', () {
    test("succès après skip d'un jour : streak reset puis +1 = 1", () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      // Streak de 5 le 20 mai.
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 16),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 17),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 18),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 19),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 20),
        success: true,
      );
      expect(notifier.state.dailyChallengeStreak, 5);

      // Skip du 21, joue le 22 — streak doit redémarrer à 1.
      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 22),
        success: true,
      );
      expect(awarded, 100);
      expect(
        notifier.state.dailyChallengeStreak,
        1,
        reason: 'streak doit repartir à 1 après skip ≥ 2 jours',
      );
    });

    test('continuité parfaite (jour J+1) : pas de reset', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 25),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(notifier.state.dailyChallengeStreak, 2);
    });
  });

  group('PlayerProgressNotifier — bonus série paliers 3/7/30', () {
    test('atteindre exactement streak=3 ⇒ awarded = 100 + 50 = 150', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 24),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 25),
        success: true,
      );
      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(awarded, 150);
      expect(notifier.state.dailyChallengeStreak, 3);
      expect(notifier.state.cauris, 120 + 100 + 100 + 150);
    });

    test('streak=4 (jour APRÈS palier 3) ⇒ awarded = 100 seulement', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      // Build streak 3.
      for (var d = 24; d <= 26; d++) {
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, d),
          success: true,
        );
      }
      expect(notifier.state.dailyChallengeStreak, 3);

      final balanceBefore = notifier.state.cauris;
      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 27),
        success: true,
      );
      expect(
        awarded,
        100,
        reason: "palier 3 déjà reçu hier, aujourd'hui c'est juste +100",
      );
      expect(notifier.state.dailyChallengeStreak, 4);
      expect(notifier.state.cauris, balanceBefore + 100);
    });

    test('atteindre streak=7 ⇒ awarded = 100 + 200 = 300', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      for (var d = 20; d <= 25; d++) {
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, d),
          success: true,
        );
      }
      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(awarded, 300);
      expect(notifier.state.dailyChallengeStreak, 7);
    });

    test('atteindre streak=30 ⇒ awarded = 100 + 1000 = 1100', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      // 30 jours consécutifs.
      for (var d = 0; d < 29; d++) {
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5).add(Duration(days: d)),
          success: true,
        );
      }
      expect(notifier.state.dailyChallengeStreak, 29);

      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 30),
        success: true,
      );
      expect(awarded, 1100);
      expect(notifier.state.dailyChallengeStreak, 30);
    });

    test('échec ne déclenche jamais de bonus (streak reset à 0)', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      // Build streak 2 pour être sur le seuil.
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 25),
        success: true,
      );
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(notifier.state.dailyChallengeStreak, 2);

      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 27),
        success: false,
      );
      expect(awarded, 0);
      expect(notifier.state.dailyChallengeStreak, 0);
    });
  });

  group('PlayerProgressNotifier — persistance daily', () {
    test('streak et lastDate survivent au redémarrage', () async {
      final prefs = await SharedPreferences.getInstance();
      final n1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await n1.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );

      final n2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(n2.state.dailyChallengeStreak, 1);
      expect(
        n2.state.lastDailyChallengeDate?.toIso8601String(),
        contains('2026-05-26'),
      );
    });
  });
}
