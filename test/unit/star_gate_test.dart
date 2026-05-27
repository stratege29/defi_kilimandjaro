import 'package:defi_kilimandjaro/domain/services/star_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StarGate — thresholdForTier', () {
    test('Tier 2 = porte libre (0 étoile requise)', () {
      expect(StarGate.thresholdForTier(2), 0);
    });

    test('Tiers 3/4/5 ont les seuils calibrés', () {
      expect(StarGate.thresholdForTier(3), 30);
      expect(StarGate.thresholdForTier(4), 120);
      expect(StarGate.thresholdForTier(5), 250);
    });

    test('Tier hors plage lève ArgumentError', () {
      expect(() => StarGate.thresholdForTier(1), throwsArgumentError);
      expect(() => StarGate.thresholdForTier(6), throwsArgumentError);
      expect(() => StarGate.thresholdForTier(0), throwsArgumentError);
    });
  });

  group('StarGate — computeUnlockedTier', () {
    test('0 étoile → tier 2 débloqué (zone tutoriel + Tier 2)', () {
      expect(StarGate.computeUnlockedTier(0), 2);
    });

    test('29 étoiles (sous T3) reste à tier 2', () {
      expect(StarGate.computeUnlockedTier(29), 2);
    });

    test('30 étoiles (seuil exact T3) débloque T3', () {
      expect(StarGate.computeUnlockedTier(30), 3);
    });

    test('119 étoiles reste à T3', () {
      expect(StarGate.computeUnlockedTier(119), 3);
    });

    test('120 étoiles (seuil exact T4) débloque T4', () {
      expect(StarGate.computeUnlockedTier(120), 4);
    });

    test('249 étoiles reste à T4', () {
      expect(StarGate.computeUnlockedTier(249), 4);
    });

    test('250 étoiles (seuil exact T5) débloque T5', () {
      expect(StarGate.computeUnlockedTier(250), 5);
    });

    test('au-delà du dernier seuil reste à T5 (pas de tier 6)', () {
      expect(StarGate.computeUnlockedTier(696), 5);
      expect(StarGate.computeUnlockedTier(99999), 5);
    });
  });

  group('StarGate — starsNeededForTier', () {
    test('targetTier ≤ 2 : aucune étoile manquante', () {
      expect(
        StarGate.starsNeededForTier(targetTier: 1, currentTotal: 0),
        0,
      );
      expect(
        StarGate.starsNeededForTier(targetTier: 2, currentTotal: 0),
        0,
      );
    });

    test('seuil non atteint : retourne le manquant exact', () {
      expect(
        StarGate.starsNeededForTier(targetTier: 3, currentTotal: 0),
        30,
      );
      expect(
        StarGate.starsNeededForTier(targetTier: 3, currentTotal: 25),
        5,
      );
      expect(
        StarGate.starsNeededForTier(targetTier: 5, currentTotal: 100),
        150,
      );
    });

    test('seuil atteint ou dépassé : 0', () {
      expect(
        StarGate.starsNeededForTier(targetTier: 3, currentTotal: 30),
        0,
      );
      expect(
        StarGate.starsNeededForTier(targetTier: 3, currentTotal: 200),
        0,
      );
    });
  });
}
