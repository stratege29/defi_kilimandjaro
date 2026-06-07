import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Abstraction de l'instrumentation analytics (GA4) — découple l'app du
/// plugin `firebase_analytics` pour la testabilité et le respect des
/// couches.
///
/// Toutes les méthodes sont **fail-soft** : l'analytics ne doit JAMAIS
/// faire crasher le gameplay. Les implémentations avalent leurs erreurs.
///
/// Sert à mesurer l'A/B `eco_sink_tier_scaling` (rééquilibrage cauris) :
/// la user property [AnalyticsKeys.sinkVariantProperty] tague chaque user
/// avec sa variante, et les events économie alimentent les métriques
/// secondaires de l'experiment Firebase A/B Testing.
abstract interface class AnalyticsService {
  /// Active la collecte (no-op si déjà active par défaut).
  Future<void> init();

  /// Pose la variante A/B du scaling des sinks comme user property GA4.
  Future<void> setSinkScalingVariant({required bool enabled});

  /// Victoire d'un niveau (standard ou défi du jour).
  Future<void> logLevelWon({
    required int tier,
    required int caurisAwarded,
    required int hintsUsed,
    required int timeLeft,
    required int stars,
    required bool isDaily,
    int? levelIndex,
    String? mountainId,
  });

  /// Usage d'un indice (payant ou freebie quotidien).
  Future<void> logHintUsed({
    required int tier,
    required int cost,
    required bool free,
    int? levelIndex,
  });

  /// Révélation payante de la réponse à l'écran d'échec (T2+).
  Future<void> logAnswerRevealed({required int tier, required int cost});

  /// Achat IAP validé — event ecommerce `purchase` (revenu → ARPDAU GA4).
  Future<void> logIapPurchase({
    required String productId,
    required double value,
    required String currency,
  });
}

/// Noms d'events / user properties + builders **purs** des maps de
/// paramètres. Extraits ici pour être testables sans le plugin Firebase
/// (le plugin est intestable en unitaire). La conversion `null → omis` est
/// gérée à la construction : GA4 refuse les valeurs nulles.
abstract final class AnalyticsKeys {
  static const String sinkVariantProperty = 'ab_sink_tier_scaling';

  static const String levelWon = 'level_won';
  static const String hintUsed = 'hint_used';
  static const String answerRevealed = 'answer_revealed';
  static const String purchase = 'purchase';

  /// Mapping de la variante A/B vers la valeur de user property GA4.
  static String sinkVariantValue({required bool enabled}) =>
      enabled ? 'on' : 'off';

  static Map<String, Object> levelWonParams({
    required int tier,
    required int caurisAwarded,
    required int hintsUsed,
    required int timeLeft,
    required int stars,
    required bool isDaily,
    int? levelIndex,
    String? mountainId,
  }) =>
      <String, Object>{
        'tier': tier,
        'cauris_awarded': caurisAwarded,
        'hints_used': hintsUsed,
        'time_left': timeLeft,
        'stars': stars,
        'is_daily': isDaily,
        if (levelIndex != null) 'level_index': levelIndex,
        if (mountainId != null) 'mountain_id': mountainId,
      };

  static Map<String, Object> hintUsedParams({
    required int tier,
    required int cost,
    required bool free,
    int? levelIndex,
  }) =>
      <String, Object>{
        'tier': tier,
        'cost': cost,
        'free': free,
        if (levelIndex != null) 'level_index': levelIndex,
      };

  static Map<String, Object> answerRevealedParams({
    required int tier,
    required int cost,
  }) =>
      <String, Object>{'tier': tier, 'cost': cost};

  static Map<String, Object> purchaseParams({
    required String productId,
    required double value,
    required String currency,
  }) =>
      <String, Object>{
        'product_id': productId,
        'value': value,
        'currency': currency,
      };
}

/// Implémentation réelle au-dessus de [FirebaseAnalytics].
class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;
  final Logger _log = Logger();

  Future<void> _safe(String label, Future<void> Function() op) async {
    try {
      await op();
    } on Object catch (e) {
      _log.w('Analytics $label failed (ignoré): $e');
    }
  }

  @override
  Future<void> init() =>
      _safe('init', () => _analytics.setAnalyticsCollectionEnabled(true));

  @override
  Future<void> setSinkScalingVariant({required bool enabled}) => _safe(
        'setSinkScalingVariant',
        () => _analytics.setUserProperty(
          name: AnalyticsKeys.sinkVariantProperty,
          value: AnalyticsKeys.sinkVariantValue(enabled: enabled),
        ),
      );

  @override
  Future<void> logLevelWon({
    required int tier,
    required int caurisAwarded,
    required int hintsUsed,
    required int timeLeft,
    required int stars,
    required bool isDaily,
    int? levelIndex,
    String? mountainId,
  }) =>
      _safe(
        'logLevelWon',
        () => _analytics.logEvent(
          name: AnalyticsKeys.levelWon,
          parameters: AnalyticsKeys.levelWonParams(
            tier: tier,
            caurisAwarded: caurisAwarded,
            hintsUsed: hintsUsed,
            timeLeft: timeLeft,
            stars: stars,
            isDaily: isDaily,
            levelIndex: levelIndex,
            mountainId: mountainId,
          ),
        ),
      );

  @override
  Future<void> logHintUsed({
    required int tier,
    required int cost,
    required bool free,
    int? levelIndex,
  }) =>
      _safe(
        'logHintUsed',
        () => _analytics.logEvent(
          name: AnalyticsKeys.hintUsed,
          parameters: AnalyticsKeys.hintUsedParams(
            tier: tier,
            cost: cost,
            free: free,
            levelIndex: levelIndex,
          ),
        ),
      );

  @override
  Future<void> logAnswerRevealed({required int tier, required int cost}) =>
      _safe(
        'logAnswerRevealed',
        () => _analytics.logEvent(
          name: AnalyticsKeys.answerRevealed,
          parameters: AnalyticsKeys.answerRevealedParams(tier: tier, cost: cost),
        ),
      );

  @override
  Future<void> logIapPurchase({
    required String productId,
    required double value,
    required String currency,
  }) =>
      _safe(
        'logIapPurchase',
        () => _analytics.logEvent(
          name: AnalyticsKeys.purchase,
          parameters: AnalyticsKeys.purchaseParams(
            productId: productId,
            value: value,
            currency: currency,
          ),
        ),
      );
}

/// Implémentation neutre (no-op) — défaut du provider et fallback tests /
/// plateformes sans analytics. Évite tout `null` côté call-sites.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> init() async {}

  @override
  Future<void> setSinkScalingVariant({required bool enabled}) async {}

  @override
  Future<void> logLevelWon({
    required int tier,
    required int caurisAwarded,
    required int hintsUsed,
    required int timeLeft,
    required int stars,
    required bool isDaily,
    int? levelIndex,
    String? mountainId,
  }) async {}

  @override
  Future<void> logHintUsed({
    required int tier,
    required int cost,
    required bool free,
    int? levelIndex,
  }) async {}

  @override
  Future<void> logAnswerRevealed({required int tier, required int cost}) async {}

  @override
  Future<void> logIapPurchase({
    required String productId,
    required double value,
    required String currency,
  }) async {}
}

/// Provider — no-op par défaut, overridé au boot (`main.dart`) par
/// [FirebaseAnalyticsService] une fois Firebase initialisé. Le no-op par
/// défaut garantit que les tests et le rendu hors-app ne touchent jamais le
/// plugin.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return const NoopAnalyticsService();
});
