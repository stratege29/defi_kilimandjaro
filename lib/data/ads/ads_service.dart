import 'dart:async';
import 'dart:io' show Platform;

import 'package:defi_kilimandjaro/data/ads/rewarded_daily_cap_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logger/logger.dart';

/// Wrap léger autour de google_mobile_ads.
///
/// **Sélection des unit IDs** :
/// - Debug (toutes plateformes) → test units publics Google. Évite de
///   générer de fausses impressions sur le compte AdMob réel pendant le
///   dev / hot reload.
/// - Release iOS → vrais unit IDs de production (`ca-app-pub-38726827...`).
/// - Release Android → encore en test IDs (TODO : créer les unités
///   AdMob Android et remplacer ci-dessous).
///
/// Le `GADApplicationIdentifier` global est dans `ios/Runner/Info.plist`
/// (toujours le vrai App ID prod — la SDK l'utilise pour s'identifier au
/// compte AdMob, indépendamment des unit IDs).
class AdsService {
  AdsService(this._progress, this._remoteConfig, this._dailyCap);

  final PlayerProgressNotifier _progress;
  final RemoteConfigService _remoteConfig;
  final RewardedDailyCapService _dailyCap;
  final Logger _log = Logger();

  /// Snapshot Remote Config lu à chaque check (le killswitch peut changer
  /// au cours d'une session pour couper toutes les pubs en cas d'incident
  /// — pas besoin de reboot de l'app).
  GameEconomyConfig get _economy => _remoteConfig.current;

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;

  bool _initialized = false;
  bool get initialized => _initialized;

  // ---------------------------------------------------------------------
  // Interstitial pacing (Étape D)
  //
  // Stocké en mémoire (pas persisté) : un relaunch reset la cadence.
  // C'est OK car la règle est UX-nudge (préserver le tempo), pas un
  // hard cap anti-fraude.
  // ---------------------------------------------------------------------

  /// Compteur de victoires depuis la dernière interstitielle. Incrémenté
  /// par [noteVictory] depuis le call-site post-victoire, remis à zéro
  /// après affichage effectif d'une pub.
  int _victoriesSinceLastInterstitial = 0;

  /// Timestamp du dernier affichage d'interstitielle (UTC). Sert au cap
  /// minimum d'intervalle (`interstitialMinIntervalSeconds`).
  DateTime? _lastInterstitialShownAt;

  /// Flag global : si vrai, [maybeShowInterstitial] et
  /// [showRewardedForCauris] no-op. Géré par la couche duel (Phase 6) qui
  /// bascule à true à l'entrée du duel et false à la sortie — aucune pub
  /// pendant un match temps réel.
  bool suppressedInDuel = false;

  /// À appeler après chaque victoire qui passe par le flow normal
  /// (post-validation). Incrémente le compteur — l'interstitielle se
  /// déclenche au prochain `maybeShowInterstitial()` quand le seuil est
  /// atteint.
  void noteVictory() {
    _victoriesSinceLastInterstitial++;
  }

  /// Test unit IDs publics Google — utilisés en debug et sur Android tant
  /// que les unités prod Android ne sont pas créées.
  static const String _testRewardedIOS =
      'ca-app-pub-3940256099942544/1712485313';
  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testInterstitialIOS =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';

  /// Unit IDs de production (compte AdMob ultimesgriots).
  static const String _prodRewardedIOS =
      'ca-app-pub-3872682728320036/4739151934';
  static const String _prodInterstitialIOS =
      'ca-app-pub-3872682728320036/1482433200';

  /// Unit IDs Android — `null` tant que les unités ne sont pas créées
  /// dans la console AdMob. Quand prêtes :
  /// 1. Créer l'app Android dans AdMob console → obtenir le APP ID
  ///    `ca-app-pub-3872682728320036~<XXX>` et le coller dans
  ///    `android/app/src/main/AndroidManifest.xml`
  ///    (clé `com.google.android.gms.ads.APPLICATION_ID`).
  /// 2. Créer une unité Rewarded → coller son ID complet ici dans
  ///    `_prodRewardedAndroid`.
  /// 3. Créer une unité Interstitial → coller son ID dans
  ///    `_prodInterstitialAndroid`.
  /// 4. Le getter ci-dessous bascule automatiquement quand non-null.
  static const String? _prodRewardedAndroid = null;
  static const String? _prodInterstitialAndroid = null;

