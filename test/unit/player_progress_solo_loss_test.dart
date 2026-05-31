import 'package:defi_kilimandjaro/core/constants/loss_economy.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du mécanisme anti-tilt « skip gratuit » (Feature A).
///
/// Invariants produit :
/// - `recordSoloLoss` incrémente le compteur par devinette SANS pénalité
///   cauris (décision « ne pas punir l'échec »).
/// - le seuil `kFreeSkipLossThreshold` (3) déclenche l'offre de skip.
/// - victoire et skip remettent le compteur à 0 ; une victoire/skip sur
///   une devinette ne touche pas les compteurs des autres.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<PlayerProgressNotifier> makeNotifier() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerProgressNotifier(PlayerProgressRepository(prefs));
  }

  group('recordSoloLoss — compteur anti-tilt', () {
    test('incrémente sans toucher au solde de cauris', () async {
      final notifier = await makeNotifier();
      final caurisBefore = notifier.state.cauris;

      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_a');

      expect(notifier.state.consecutiveLossesOn('dev_a'), 2);
      expect(
        notifier.state.cauris,
        caurisBefore,
        reason: 'aucune pénalité cauris sur défaite solo',
      );
    });

    test('compteurs indépendants par devinette', () async {
      final notifier = await makeNotifier();
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_b');

      expect(notifier.state.consecutiveLossesOn('dev_a'), 2);
      expect(notifier.state.consecutiveLossesOn('dev_b'), 1);
      expect(notifier.state.consecutiveLossesOn('dev_inconnu'), 0);
    });

    test('id vide est ignoré (no-op)', () async {
      final notifier = await makeNotifier();
      await notifier.recordSoloLoss(devinetteId: '');
      expect(notifier.state.consecutiveLossesByDevinetteId, isEmpty);
    });

    test('le skip se déclenche exactement au seuil (3)', () async {
      final notifier = await makeNotifier();
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      expect(
        notifier.state.consecutiveLossesOn('dev_a') >= kFreeSkipLossThreshold,
        isFalse,
      );
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      expect(
        notifier.state.consecutiveLossesOn('dev_a') >= kFreeSkipLossThreshold,
        isFalse,
      );
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      expect(
        notifier.state.consecutiveLossesOn('dev_a') >= kFreeSkipLossThreshold,
        isTrue,
        reason: 'exactement 3 défaites consécutives ouvrent le skip',
      );
    });

    test('persiste à travers un redémarrage', () async {
      final prefs = await SharedPreferences.getInstance();
      final n1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await n1.recordSoloLoss(devinetteId: 'dev_a');
      await n1.recordSoloLoss(devinetteId: 'dev_a');

      final n2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(n2.state.consecutiveLossesOn('dev_a'), 2);
    });
  });

  group('reset du compteur — victoire & skip', () {
    test('victoire sur la devinette remet son compteur à 0', () async {
      final notifier = await makeNotifier();
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_b');

      await notifier.recordWin(
        mountainId: 'ci_nimba',
        levelIndex: 3,
        caurisAwarded: 100,
        starsEarned: 2,
        devinetteId: 'dev_a',
      );

      expect(notifier.state.consecutiveLossesOn('dev_a'), 0);
      expect(
        notifier.state.consecutiveLossesOn('dev_b'),
        1,
        reason: 'une autre devinette ne doit pas être touchée',
      );
    });

    test('victoire sans devinetteId ne touche aucun compteur', () async {
      final notifier = await makeNotifier();
      await notifier.recordSoloLoss(devinetteId: 'dev_a');

      await notifier.recordWin(
        mountainId: 'ci_nimba',
        levelIndex: 3,
        caurisAwarded: 100,
        starsEarned: 2,
      );

      expect(notifier.state.consecutiveLossesOn('dev_a'), 1);
    });

    test('skip gratuit remet le compteur à 0 sans pénalité', () async {
      final notifier = await makeNotifier();
      final caurisBefore = notifier.state.cauris;
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_a');
      await notifier.recordSoloLoss(devinetteId: 'dev_a');

      await notifier.recordSoloSkipFree(devinetteId: 'dev_a');

      expect(notifier.state.consecutiveLossesOn('dev_a'), 0);
      expect(notifier.state.cauris, caurisBefore);
    });

    test('skip sur une devinette sans compteur est un no-op', () async {
      final notifier = await makeNotifier();
      await notifier.recordSoloSkipFree(devinetteId: 'dev_inconnu');
      expect(notifier.state.consecutiveLossesByDevinetteId, isEmpty);
    });
  });
}
