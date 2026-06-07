import 'package:equatable/equatable.dart';

/// Configuration économique du jeu — pilotée par Firebase Remote Config.
///
/// Toutes les valeurs sont des constantes côté code par défaut
/// (cf. [GameEconomyConfig.defaults]) et peuvent être overridées sans store
/// update via la console Firebase Remote Config. Les `RemoteConfigKeys` ci-bas
/// listent les noms littéraux à créer côté console.
///
/// Aucune dépendance Firebase ici : le `RemoteConfigService` instancie cette
/// classe à partir des valeurs résolues, l'UI et les controllers ne dépendent
/// que de cette entité (testabilité + couches respectées).
class GameEconomyConfig extends Equatable {
  const GameEconomyConfig({
    required this.hintCost,
    required this.hintCostMultiplier,
    required this.revealCostBase,
    required this.sinkTierScalingEnabled,
    required this.winRewardBase,
    required this.speedBonusPerSecond,
    required this.rewardedVideoBonus,
    required this.rewardedDoubleEnabled,
    required this.rewardedDailyCap,
    required this.initialCauris,
    required this.streakRewards,
    required this.interstitialEveryNLevels,
    required this.interstitialMinIntervalSeconds,
    required this.adsKillswitch,
  });

  /// Coût en cauris du **premier** indice utilisé dans un niveau.
  /// Les indices suivants sont scalés via [hintCostMultiplier].
  final int hintCost;

  /// Multiplicateur appliqué au coût des indices suivants dans le même
  /// niveau. Exemples avec base 25 et multiplier 1.5 :
  /// - 1er indice = 25
  /// - 2e indice = 38
  /// - 3e indice = 56
  final double hintCostMultiplier;

  /// Coût de base de la révélation de réponse à l'écran d'échec (zone T2+).
  /// Scalé par le multiplicateur de tier si [sinkTierScalingEnabled] est
  /// actif (cf. [revealCost]) — un reveal coûte alors ≈ une victoire propre
  /// au tier courant, préservant la tension en fin de progression.
  final int revealCostBase;

  /// Active le scaling des **sinks** (indices + révélation) par le
  /// multiplicateur de tier du niveau (1.0 → 2.5), aligné sur celui des
  /// gains. Empêche le late-game de devenir trivial : sinks plats + gains
  /// gonflés = monnaie décorative. Flag dédié pour A/B test + rollback
  /// instantané via Remote Config.
  final bool sinkTierScalingEnabled;

  /// Base de la récompense victoire (avant bonus vitesse + multiplier tier).
  final int winRewardBase;

  /// Cauris bonus par seconde restante au moment de la validation.
  /// Récompense finale = ([winRewardBase] + timeLeft × [speedBonusPerSecond])
  /// × multiplier tier (1.0 → 2.5).
  final int speedBonusPerSecond;

  /// Cauris crédités après une rewarded video terminée.
  final int rewardedVideoBonus;

  /// Active le bouton "Doubler la récompense" sur l'écran victoire.
  final bool rewardedDoubleEnabled;

  /// Plafond quotidien de rewarded videos par joueur (anti-farming +
  /// préservation de la conversion IAP).
  final int rewardedDailyCap;

  /// Solde initial offert à un nouveau joueur (utilisé par
  /// `PlayerProgress.initial(cauris:)`).
  final int initialCauris;

  /// Récompense en cauris pour chaque jour consécutif de connexion.
  /// Format Remote Config : chaîne CSV `"10,20,40,60,100,150,300"`.
  /// `streakRewards[0]` = J1, `streakRewards[6]` = J7 (cycle de 7 jours).
  /// Au-delà du jour 7, la dernière valeur est réutilisée.
  final List<int> streakRewards;

  /// Fréquence de déclenchement de l'interstitielle (toutes les N victoires).
  final int interstitialEveryNLevels;

  /// Intervalle minimum (secondes) entre deux interstitielles consécutives,
  /// quel que soit le compteur. Évite les pubs back-to-back.
  final int interstitialMinIntervalSeconds;

  /// Kill global : coupe rewarded + interstitielles sans store update.
  /// Le shop reste actif (la décision est isolée du flux ads payants).
  final bool adsKillswitch;

  /// Valeurs par défaut câblées en dur (fallback si Remote Config indisponible
  /// ou première installation offline).
  static const GameEconomyConfig defaults = GameEconomyConfig(
    hintCost: 25,
    hintCostMultiplier: 1.5,
    revealCostBase: 40,
    sinkTierScalingEnabled: true,
    winRewardBase: 20,
    speedBonusPerSecond: 1,
    rewardedVideoBonus: 50,
    rewardedDoubleEnabled: true,
    rewardedDailyCap: 5,
    initialCauris: 120,
    streakRewards: <int>[10, 20, 40, 60, 100, 150, 300],
    interstitialEveryNLevels: 3,
    interstitialMinIntervalSeconds: 60,
    adsKillswitch: false,
  );