  static String get _rewardedUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testRewardedIOS : _testRewardedAndroid;
    }
    if (Platform.isIOS) return _prodRewardedIOS;
    return _prodRewardedAndroid ?? _testRewardedAndroid;
  }

  static String get _interstitialUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testInterstitialIOS : _testInterstitialAndroid;
    }
    if (Platform.isIOS) return _prodInterstitialIOS;
    return _prodInterstitialAndroid ?? _testInterstitialAndroid;
  }

  Future<void> init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    final mode = kDebugMode
        ? 'test units'
        : (Platform.isIOS ? 'prod units' : 'test units (Android pending)');
    _log.i('AdMob initialized ($mode)');
    unawaited(_loadRewarded());
    unawaited(_loadInterstitial());
  }

  // -------------------------- Rewarded video --------------------------------

  Future<void> _loadRewarded() async {
    await RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _log.i('Rewarded ad loaded');
        },
        onAdFailedToLoad: (err) {
          _rewarded = null;
          _log.w('Rewarded load failed: $err');
        },
      ),
    );
  }

  /// Montre une rewarded video. Crédite [caurisReward] sur succès (défaut :
  /// valeur Remote Config `eco_rewarded_video_bonus`). Retourne `true` si
  /// l'utilisateur a regardé jusqu'au bout.
  ///
  /// Skips :
  /// - Service non initialisé
  /// - Killswitch Remote Config (`ads_killswitch = true`)
  /// - Cap quotidien atteint (`eco_rewarded_daily_cap`)
  /// - Pas de pub chargée (déclenche un reload)
  Future<bool> showRewardedForCauris({int? caurisReward}) async {
    if (!_initialized) return false;
    if (suppressedInDuel) return false;
    if (_economy.adsKillswitch) {
      _log.i('Rewarded skipped — ads_killswitch active');
      return false;
    }
    if (!_dailyCap.canShow(_economy.rewardedDailyCap)) {
      _log.i(
        'Rewarded skipped — daily cap reached '
        '(${_dailyCap.countToday}/${_economy.rewardedDailyCap})',
      );
      return false;
    }
    final reward = caurisReward ?? _economy.rewardedVideoBonus;
    final ad = _rewarded;
    if (ad == null) {
      _log.w('Rewarded not ready, reloading');
      unawaited(_loadRewarded());
      return false;
    }

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _rewarded = null;
        unawaited(_loadRewarded());
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        a.dispose();
        _rewarded = null;
        _log.w('Rewarded show failed: $err');
        unawaited(_loadRewarded());
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await ad.show(
      onUserEarnedReward: (_, __) async {
        await _progress.addCauris(reward);
        // Compte la vue **uniquement** quand la récompense est crédité —
        // un dismiss prématuré ne consomme pas le cap (sinon farming par
        // skip).
        await _dailyCap.recordView();
        if (!completer.isCompleted) completer.complete(true);
      },
    );
    return completer.future;
  }

  // -------------------------- Interstitial ----------------------------------

  Future<void> _loadInterstitial() async {
    await InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _log.i('Interstitial ad loaded');
        },
        onAdFailedToLoad: (err) {
          _interstitial = null;
          _log.w('Interstitial load failed: $err');
        },
      ),
    );
  }

  /// Affiche une interstitielle si **toutes** les conditions sont réunies.
  ///
  /// Skips :
  /// - Service non initialisé
  /// - Joueur No-Ads
  /// - Killswitch Remote Config (`ads_killswitch`)
  /// - Suppression duel active (Phase 6)
  /// - Seuil victoires non atteint (`interstitialEveryNLevels`)
  /// - Min-interval pas écoulé depuis la dernière interstitielle
  /// - Aucune pub chargée (déclenche un reload silencieux)
  ///
  /// Reset le compteur victoires + met à jour le timestamp **uniquement**
  /// quand `ad.show()` est appelé — un skip ne consomme pas la cadence.
  Future<void> maybeShowInterstitial() async {
    if (!_initialized) return;
    if (suppressedInDuel) return;
    if (_progress.isNoAdsPurchased) return;
    if (_economy.adsKillswitch) {
      _log.i('Interstitial skipped — ads_killswitch active');
      return;
    }

    // Seuil victoires.
    if (_victoriesSinceLastInterstitial < _economy.interstitialEveryNLevels) {
      return;
    }

    // Min-interval.
    final last = _lastInterstitialShownAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last).inSeconds;
      if (elapsed < _economy.interstitialMinIntervalSeconds) {
        _log.i(
          'Interstitial skipped — min interval not elapsed '
          '(${elapsed}s / ${_economy.interstitialMinIntervalSeconds}s)',
        );
        return;
      }
    }

    final ad = _interstitial;
    if (ad == null) {
      unawaited(_loadInterstitial());
      return;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _interstitial = null;
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        a.dispose();
        _interstitial = null;
        _log.w('Interstitial show failed: $err');
        unawaited(_loadInterstitial());
      },
    );
    _victoriesSinceLastInterstitial = 0;
    _lastInterstitialShownAt = DateTime.now();
    await ad.show();
  }

  Future<void> dispose() async {
    await _rewarded?.dispose();
    await _interstitial?.dispose();
  }

  /// Helper pour log debug uniquement.
  void debug(String msg) {
    if (kDebugMode) _log.d(msg);
  }
}

final adsServiceProvider = Provider<AdsService>((ref) {
  final svc = AdsService(
    ref.watch(playerProgressProvider.notifier),
    ref.watch(remoteConfigServiceProvider),
    ref.watch(rewardedDailyCapServiceProvider.notifier),
  );
  ref.onDispose(svc.dispose);
  return svc;
});
