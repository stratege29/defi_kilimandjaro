import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un jeu de paramètres produit par un builder de [AnalyticsKeys], étiqueté
/// pour que l'échec du contrat de types désigne le builder fautif.
typedef _BuilderCase = MapEntry<String, Map<String, Object>>;

/// Toutes les sorties possibles des builders : chaque builder y figure avec
/// les deux valeurs de chacun de ses flags booléens et les deux formes
/// (champs optionnels présents / omis), pour que le contrôle de types
/// balaie l'ensemble des branches.
List<_BuilderCase> _allBuilderOutputs() => <_BuilderCase>[
      _BuilderCase(
        'levelWonParams (flags true, champs optionnels présents)',
        AnalyticsKeys.levelWonParams(
          tier: 3,
          caurisAwarded: 66,
          hintsUsed: 1,
          timeLeft: 20,
          stars: 2,
          isDaily: true,
          kind: 'rafale',
          exposed: true,
          levelIndex: 4,
          mountainId: 'ci_nimba',
        ),
      ),
      _BuilderCase(
        'levelWonParams (flags false, champs optionnels omis)',
        AnalyticsKeys.levelWonParams(
          tier: 1,
          caurisAwarded: 25,
          hintsUsed: 0,
          timeLeft: 10,
          stars: 3,
          isDaily: false,
          kind: 'classic',
          exposed: false,
        ),
      ),
      _BuilderCase(
        'hintUsedParams (free=true, level_index omis)',
        AnalyticsKeys.hintUsedParams(tier: 5, cost: 0, free: true),
      ),
      _BuilderCase(
        'hintUsedParams (free=false, level_index présent)',
        AnalyticsKeys.hintUsedParams(
          tier: 2,
          cost: 40,
          free: false,
          levelIndex: 7,
        ),
      ),
      _BuilderCase(
        'answerRevealedParams',
        AnalyticsKeys.answerRevealedParams(tier: 4, cost: 80),
      ),
      _BuilderCase(
        'levelAbandonedParams (flags false, champs optionnels présents)',
        AnalyticsKeys.levelAbandonedParams(
          tier: 3,
          reason: AnalyticsKeys.abandonReasonQuit,
          timeLeft: 12,
          hintsUsed: 1,
          failsOnLevel: 2,
          isDaily: false,
          kind: 'duo',
          exposed: false,
          levelIndex: 3,
          mountainId: 'ke_kenya',
        ),
      ),
      _BuilderCase(
        'levelAbandonedParams (flags true, champs optionnels omis)',
        AnalyticsKeys.levelAbandonedParams(
          tier: 3,
          reason: AnalyticsKeys.abandonReasonSkipFree,
          timeLeft: 0,
          hintsUsed: 0,
          failsOnLevel: 0,
          isDaily: true,
          kind: 'blindBoss',
          exposed: true,
        ),
      ),
      _BuilderCase(
        'purchaseParams',
        AnalyticsKeys.purchaseParams(
          productId: 'coins_pack_499',
          value: 4.99,
          currency: 'EUR',
        ),
      ),
    ];

