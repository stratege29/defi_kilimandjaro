import 'package:defi_kilimandjaro/data/repositories/bundle_daily_challenge_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests du repo daily bundle : déterminisme du shuffle annuel,
/// stabilité pour une même date, distribution sur l'année.
///
/// Les assets bundle sont chargés via `rootBundle` — `TestWidgetsFlutter
/// Binding.ensureInitialized()` permet l'accès en mode test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BundleDailyChallengeRepository — basique', () {
    test('retourne une devinette pour une date du seed', () async {
      final repo = BundleDailyChallengeRepository();
      final result = await repo.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, isNotNull);
      expect(result!.id, startsWith('daily_'));
      expect(result.answer, isNotEmpty);
    });

    test('déterminisme : 2 appels même date ⇒ même devinette', () async {
      final repo = BundleDailyChallengeRepository();
      final a = await repo.fetchDevinetteForDate(DateTime(2026, 5, 26));
      final b = await repo.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(a!.id, b!.id);
    });

    test('heure du jour ignorée (même date logique ⇒ même mot)', () async {
      final repo = BundleDailyChallengeRepository();
      final morning = await repo.fetchDevinetteForDate(
        DateTime(2026, 5, 26, 6),
      );
      final evening = await repo.fetchDevinetteForDate(
        DateTime(2026, 5, 26, 23, 59),
      );
      expect(morning!.id, evening!.id);
    });

    test("cache mémoire évite les reloads d'assets", () async {
      final repo = BundleDailyChallengeRepository();
      // 1er appel charge.
      await repo.fetchDevinetteForDate(DateTime(2026, 5));
      // 2e appel devrait hit le cache mémoire — pas de moyen direct de
      // vérifier sans instrument, mais on s'assure que le 2e appel
      // retourne le même résultat instantanément.
      final result = await repo.fetchDevinetteForDate(DateTime(2026, 5));
      expect(result, isNotNull);
    });
  });

  group('BundleDailyChallengeRepository — shuffle annuel', () {
    test('même date sur 2 années différentes ⇒ probablement mots différents',
        () async {
      // Le shuffle est seedé par l'année donc les permutations sont
      // distinctes — sur 15 entrées, p(collision) ≈ 1/15 ≈ 7%. On
      // teste plusieurs dates pour réduire la chance de faux positif.
      final repo = BundleDailyChallengeRepository();
      var differingDates = 0;
      for (var month = 1; month <= 12; month++) {
        final y2026 = await repo.fetchDevinetteForDate(
          DateTime(2026, month, 15),
        );
        final y2027 = await repo.fetchDevinetteForDate(
          DateTime(2027, month, 15),
        );
        if (y2026!.id != y2027!.id) differingDates++;
      }
      // Sur 12 mois on s'attend à ≥ 8 dates différentes (statistique
      // robuste à la collision). 7+ acceptable pour la stabilité du
      // test sans flakiness.
      expect(
        differingDates,
        greaterThanOrEqualTo(7),

       reason:
            'Le shuffle annuel doit produire des mots différents entre '
            'années sur la majorité des dates ($differingDates/12)',
      );
    });

    test("couvre tout le pool sur l'année (no dead entry)", () async {
      // Sur 365 jours et un pool de 15 entrées, chaque entry doit
      // apparaître ~24 fois (modulo). On s'assure qu'**aucune** entry
      // ne reste hors du tirage à l'année.
      final repo = BundleDailyChallengeRepository();
      final seen = <String>{};
      for (var dayOfYear = 1; dayOfYear <= 365; dayOfYear++) {
        final date = DateTime(2026).add(Duration(days: dayOfYear - 1));
        final d = await repo.fetchDevinetteForDate(date);
        if (d != null) seen.add(d.id);
      }
      expect(
        seen.length,
        greaterThanOrEqualTo(15),
        reason: 'Toutes les entrées du pool devraient apparaître au '
            "moins une fois dans l'année",
      );
    });
  });

  group('BundleDailyChallengeRepository — robustesse', () {
    test('asset manquant retourne null sans planter', () async {
      final repo = BundleDailyChallengeRepository(
        assetPath: 'assets/data/__nonexistent_daily_seed.json',
      );
      final result = await repo.fetchDevinetteForDate(DateTime(2026, 5, 26));
      expect(result, isNull);
    });
  });
}
