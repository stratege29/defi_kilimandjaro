import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameEconomyConfig.defaults — rééquilibrage cible "équilibré"', () {
    const d = GameEconomyConfig.defaults;

    test('faucet victoire tempéré + sinks scalés activés', () {
      expect(d.winRewardBase, 20);
      expect(d.speedBonusPerSecond, 1);
      expect(d.hintCost, 25);
      expect(d.revealCostBase, 40);
      expect(d.sinkTierScalingEnabled, isTrue);
    });
  });

  group('hintCostForIndex — escalade intra-niveau + scaling tier', () {
    test('scaling OFF → base × multiplier^index, tier ignoré', () {
      final c = GameEconomyConfig.defaults.copyWith(
        sinkTierScalingEnabled: false,
      );
      // base 25, multiplier 1.5
      expect(c.hintCostForIndex(0, tierMultiplier: 2.5), 25);
      expect(c.hintCostForIndex(1, tierMultiplier: 2.5), 38); // 25×1.5=37.5→38
      expect(c.hintCostForIndex(2, tierMultiplier: 2.5), 56); // 37.5×1.5=56.25
    });

    test('scaling ON → coût multiplié par le tierMultiplier', () {
      const c = GameEconomyConfig.defaults; // sinkTierScalingEnabled = true
      // T3 (×1.6) premier indice : 25×1.6 = 40
      expect(c.hintCostForIndex(0, tierMultiplier: 1.6), 40);
      // T5 (×2.5) premier indice : 25×2.5 = 62.5 → 63
      expect(c.hintCostForIndex(0, tierMultiplier: 2.5), 63);
      // T3 deuxième indice : 25×1.5×1.6 = 60
      expect(c.hintCostForIndex(1, tierMultiplier: 1.6), 60);
    });

    test('tierMultiplier par défaut = 1.0 (pas de scaling implicite)', () {
      const c = GameEconomyConfig.defaults;
      expect(c.hintCostForIndex(0), 25);
    });
  });

  group('revealCost — sink de révélation', () {
    test('scaling OFF → coût plat revealCostBase', () {
      final c = GameEconomyConfig.defaults.copyWith(
        sinkTierScalingEnabled: false,
      );
      expect(c.revealCost(tierMultiplier: 2.5), 40);
      expect(c.revealCost(), 40);
    });

    test('scaling ON → revealCostBase × tierMultiplier (≈ 1 victoire)', () {
      const c = GameEconomyConfig.defaults;
      expect(c.revealCost(tierMultiplier: 1.3), 52); // T2
      expect(c.revealCost(tierMultiplier: 1.6), 64); // T3
      expect(c.revealCost(tierMultiplier: 2), 80); // T4
      expect(c.revealCost(tierMultiplier: 2.5), 100); // T5
    });
  });

  group('freehandBonus — bonus « À main levée »', () {
    const d = GameEconomyConfig.defaults; // base 15, +3/lettre, seuil 4

    test('défauts câblés', () {
      expect(d.freehandBonusBase, 15);
      expect(d.freehandBonusPerLetter, 3);
      expect(d.freehandMinLength, 4);
    });

    test('mot trop court (< seuil) → 0', () {
      expect(d.freehandBonus(0), 0);
      expect(d.freehandBonus(3), 0);
    });

    test('exactement le seuil → forfait de base seul', () {
      expect(d.freehandBonus(4), 15); // 15 + 0×3
    });

    test('au-delà du seuil → base + (longueur − seuil) × perLetter', () {
      expect(d.freehandBonus(5), 18); // 15 + 1×3
      expect(d.freehandBonus(6), 21); // 15 + 2×3
      expect(d.freehandBonus(8), 27); // 15 + 4×3
    });

    test('overrides Remote Config respectés', () {
      final c = d.copyWith(
        freehandBonusBase: 10,
        freehandBonusPerLetter: 5,
        freehandMinLength: 5,
      );
      expect(c.freehandBonus(4), 0); // sous le nouveau seuil
      expect(c.freehandBonus(5), 10); // forfait
      expect(c.freehandBonus(7), 20); // 10 + 2×5
    });
  });

  group('streakRewardForDay — inchangé (faucet de rétention)', () {
    const d = GameEconomyConfig.defaults;

    test('escalier J1→J7 puis plateau', () {
      expect(d.streakRewardForDay(1), 10);
      expect(d.streakRewardForDay(7), 300);
      expect(d.streakRewardForDay(99), 300);
      expect(d.streakRewardForDay(0), 0);
    });
  });
}
