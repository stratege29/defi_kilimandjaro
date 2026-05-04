import 'dart:async';
import 'dart:io' show Platform;

import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logger/logger.dart';

/// Wrap léger autour de google_mobile_ads.
///
/// **Mode TEST par défaut** — utilise les unit IDs publics de Google.
/// Remplace par les vrais IDs AdMob une fois le compte configuré.
class AdsService {
  AdsService(this._progress);

  final PlayerProgressNotifier _progress;
  final Logger _log = Logger();

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Test ad units publics Google (toujours fonctionnels en debug).
  static String get _rewardedUnitId {
    if (Platform.isIOS) return 'ca-app-pub-3940256099942544/1712485313';
    return 'ca-app-pub-3940256099942544/5224354917';
  }

  static String get _interstitialUnitId {
    if (Platform.isIOS) return 'ca-app-pub-3940256099942544/4411468910';
    return 'ca-app-pub-3940256099942544/1033173712';
  }

  Future<void> init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    _log.i('AdMob initialized (test units)');
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

  /// Montre une rewarded video. Crédite [coinsReward] sur succès.
  /// Retourne `true` si l'utilisateur a regardé jusqu'au bout.
  Future<bool> showRewardedForCoins({int coinsReward = 50}) async {
    if (!_initialized) return false;
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
        await _progress.addCoins(coinsReward);
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

  /// Affiche une interstitielle si disponible. Best-effort, no-op sinon.
  Future<void> maybeShowInterstitial() async {
    if (!_initialized) return;
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
  final svc = AdsService(ref.watch(playerProgressProvider.notifier));
  ref.onDispose(svc.dispose);
  return svc;
});
