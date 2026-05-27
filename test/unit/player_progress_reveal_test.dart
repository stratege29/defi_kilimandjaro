import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du sink "reveal payant T3+" — compteur d'échecs par niveau,
/// reset à la victoire, débit cauris via `purchaseReveal`.
///
/// Persistance via `SharedPreferences.setMockInitialValues({})` —
/// même pattern que les tests existants (`player_progress_packs_test`).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PlayerProgressNotifier — recordLevelFailure', () {
    test('incrémente le compteur du niveau et le retourne', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      final n1 = await notifier.recordLevelFailure(
        mountainId: 'ci_nimba',
        levelIndex: 3,
      );
      expect(n1, 1);

      final n2 = await notifier.recordLevelFailure(
        mountainId: 'ci_nimba',
        levelIndex: 3,
      );
      expect(n2, 2);

      final n3 = await notifier.recordLevelFailure(
        mountainId: 'ci_nimba',
        levelIndex: 3,
      );
      expect(n3, 3);
      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        3,
      );
    });

    test('compteurs indépendants par niveau', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 1);
      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 1);
      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 2);

      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
        2,
      );
      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 2),
        1,
      );
      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 99),
        0,
      );
    });

    test('persistance à travers redémarrage', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier1.recordLevelFailure(
        mountainId: 'ci_nimba',
        levelIndex: 3,
      );
      await notifier1.recordLevelFailure(
        mountainId: 'ci_nimba',
        levelIndex: 3,
      );

      // Simule un redémarrage : nouveau notifier sur les mêmes prefs.
      final notifier2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(
        notifier2.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        2,
      );
    });
  });

  group('PlayerProgressNotifier — recordWin reset failsByLevel', () {
    test("victoire sur un niveau efface SON compteur d'échecs", () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 3);
      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 3);
      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        2,
      );

      await notifier.recordWin(
        mountainId: 'ci_nimba',
        levelIndex: 3,
        caurisAwarded: 100,
        starsEarned: 2,
      );

      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        0,
      );
    });

    test('victoire sur niveau A ne touche pas au compteur du niveau B',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 1);
      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 2);
      await notifier.recordLevelFailure(mountainId: 'ci_nimba', levelIndex: 2);

      await notifier.recordWin(
        mountainId: 'ci_nimba',
        levelIndex: 1,
        caurisAwarded: 50,
        starsEarned: 1,
      );

      // Niveau 1 reset, niveau 2 intact.
      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
        0,
      );
      expect(
        notifier.state.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 2),
        2,
      );
    });
  });

  group('PlayerProgressNotifier — purchaseReveal', () {
    test('débite le coût et retourne true quand solde suffisant', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(notifier.state.cauris, 120); // initial

      final ok = await notifier.purchaseReveal(50);
      expect(ok, isTrue);
      expect(notifier.state.cauris, 70);
    });

    test('retourne false sans débit quand solde insuffisant', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      // Force un solde bas (10 cauris).
      await notifier.purchaseReveal(110);
      expect(notifier.state.cauris, 10);

      final ok = await notifier.purchaseReveal(50);
      expect(ok, isFalse);
      expect(notifier.state.cauris, 10, reason: "aucun débit en cas d'échec");
    });

    test('coût zéro ou négatif retourne true sans débit (no-op)', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(await notifier.purchaseReveal(0), isTrue);
      expect(notifier.state.cauris, 120);
      expect(await notifier.purchaseReveal(-10), isTrue);
      expect(notifier.state.cauris, 120);
    });

    test('persistance du débit à travers redémarrage', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier1.purchaseReveal(50);

      final notifier2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(notifier2.state.cauris, 70);
    });
  });
}
