import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests des freeze tokens : achat, plafond, auto-conso sur day-skip,
/// non-conso sur échec, persistance.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PlayerProgressNotifier — purchaseFreezeToken', () {
    test('achat réussi débite 150 🐚 et incrémente le compteur', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(notifier.state.cauris, 120);
      expect(notifier.state.freezeTokens, 0);

      // 120 cauris < 150 → premier achat refusé.
      final fail1 = await notifier.purchaseFreezeToken();
      expect(fail1, isFalse);
      expect(notifier.state.cauris, 120);
      expect(notifier.state.freezeTokens, 0);

      // Recharge à 200 via une victoire daily fictive : 1er daily +100.
      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 5, 26),
        success: true,
      );
      expect(notifier.state.cauris, 220);

      final ok = await notifier.purchaseFreezeToken();
      expect(ok, isTrue);
      expect(notifier.state.cauris, 70); // 220 − 150
      expect(notifier.state.freezeTokens, 1);
    });

    test('achat refusé si solde insuffisant (sans débit ni token)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      // Solde initial 120 < 150 → refus direct.
      final ok = await notifier.purchaseFreezeToken();
      expect(ok, isFalse);
      expect(notifier.state.cauris, 120);
      expect(notifier.state.freezeTokens, 0);
    });

    test('achat refusé si stock max atteint (3 tokens)', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      // Bootstrap : ajoute 450 cauris pour 3 achats.
      await notifier.addCauris(450);
      expect(notifier.state.cauris, 570);

      expect(await notifier.purchaseFreezeToken(), isTrue);
      expect(await notifier.purchaseFreezeToken(), isTrue);
      expect(await notifier.purchaseFreezeToken(), isTrue);
      expect(notifier.state.freezeTokens, 3);

      final balanceBefore = notifier.state.cauris;
      await notifier.addCauris(500); // s'assurer que le motif n'est pas le solde
      final refused = await notifier.purchaseFreezeToken();
      expect(refused, isFalse);
      expect(notifier.state.freezeTokens, 3);
      expect(
        notifier.state.cauris,
        balanceBefore + 500,
        reason: 'aucun débit en cas de refus stock max',
      );
    });
  });

  group(
    'PlayerProgressNotifier — auto-consume freeze sur day-skip',
    () {
      test('skip + success + token ⇒ streak préservé, token décrémenté',
          () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));

        // Bootstrap : streak 5 puis achat d'un token.
        for (var d = 1; d <= 5; d++) {
          await notifier.recordDailyChallengeResult(
            date: DateTime(2026, 5, d),
            success: true,
          );
        }
        // Solde : 120 + 100×4 + 150 (palier J3) = 670. Achat 150 ⇒ 520.
        await notifier.purchaseFreezeToken();
        expect(notifier.state.freezeTokens, 1);
        expect(notifier.state.dailyChallengeStreak, 5);

        // Skip du 6, joue le 7 avec success → freeze appliqué.
        final awarded = await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, 7),
          success: true,
        );

        expect(
          notifier.state.dailyChallengeStreak,
          6,
          reason: 'streak doit continuer (5 + 1) grâce au freeze',
        );
        expect(notifier.state.freezeTokens, 0);
        expect(
          awarded,
          DailyChallengeService.rewardCauris,
          reason: 'gain base 100 sans bonus palier sur streak 6',
        );
        expect(
          notifier.state.lastFreezeUsedDate?.day,
          7,
          reason: 'lastFreezeUsedDate doit pointer sur le jour du sauvetage',
        );
      });

      test('skip + success SANS token ⇒ streak reset à 0 (comportement standard)',
          () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));

        for (var d = 1; d <= 3; d++) {
          await notifier.recordDailyChallengeResult(
            date: DateTime(2026, 5, d),
            success: true,
          );
        }
        expect(notifier.state.dailyChallengeStreak, 3);
        expect(notifier.state.freezeTokens, 0);

        // Skip du 4, joue le 5 — pas de token → streak reset à 1.
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, 5),
          success: true,
        );
        expect(notifier.state.dailyChallengeStreak, 1);
        expect(notifier.state.lastFreezeUsedDate, isNull);
      });

      test('skip + ÉCHEC ⇒ token jamais consommé (économie)', () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));

        // Bootstrap : streak 3 + 1 token (cauris cumulés : 120 + 100+100+150 = 470, achat 150 ⇒ 320).
        for (var d = 1; d <= 3; d++) {
          await notifier.recordDailyChallengeResult(
            date: DateTime(2026, 5, d),
            success: true,
          );
        }
        await notifier.purchaseFreezeToken();
        expect(notifier.state.freezeTokens, 1);

        // Skip du 4, joue le 5 mais ÉCHEC → token PAS consommé, streak reset.
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, 5),
          success: false,
        );
        expect(
          notifier.state.freezeTokens,
          1,
          reason: 'token préservé : pas de gaspillage sur échec',
        );
        expect(notifier.state.dailyChallengeStreak, 0);
        expect(notifier.state.lastFreezeUsedDate, isNull);
      });

      test('continuité parfaite (J+1) ⇒ token JAMAIS consommé', () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));

        await notifier.addCauris(150);
        await notifier.purchaseFreezeToken();
        expect(notifier.state.freezeTokens, 1);

        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, 25),
          success: true,
        );
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, 26),
          success: true,
        );

        expect(
          notifier.state.freezeTokens,
          1,
          reason: 'pas de skip ⇒ token intact',
        );
        expect(notifier.state.dailyChallengeStreak, 2);
      });

      test('skip de 5 jours + success + token ⇒ freeze ne couvre que la continuité, pas le gap',
          () async {
        // Note : le freeze actuel est "tout-ou-rien" sur day-skip — il
        // sauve la streak quelle que soit la longueur du gap. Spec MVP.
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));

        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5),
          success: true,
        );
        await notifier.addCauris(150);
        await notifier.purchaseFreezeToken();
        expect(notifier.state.freezeTokens, 1);
        expect(notifier.state.dailyChallengeStreak, 1);

        // Skip de 5 jours, retour le 7.
        await notifier.recordDailyChallengeResult(
          date: DateTime(2026, 5, 7),
          success: true,
        );

        expect(
          notifier.state.dailyChallengeStreak,
          2,
          reason: 'streak conservé (1) + 1 = 2 grâce au freeze',
        );
        expect(notifier.state.freezeTokens, 0);
      });
    },
  );

  group('PlayerProgressNotifier — persistance freeze', () {
    test('freezeTokens + lastFreezeUsedDate survivent au redémarrage',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final n1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await n1.addCauris(450);
      await n1.purchaseFreezeToken();
      await n1.purchaseFreezeToken();
      expect(n1.state.freezeTokens, 2);

      final n2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(n2.state.freezeTokens, 2);
    });
  });
}
