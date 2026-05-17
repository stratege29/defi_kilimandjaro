import 'dart:async';
import 'dart:io' show Platform;

import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
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
  AdsService(this._progress);

  final PlayerProgressNotifier _progress;
  final Logger _log = Logger();

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;

  // Forcé à `false` en v0.1 : `init()` est un no-op (cf. plus bas).
  // À transformer en `bool _initialized = false;` mutable quand AdMob
  // sera ré-activé en v0.2.
  final bool _initialized = false;
  bool get initialized => _initialized;

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
  // TODO(admob): créer les unités Android et remplacer les test IDs
  // ci-dessous par les vrais IDs prod Android.

  static String get _rewardedUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testRewardedIOS : _testRewardedAndroid;
    }
    if (Platform.isIOS) return _prodRewardedIOS;
    return _testRewardedAndroid; // TODO(admob): prod Android.
  }

  static String get _interstitialUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testInterstitialIOS : _testInterstitialAndroid;
    }
    if (Platform.isIOS) return _prodInterstitialIOS;
    return _testInterstitialAndroid; // TODO(admob): prod Android.
  }

  /// **DÉSACTIVÉ en v0.1** — voir `lib/main.dart` (commentaire AdMob/UMP).
  /// `_initialized` reste à `false` → `showRewardedForCauris` et
  /// `maybeShowInterstitial` retournent immédiatement sans charger ni
  /// afficher la moindre pub. Ré-activera en v0.2.
  Future<void> init() async {
    _log.i('AdMob init skipped (disabled in v0.1)');
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

  /// Montre une rewarded video. Crédite [caurisReward] sur succès.
  /// Retourne `true` si l'utilisateur a regardé jusqu'au bout.
  Future<bool> showRewardedForCauris({int caurisReward = 50}) async {
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
        await _progress.addCauris(caurisReward);
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