void main() {
  // Garde-fou principal : `firebase_analytics` assert que chaque valeur de
  // `parameters` est un `String` ou un `num` (cf. `_assertParameterTypesAreCorrect`
  // du plugin). Un `bool` faisait échouer l'event ENTIER, silencieusement —
  // `FirebaseAnalyticsService._safe` avale l'exception, donc rien ne
  // remontait dans GA4. Tout flag passe désormais par `AnalyticsKeys.flag`.
  group('Contrat de types GA4 — String / num uniquement', () {
    for (final entry in _allBuilderOutputs()) {
      test(entry.key, () {
        expect(entry.value, isNotEmpty);
        entry.value.forEach((key, value) {
          expect(
            value,
            isNot(isA<bool>()),
            reason: "'$key' est un bool : GA4 le refuse, "
                'utiliser AnalyticsKeys.flag().',
          );
          expect(
            value,
            anyOf(isA<String>(), isA<num>()),
            reason: "'$key' vaut $value (${value.runtimeType}) : seuls "
                'String et num sont acceptés par logEvent.',
          );
        });
      });
    }
  });

  group('AnalyticsKeys.flag — convention unique des booléens', () {
    test('true → 1, false → 0', () {
      expect(AnalyticsKeys.flag(value: true), 1);
      expect(AnalyticsKeys.flag(value: false), 0);
    });
  });

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
        kind: 'rafale',
        exposed: true,
        levelIndex: 4,
        mountainId: 'ci_nimba',
      );
      expect(p, {
        'tier': 3,
        'cauris_awarded': 66,
        'hints_used': 1,
        'time_left': 20,
        'stars': 2,
        'is_daily': 0,
        'kind': 'rafale',
        'exposed': 1,
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
        kind: 'classic',
        exposed: false,
      );
      expect(p.containsKey('level_index'), isFalse);
      expect(p.containsKey('mountain_id'), isFalse);
      expect(p['is_daily'], 1);
      expect(p['exposed'], 0);
    });
  });

  group('AnalyticsKeys.hintUsedParams', () {
    test('free=true ⇒ flag posé, level_index omis si null', () {
      final p = AnalyticsKeys.hintUsedParams(tier: 5, cost: 0, free: true);
      expect(p['free'], 1);
      expect(p['cost'], 0);
      expect(p['tier'], 5);
      expect(p.containsKey('level_index'), isFalse);
    });

    test('free=false ⇒ flag à 0', () {
      final p = AnalyticsKeys.hintUsedParams(tier: 5, cost: 40, free: false);
      expect(p['free'], 0);
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

  group('AnalyticsKeys.levelAbandonedParams', () {
    test('inclut tier, level_index, reason et contexte', () {
      final p = AnalyticsKeys.levelAbandonedParams(
        tier: 3,
        reason: AnalyticsKeys.abandonReasonQuit,
        timeLeft: 12,
        hintsUsed: 1,
        failsOnLevel: 2,
        isDaily: false,
        kind: 'duo',
        exposed: false,
        levelIndex: 3,
        mountainId: 'ke_kenya',
      );
      expect(p, {
        'tier': 3,
        'reason': 'quit',
        'time_left': 12,
        'hints_used': 1,
        'fails_on_level': 2,
        'is_daily': 0,
        'kind': 'duo',
        'exposed': 0,
        'level_index': 3,
        'mountain_id': 'ke_kenya',
      });
    });

    test('omet level_index et mountain_id nuls (Hub / défi du jour)', () {
      final p = AnalyticsKeys.levelAbandonedParams(
        tier: 3,
        reason: AnalyticsKeys.abandonReasonSkipFree,
        timeLeft: 0,
        hintsUsed: 0,
        failsOnLevel: 0,
        isDaily: true,
        kind: 'classic',
        exposed: false,
      );
      expect(p.containsKey('level_index'), isFalse);
      expect(p.containsKey('mountain_id'), isFalse);
      expect(p['reason'], 'skip_free');
      expect(p['is_daily'], 1);
    });

    test("raisons d'abandon stables (dimensions GA4)", () {
      expect(AnalyticsKeys.levelAbandoned, 'level_abandoned');
      expect(AnalyticsKeys.abandonReasonQuit, 'quit');
      expect(
        AnalyticsKeys.abandonReasonQuitAfterFailure,
        'quit_after_failure',
      );
      expect(AnalyticsKeys.abandonReasonSkipFree, 'skip_free');
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
        kind: 'classic',
        exposed: false,
      );
      await svc.logHintUsed(tier: 1, cost: 1, free: false);
      await svc.logAnswerRevealed(tier: 1, cost: 1);
      await svc.logLevelAbandoned(
        tier: 1,
        reason: AnalyticsKeys.abandonReasonQuit,
        timeLeft: 0,
        hintsUsed: 0,
        failsOnLevel: 0,
        isDaily: false,
        kind: 'classic',
        exposed: false,
      );
      await svc.logIapPurchase(productId: 'x', value: 1, currency: 'EUR');
    });
  });
}