  /// Coût du Nème indice dans un niveau (N indexé depuis 0).
  /// - N=0 → [hintCost]
  /// - N=1 → [hintCost] × [hintCostMultiplier]
  /// - N=2 → [hintCost] × [hintCostMultiplier]^2
  ///
  /// Si [sinkTierScalingEnabled] est actif, le coût est en plus multiplié
  /// par [tierMultiplier] (le `caurisMultiplier` du niveau, 1.0 → 2.5),
  /// pour que les indices restent une fraction sensible des gains au tier
  /// courant. Quand le flag est off, [tierMultiplier] est ignoré.
  int hintCostForIndex(int hintIndex, {double tierMultiplier = 1.0}) {
    var cost = hintCost.toDouble();
    for (var i = 0; i < hintIndex; i++) {
      cost *= hintCostMultiplier;
    }
    if (sinkTierScalingEnabled) {
      cost *= tierMultiplier;
    }
    return cost.round();
  }

  /// Coût de la révélation de réponse pour le tier courant. Vaut
  /// [revealCostBase] × [tierMultiplier] si [sinkTierScalingEnabled], sinon
  /// [revealCostBase] plat. Cible : ≈ une victoire propre au tier.
  int revealCost({double tierMultiplier = 1.0}) {
    final base = revealCostBase.toDouble();
    return (sinkTierScalingEnabled ? base * tierMultiplier : base).round();
  }

  /// Récompense streak pour un compteur donné (1-indexé : `streakDay = 1` →
  /// `streakRewards[0]`). Au-delà de la liste, retourne la dernière valeur
  /// (palier asymptotique).
  int streakRewardForDay(int streakDay) {
    if (streakDay <= 0) return 0;
    if (streakRewards.isEmpty) return 0;
    final idx = streakDay - 1;
    if (idx >= streakRewards.length) return streakRewards.last;
    return streakRewards[idx];
  }

  GameEconomyConfig copyWith({
    int? hintCost,
    double? hintCostMultiplier,
    int? revealCostBase,
    bool? sinkTierScalingEnabled,
    int? winRewardBase,
    int? speedBonusPerSecond,
    int? rewardedVideoBonus,
    bool? rewardedDoubleEnabled,
    int? rewardedDailyCap,
    int? initialCauris,
    List<int>? streakRewards,
    int? interstitialEveryNLevels,
    int? interstitialMinIntervalSeconds,
    bool? adsKillswitch,
  }) {
    return GameEconomyConfig(
      hintCost: hintCost ?? this.hintCost,
      hintCostMultiplier: hintCostMultiplier ?? this.hintCostMultiplier,
      revealCostBase: revealCostBase ?? this.revealCostBase,
      sinkTierScalingEnabled:
          sinkTierScalingEnabled ?? this.sinkTierScalingEnabled,
      winRewardBase: winRewardBase ?? this.winRewardBase,
      speedBonusPerSecond: speedBonusPerSecond ?? this.speedBonusPerSecond,
      rewardedVideoBonus: rewardedVideoBonus ?? this.rewardedVideoBonus,
      rewardedDoubleEnabled:
          rewardedDoubleEnabled ?? this.rewardedDoubleEnabled,
      rewardedDailyCap: rewardedDailyCap ?? this.rewardedDailyCap,
      initialCauris: initialCauris ?? this.initialCauris,
      streakRewards: streakRewards ?? this.streakRewards,
      interstitialEveryNLevels:
          interstitialEveryNLevels ?? this.interstitialEveryNLevels,
      interstitialMinIntervalSeconds:
          interstitialMinIntervalSeconds ?? this.interstitialMinIntervalSeconds,
      adsKillswitch: adsKillswitch ?? this.adsKillswitch,
    );
  }

  @override
  List<Object?> get props => [
        hintCost,
        hintCostMultiplier,
        revealCostBase,
        sinkTierScalingEnabled,
        winRewardBase,
        speedBonusPerSecond,
        rewardedVideoBonus,
        rewardedDoubleEnabled,
        rewardedDailyCap,
        initialCauris,
        streakRewards,
        interstitialEveryNLevels,
        interstitialMinIntervalSeconds,
        adsKillswitch,
      ];
}

/// Clés littérales Firebase Remote Config — source de vérité pour la
/// console et tests. Renommer une clé casse les overrides en prod, **ne
/// jamais le faire** sans coordonner avec l'admin console.
abstract class RemoteConfigKeys {
  RemoteConfigKeys._();

  static const String hintCost = 'eco_hint_cost';
  static const String hintCostMultiplier = 'eco_hint_cost_multiplier';
  static const String revealCostBase = 'eco_reveal_cost_base';
  static const String sinkTierScaling = 'eco_sink_tier_scaling';
  static const String winRewardBase = 'eco_win_reward_base';
  static const String speedBonusPerSecond = 'eco_speed_bonus_per_second';
  static const String rewardedVideoBonus = 'eco_rewarded_video_bonus';
  static const String rewardedDoubleEnabled = 'eco_rewarded_double_enabled';
  static const String rewardedDailyCap = 'eco_rewarded_daily_cap';
  static const String initialCauris = 'eco_initial_cauris';
  static const String streakRewards = 'eco_streak_rewards';
  static const String interstitialEveryNLevels =
      'ads_interstitial_every_n_levels';
  static const String interstitialMinIntervalSeconds =
      'ads_interstitial_min_interval_seconds';
  static const String adsKillswitch = 'ads_killswitch';
}
