import 'dart:async';

import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Wrap léger autour de [FirebaseRemoteConfig] qui expose un
/// [GameEconomyConfig] cohérent à toute l'app.
///
/// Lifecycle :
/// 1. [init] est appelé une fois au boot (après `Firebase.initializeApp`
///    et `activateAppCheck`). Il dépose les defaults littéraux,
///    paramètre les `minimumFetchInterval`, et tente un
///    `fetchAndActivate()` non-bloquant.
/// 2. [current] retourne le snapshot le plus récent — fallback sur
///    [GameEconomyConfig.defaults] si Firebase n'a jamais répondu (offline,
///    plugin indisponible, init failed).
/// 3. [refresh] permet de re-fetch à la demande (debug, écran admin futur,
///    A/B switch côté dev). Pas appelé en gameplay.
///
/// Aucune mise à jour réactive : les valeurs sont lues une fois au début
/// de chaque partie via le provider — changer la config en cours de partie
/// pourrait casser des invariants (ex: indice à 20 cliqué, RC change à
/// 30, le joueur a "payé" un prix qui n'existe plus). Pour appliquer une
/// nouvelle config, il faut relancer un niveau / une session.
class RemoteConfigService {
  RemoteConfigService();

  final Logger _log = Logger();
  GameEconomyConfig _current = GameEconomyConfig.defaults;
  bool _initialized = false;

  /// Snapshot courant. Lecture synchrone, jamais null.
  GameEconomyConfig get current => _current;

  /// Vrai une fois que [init] a été appelé (même si le fetch a échoué :
  /// les defaults sont toujours actifs).
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final rc = FirebaseRemoteConfig.instance;

