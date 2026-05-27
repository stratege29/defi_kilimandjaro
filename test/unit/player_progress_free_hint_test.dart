import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests de l'indice gratuit quotidien : octroi idempotent par jour,
/// consommation prioritaire par `spendOnHint`, persistance.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PlayerProgressNotifier — claimFreeHintIfDue', () {
    test('premier appel octroie le freebie, retourne true', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(notifier.state.freeHintAvailable, isFalse);

      final granted = await notifier.claimFreeHintIfDue(
        date: DateTime(2026, 5, 26),
      );
      expect(granted, isTrue);
      expect(notifier.state.freeHintAvailable, isTrue);
      expect(
        notifier.state.lastFreeHintGrantedDate?.day,
        26,
      );
    });

    test('2e appel le même jour est un no-op (idempotent)', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      final first = await notifier.claimFreeHintIfDue(
        date: DateTime(2026, 5, 26, 8),
      );
      expect(first, isTrue);

      final second = await notifier.claimFreeHintIfDue(
        date: DateTime(2026, 5, 26, 20),
      );
      expect(second, isFalse);
      expect(notifier.state.freeHintAvailable, isTrue);
    });

    test('le lendemain ré-octroie un nouveau freebie', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.claimFreeHintIfDue(date: DateTime(2026, 5, 25));
      // Le joueur consomme dans la journée.
      await notifier.spendOnHint(20);
      expect(notifier.state.freeHintAvailable, isFalse);

      // Lendemain : nouvel octroi.
      final granted = await notifier.claimFreeHintIfDue(
        date: DateTime(2026, 5, 26),
      );
      expect(granted, isTrue);
      expect(notifier.state.freeHintAvailable, isTrue);
    });

    test('lendemain SANS consommation : pas de stack (max 1)', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));

      await notifier.claimFreeHintIfDue(date: DateTime(2026, 5, 25));
      // Joueur ne consomme pas. Lendemain, l'octroi est "ré-appliqué" :
      // freeHintAvailable reste true (déjà true), lastDate avance.
      final granted = await notifier.claimFreeHintIfDue(
        date: DateTime(2026, 5, 26),
      );
      expect(granted, isTrue);
      expect(notifier.state.freeHintAvailable, isTrue);
      // Confirme qu'il n'y a qu'un seul "slot" (drapeau bool, pas un int).
      expect(notifier.state.freeHintAvailable, isTrue);
    });
  });

  group('PlayerProgressNotifier — spendOnHint avec freebie', () {
    test(
      'freebie présent : consomme freebie, ne touche pas aux cauris',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));
        await notifier.claimFreeHintIfDue(date: DateTime(2026, 5, 26));
        expect(notifier.state.cauris, 120);
        expect(notifier.state.freeHintAvailable, isTrue);

        final ok = await notifier.spendOnHint(50);
        expect(ok, isTrue);
        expect(notifier.state.cauris, 120, reason: 'cauris intacts');
        expect(notifier.state.freeHintAvailable, isFalse);
      },
    );

    test(
      'pas de freebie : comportement standard (débite cauris)',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier =
            PlayerProgressNotifier(PlayerProgressRepository(prefs));
        expect(notifier.state.freeHintAvailable, isFalse);

        final ok = await notifier.spendOnHint(20);
        expect(ok, isTrue);
        expect(notifier.state.cauris, 100);
      },
    );

    test('freebie consommé : 2e indice débite les cauris', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.claimFreeHintIfDue(date: DateTime(2026, 5, 26));

      await notifier.spendOnHint(20); // freebie
      expect(notifier.state.cauris, 120);

      await notifier.spendOnHint(20); // cauris
      expect(notifier.state.cauris, 100);
    });

    test('freebie présent + solde insuffisant ⇒ consommation OK', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await notifier.claimFreeHintIfDue(date: DateTime(2026, 5, 26));

      // Le freebie protège même face à un coût > solde.
      final ok = await notifier.spendOnHint(99999);
      expect(ok, isTrue);
      expect(notifier.state.cauris, 120);
      expect(notifier.state.freeHintAvailable, isFalse);
    });
  });

  group('PlayerProgressNotifier — persistance free hint', () {
    test('freebie + lastDate survivent au redémarrage', () async {
      final prefs = await SharedPreferences.getInstance();
      final n1 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      await n1.claimFreeHintIfDue(date: DateTime(2026, 5, 26));

      final n2 = PlayerProgressNotifier(PlayerProgressRepository(prefs));
      expect(n2.state.freeHintAvailable, isTrue);
      expect(n2.state.lastFreeHintGrantedDate?.day, 26);
    });
  });
}
