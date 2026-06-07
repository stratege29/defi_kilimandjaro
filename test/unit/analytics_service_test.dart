import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalyticsKeys.sinkVariantValue — mapping variante A/B', () {
    test('true → "on", false → "off"', () {
      expect(AnalyticsKeys.sinkVariantValue(enabled: true), 'on');
      expect(AnalyticsKeys.sinkVariantValue(enabled: false), 'off');
    });

    test('nom de la user property stable', () {
      expect(AnalyticsKeys.sinkVariantProperty, 'ab_sink_tier_scaling');
    });
  });

  group('AnalyticsKeys.levelWonParams', () {
    test('inclut tous les champs requis', () {
      final p = AnalyticsKeys.levelWonParams(
        tier: 3,
        caurisAwarded: 66,
        hintsUsed: 1,
        timeLeft: 20,
        stars: 2,
        isDaily: false,
        levelIndex: 4,
        mountainId: 'ci_nimba',
      );
      expect(p, {
        'tier': 3,
        'cauris_awarded': 66,
        'hints_used': 1,
        'time_left': 20,
        'stars': 2,
        'is_daily': false,
        'level_index': 4,
        'mountain_id': 'ci_nimba',
      });
    });

    test('omet les champs nuls (GA4 refuse les valeurs nulles)', () {
      final p = AnalyticsKeys.levelWonParams(
        tier: 1,
        caurisAwarded: 25,
        hintsUsed: 0,
        timeLeft: 10,
        stars: 3,
        isDaily: true,
      );
      expect(p.containsKey('level_index'), isFalse);
      expect(p.containsKey('mountain_id'), isFalse);
      expect(p['is_daily'], true);
    });
  });

  group('AnalyticsKeys.hintUsedParams', () {
    test('free=true ⇒ flag posé, level_index omis si null', () {
      final p = AnalyticsKeys.hintUsedParams(tier: 5, cost: 0, free: true);
      expect(p['free'], true);
      expect(p['cost'], 0);
      expect(p['tier'], 5);
      expect(p.containsKey('level_index'), isFalse);
    });
  });

  group('AnalyticsKeys.answerRevealedParams', () {
    test('tier + cost', () {
      expect(
        AnalyticsKeys.answerRevealedParams(tier: 4, cost: 80),
        {'tier': 4, 'cost': 80},
      );
    });
  });

  group('AnalyticsKeys.purchaseParams', () {
    test('event ecommerce purchase : value + currency', () {
      final p = AnalyticsKeys.purchaseParams(
        productId: 'coins_pack_499',
        value: 4.99,
        currency: 'EUR',
      );
      expect(p, {
        'product_id': 'coins_pack_499',
        'value': 4.99,
        'currency': 'EUR',
      });
    });
  });

  group('NoopAnalyticsService — fail-soft, ne throw jamais', () {
    test('toutes les méthodes complètent sans erreur', () async {
      const svc = NoopAnalyticsService();
      await svc.init();
      await svc.setSinkScalingVariant(enabled: true);
      await svc.logLevelWon(
        tier: 1,
        caurisAwarded: 1,
        hintsUsed: 0,
        timeLeft: 0,
        stars: 1,
        isDaily: false,
      );
      await svc.logHintUsed(tier: 1, cost: 1, free: false);
      await svc.logAnswerRevealed(tier: 1, cost: 1);
      await svc.logIapPurchase(productId: 'x', value: 1, currency: 'EUR');
    });
  });
}