      // Setup intervalles : en debug, fetch immédiat à chaque init pour
      // permettre l'itération rapide ; en release, 1h pour respecter les
      // quotas Firebase (5 fetch/h par device par défaut).
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 1),
        ),
      );

      // Defaults baked-in : le 1er run offline tape ces valeurs.
      await rc.setDefaults(_defaultsMap(GameEconomyConfig.defaults));

      // Fetch + activate avec timeout : on n'attend pas le réseau plus que
      // nécessaire pour ne pas allonger le boot. Le fail-soft garde les
      // defaults actifs.
      try {
        final activated = await rc.fetchAndActivate().timeout(
              const Duration(seconds: 8),
            );
        _current = _parse(rc);
        _log.i(
          'RemoteConfig fetched (activated=$activated): hint=${_current.hintCost} '
          'reward=${_current.winRewardBase} rewarded=${_current.rewardedVideoBonus} '
          'killswitch=${_current.adsKillswitch}',
        );
      } on TimeoutException {
        // Pas grave : defaults restent actifs, on retentera au prochain boot.
        _current = _parse(rc);
        _log.w('RemoteConfig fetch timed out — using cached/default values');
      }
    } on Object catch (e, st) {
      _log.w('RemoteConfig init failed — falling back to defaults: $e\n$st');
      _current = GameEconomyConfig.defaults;
    } finally {
      _initialized = true;
    }
  }

  /// Force un re-fetch (à la demande). No-op si pas initialisé.
  Future<void> refresh() async {
    if (!_initialized) return;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate().timeout(const Duration(seconds: 8));
      _current = _parse(rc);
      _log.i('RemoteConfig manually refreshed');
    } on Object catch (e) {
      _log.w('RemoteConfig refresh failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Lit les valeurs depuis le plugin et reconstruit un [GameEconomyConfig].
  /// Toute valeur invalide tombe en fallback sur le default — anti-shoot in foot.
  GameEconomyConfig _parse(FirebaseRemoteConfig rc) {
    const d = GameEconomyConfig.defaults;
    return GameEconomyConfig(
      hintCost: _safePositiveInt(
        rc.getInt(RemoteConfigKeys.hintCost),
        d.hintCost,
      ),
      hintCostMultiplier: _safePositiveDouble(
        rc.getDouble(RemoteConfigKeys.hintCostMultiplier),
        d.hintCostMultiplier,
      ),
      revealCostBase: _safePositiveInt(
        rc.getInt(RemoteConfigKeys.revealCostBase),
        d.revealCostBase,
      ),
      sinkTierScalingEnabled: rc.getBool(RemoteConfigKeys.sinkTierScaling),
      winRewardBase: _safeNonNegativeInt(
        rc.getInt(RemoteConfigKeys.winRewardBase),
        d.winRewardBase,
      ),
      speedBonusPerSecond: _safeNonNegativeInt(
        rc.getInt(RemoteConfigKeys.speedBonusPerSecond),
        d.speedBonusPerSecond,
      ),
      rewardedVideoBonus: _safePositiveInt(
        rc.getInt(RemoteConfigKeys.rewardedVideoBonus),
        d.rewardedVideoBonus,
      ),
      rewardedDoubleEnabled: rc.getBool(RemoteConfigKeys.rewardedDoubleEnabled),
      rewardedDailyCap: _safePositiveInt(
        rc.getInt(RemoteConfigKeys.rewardedDailyCap),
        d.rewardedDailyCap,
      ),
      initialCauris: _safeNonNegativeInt(
        rc.getInt(RemoteConfigKeys.initialCauris),
        d.initialCauris,
      ),
      streakRewards: _parseCsvInts(
        rc.getString(RemoteConfigKeys.streakRewards),
        d.streakRewards,
      ),
      interstitialEveryNLevels: _safePositiveInt(
        rc.getInt(RemoteConfigKeys.interstitialEveryNLevels),
        d.interstitialEveryNLevels,
      ),
      interstitialMinIntervalSeconds: _safeNonNegativeInt(
        rc.getInt(RemoteConfigKeys.interstitialMinIntervalSeconds),
        d.interstitialMinIntervalSeconds,
      ),
      adsKillswitch: rc.getBool(RemoteConfigKeys.adsKillswitch),
    );
  }

  /// Map sérialisable accepté par `setDefaults` (clés littérales →
  /// valeurs primitives JSON-safe).
  Map<String, dynamic> _defaultsMap(GameEconomyConfig d) => {
        RemoteConfigKeys.hintCost: d.hintCost,
        RemoteConfigKeys.hintCostMultiplier: d.hintCostMultiplier,
        RemoteConfigKeys.revealCostBase: d.revealCostBase,
        RemoteConfigKeys.sinkTierScaling: d.sinkTierScalingEnabled,
        RemoteConfigKeys.winRewardBase: d.winRewardBase,
        RemoteConfigKeys.speedBonusPerSecond: d.speedBonusPerSecond,
        RemoteConfigKeys.rewardedVideoBonus: d.rewardedVideoBonus,
        RemoteConfigKeys.rewardedDoubleEnabled: d.rewardedDoubleEnabled,
        RemoteConfigKeys.rewardedDailyCap: d.rewardedDailyCap,
        RemoteConfigKeys.initialCauris: d.initialCauris,
        RemoteConfigKeys.streakRewards: d.streakRewards.join(','),
        RemoteConfigKeys.interstitialEveryNLevels: d.interstitialEveryNLevels,
        RemoteConfigKeys.interstitialMinIntervalSeconds:
            d.interstitialMinIntervalSeconds,
        RemoteConfigKeys.adsKillswitch: d.adsKillswitch,
      };

  static int _safePositiveInt(int value, int fallback) =>
      value > 0 ? value : fallback;

  static int _safeNonNegativeInt(int value, int fallback) =>
      value >= 0 ? value : fallback;

  static double _safePositiveDouble(double value, double fallback) =>
      value > 0 ? value : fallback;

  static List<int> _parseCsvInts(String csv, List<int> fallback) {
    if (csv.trim().isEmpty) return fallback;
    final parts = csv.split(',');
    final result = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null || n < 0) return fallback; // entrée corrompue → fallback
      result.add(n);
    }
    return result.isEmpty ? fallback : result;
  }
}

/// Singleton Riverpod — lecture synchrone du snapshot courant.
final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  return RemoteConfigService();
});

/// Snapshot lu par les controllers et widgets. Lecture synchrone, jamais
/// null grâce au fallback baked-in. Pour A/B testing future-proof, ne PAS
/// watcher ce provider en gameplay (cf. doc du service) — préférer
/// `ref.read(...)` au début d'une session.
final gameEconomyConfigProvider = Provider<GameEconomyConfig>((ref) {
  return ref.watch(remoteConfigServiceProvider).current;
});
