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

    test('setPackMix valide que tous les packs sont possédés', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');

      expect(
        () => notifier.setPackMix(
          PackMix(
            weights: const <String, double>{
              'culture_ci': 0.5,
              'crack_nouchi': 0.5,
            },
          ),
        ),
        throwsArgumentError,
      );
    });

    test('setPackMix accepte un mix valide et persiste', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('crack_nouchi');

      final mix = PackMix(
        weights: const <String, double>{
          'culture_ci': 0.7,
          'crack_nouchi': 0.3,
        },
      );
      await notifier.setPackMix(mix);
      expect(notifier.state.activePackMix, mix);

      // Reload pour vérifier la persistance.
      final reloaded = PlayerProgressNotifier(
        PlayerProgressRepository(prefs),
      );
      expect(reloaded.state.activePackMix, mix);
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
  });

  group('PlayerProgress JSON roundtrip — packs', () {
    test('toJson + fromJson conserve ownedPacks, freePack, mix', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.chooseFreePack('culture_ci');
      await notifier.grantPack('crack_nouchi');
      await notifier.setPackMix(
        PackMix(
          weights: const <String, double>{
            'culture_ci': 0.6,
            'crack_nouchi': 0.4,
          },
        ),
      );

      final raw = prefs.getString('player_progress');
      expect(raw, isNotNull);
      // On vérifie indirectement via le re-load.
      final reloaded = PlayerProgressRepository(prefs).load();
      expect(reloaded.ownedPacks, {'culture_ci', 'crack_nouchi'});
      expect(reloaded.freePackChosen, 'culture_ci');
      expect(reloaded.activePackMix.weights['culture_ci'], closeTo(0.6, 1e-9));
      expect(reloaded.activePackMix.weights['crack_nouchi'], closeTo(0.4, 1e-9));
    });
  });
}
