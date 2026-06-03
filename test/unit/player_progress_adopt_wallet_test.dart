import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<PlayerProgressNotifier> buildNotifier() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerProgressNotifier(PlayerProgressRepository(prefs));
  }

  group('adoptWallet — réconciliation wallet serveur (non destructive)', () {
    test('appareil réinstallé : adopte le solde serveur supérieur', () async {
      final notifier = await buildNotifier();
      // Solde local = bienvenue (120) ; serveur = vrai solde de l'ancien
      // appareil.
      expect(notifier.state.cauris, 120);

      await notifier.adoptWallet(
        serverCauris: 850,
        serverOwnedPacks: const ['crack_nouchi'],
      );

      expect(notifier.state.cauris, 850);
      expect(notifier.state.ownedPacks, contains('crack_nouchi'));
    });

    test('même appareil : ne wipe pas les gains locaux (max)', () async {
      final notifier = await buildNotifier();
      await notifier.addCauris(5000); // gains in-game non poussés au serveur.
      expect(notifier.state.cauris, 5120);

      // Wallet serveur en retard (n'a pas reçu les gains).
      await notifier.adoptWallet(
        serverCauris: 200,
        serverOwnedPacks: const [],
      );

      expect(notifier.state.cauris, 5120); // local conservé.
    });

    test('packs : union, sans perdre le pack gratuit local', () async {
      final notifier = await buildNotifier();
      await notifier.chooseFreePack('culture_ci');

      await notifier.adoptWallet(
        serverCauris: 0,
        serverOwnedPacks: const ['crack_nouchi', 'football_ci'],
      );

      expect(notifier.state.ownedPacks, {
        'culture_ci',
        'crack_nouchi',
        'football_ci',
      });
    });

    test('no-op quand rien ne change (solde serveur inférieur, packs déjà là)',
        () async {
      final notifier = await buildNotifier();
      await notifier.chooseFreePack('culture_ci');
      final before = notifier.state;

      await notifier.adoptWallet(
        serverCauris: 50, // < 120 local
        serverOwnedPacks: const ['culture_ci'], // déjà possédé
      );

      expect(identical(notifier.state, before), isTrue);
    });
  });
}
