import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PlayerProgress packs — persistance', () {
    test('état initial : aucun pack possédé, pas de free choice', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PlayerProgressRepository(prefs);
      final notifier = PlayerProgressNotifier(repo);
      expect(notifier.state.ownedPacks, isEmpty);
      expect(notifier.state.freePackChosen, isNull);
      expect(notifier.state.hasChosenFreePack, isFalse);
    });

    test('chooseFreePack ajoute le pack et bascule le mix', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      final ok = await notifier.chooseFreePack('culture_ci');
      expect(ok, isTrue);
      expect(notifier.state.ownedPacks, {'culture_ci'});
      expect(notifier.state.freePackChosen, 'culture_ci');
      expect(notifier.state.activePackMix, PackMix.single('culture_ci'));
    });

    test('chooseFreePack est immuable — deuxième appel ignoré', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');

      final result = await notifier.chooseFreePack('crack_nouchi');
      expect(result, isFalse);
      expect(notifier.state.freePackChosen, 'culture_ci');
      expect(notifier.state.ownedPacks, {'culture_ci'});
    });

    test('chooseFreePack persiste à travers les rechargements', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier1.chooseFreePack('culture_ci');

      // Simule un redémarrage de l'app : nouveau notifier sur les mêmes prefs.
      final notifier2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(notifier2.state.freePackChosen, 'culture_ci');
      expect(notifier2.state.activePackMix, PackMix.single('culture_ci'));
    });

    test('grantPack ajoute aux ownedPacks sans toucher au mix', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');

      await notifier.grantPack('crack_nouchi');
      expect(notifier.state.ownedPacks, {'culture_ci', 'crack_nouchi'});
      // Le mix actif reste mono-pack tant que l'utilisateur n'a pas trafiqué.
      expect(notifier.state.activePackMix, PackMix.single('culture_ci'));
    });

    test('grantPack idempotent', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('crack_nouchi');
      await notifier.grantPack('crack_nouchi');
      expect(notifier.state.ownedPacks, {'culture_ci', 'crack_nouchi'});
    });

    test('setActivePack refuse un pack non possédé', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');

      expect(
        () => notifier.setActivePack('crack_nouchi'),
        throwsArgumentError,
      );
      // Le pack actif n'a pas changé.
      expect(notifier.state.activePackId, 'culture_ci');
    });

    test('setActivePack bascule la grimpe courante et persiste', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('crack_nouchi');

      await notifier.setActivePack('crack_nouchi');
      expect(notifier.state.activePackId, 'crack_nouchi');
      expect(notifier.state.activePackMix, PackMix.single('crack_nouchi'));

      // Reload pour vérifier la persistance.
      final reloaded = PlayerProgressNotifier(
        PlayerProgressRepository(prefs),
      );
      expect(reloaded.state.activePackId, 'crack_nouchi');
    });

    test('reset remet à zéro les packs', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('crack_nouchi');

      await notifier.reset();
      expect(notifier.state.ownedPacks, isEmpty);
      expect(notifier.state.freePackChosen, isNull);
    });

    test('recordWin : progression indépendante par pack actif', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('football_ci');

      // Grimpe sur culture_ci.
      await notifier.recordWin(
        mountainId: 'ci_nimba',
        caurisAwarded: 0,
        levelIndex: 1,
        starsEarned: 3,
      );
      expect(notifier.state.levelsOn('ci_nimba'), 1);
      expect(notifier.state.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
          3);

      // Bascule sur football_ci → grimpe vierge (progression par pack).
      await notifier.setActivePack('football_ci');
      expect(notifier.state.levelsOn('ci_nimba'), 0);
      expect(notifier.state.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
          0);

      // Le total honorifique est GLOBAL (somme tous packs).
      expect(notifier.state.totalLevelsCompleted, 1);

      // Re-bascule sur culture_ci → progression retrouvée intacte.
      await notifier.setActivePack('culture_ci');
      expect(notifier.state.levelsOn('ci_nimba'), 1);
    });
  });

  group('PlayerProgress JSON roundtrip — packs', () {
    test('toJson + fromJson conserve ownedPacks, freePack, pack actif',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('crack_nouchi');
      await notifier.setActivePack('crack_nouchi');

      final raw = prefs.getString('player_progress');
      expect(raw, isNotNull);
      // On vérifie indirectement via le re-load.
      final reloaded = PlayerProgressRepository(prefs).load();
      expect(reloaded.ownedPacks, {'culture_ci', 'crack_nouchi'});
      expect(reloaded.freePackChosen, 'culture_ci');
      expect(reloaded.activePackId, 'crack_nouchi');
      expect(reloaded.activePackMix, PackMix.single('crack_nouchi'));
    });
  });
}
