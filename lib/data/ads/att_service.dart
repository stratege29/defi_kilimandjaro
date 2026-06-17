import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Coordonne la demande d'autorisation **App Tracking Transparency**
/// (iOS 14.5+) pour AdMob.
///
/// **Au démarrage, AVANT l'init AdMob** : Apple exige (Guideline 2.1) que
/// le prompt ATT apparaisse *avant* toute collecte de données traçables —
/// donc avant que le SDK Google Mobile Ads ne charge la moindre pub.
/// `ensureRequested()` est appelé dans `main.dart` juste avant
/// `AdsService.init()`. (Auparavant le prompt était repoussé à la 2e
/// victoire pour maximiser l'opt-in : rejet App Store car le reviewer ne
/// le voyait jamais ET des pubs se chargeaient avant.)
///
/// **Effet de l'opt-in** : eCPM rewarded et interstitial AdMob × ~2.
/// L'opt-out fait fonctionner les pubs en mode non-personnalisé, lower
/// fill rate mais légal. UMP gère déjà le consent RGPD côté EU,
/// ATT est complémentaire (Apple-spécifique).
///
/// **No-op Android** : ATT n'existe pas — le plugin gère gracefully.
///
/// **Idempotence** : le système renvoie le même statut une fois la
/// décision prise par l'utilisateur (pas de re-prompt). On stocke un
/// flag local `att_prompt_done` pour éviter d'invoquer `requestTracking`
/// plusieurs fois par session inutilement.
class AttService {
  AttService(this._prefs);

  static const String _kPromptDoneKey = 'att_prompt_done';

  final SharedPreferences _prefs;
  final Logger _log = Logger();

  bool _initialized = false;

  /// Statut courant (ou notDetermined sur Android / iOS < 14.5).
  TrackingStatus _status = TrackingStatus.notDetermined;
  TrackingStatus get status => _status;

  /// True dès que [ensureRequested] a été appelé une fois
  /// avec succès (peu importe la réponse user). Persiste cross-session.
  bool get hasPromptedOnce => _prefs.getBool(_kPromptDoneKey) ?? false;

  /// Initialise en lisant le statut courant — appelable plusieurs fois
  /// sans effet de bord. Ne déclenche **pas** de prompt système.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _status = await AppTrackingTransparency.trackingAuthorizationStatus;
      _log.i('ATT initial status: $_status (prompted=$hasPromptedOnce)');
    } on Object catch (e) {
      _log.w('ATT init failed (probablement Android, no-op): $e');
    } finally {
      _initialized = true;
    }
  }

  /// Demande l'autorisation ATT — seulement si :
  /// - Plateforme iOS
  /// - Statut courant `notDetermined` (jamais prompted)
  /// - Pas déjà tenté dans cette installation (`hasPromptedOnce` false)
  ///
  /// **À appeler au démarrage, avant `AdsService.init()`** (cf. `main.dart`)
  /// pour que le prompt précède tout chargement de pub. Idempotent et
  /// fail-soft. Doit être awaité afin que l'init AdMob attende la réponse.
  Future<void> ensureRequested() async {
    if (!Platform.isIOS) return;
    if (!_initialized) await init();
    if (hasPromptedOnce) return;
    if (_status != TrackingStatus.notDetermined) return;

    try {
      // iOS ne présente le dialog ATT que si l'app est ACTIVE. Au cold
      // start, le premier post-frame peut survenir avant l'état `resumed`
      // → `requestTrackingAuthorization` renvoie alors `notDetermined`
      // SANS jamais afficher le dialog. On attend donc l'état resumed puis
      // un court délai de stabilisation avant de demander.
      await _waitUntilResumed();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      _status = await AppTrackingTransparency.requestTrackingAuthorization();
      _log.i('ATT prompt result: $_status');

      // Ne marquer « prompted » QUE si l'utilisateur a réellement répondu.
      // Si on est toujours `notDetermined` (dialog non affiché), on laisse
      // le flag à false pour re-tenter au prochain lancement.
      if (_status != TrackingStatus.notDetermined) {
        await _prefs.setBool(_kPromptDoneKey, true);
      } else {
        _log.w('ATT stayed notDetermined (dialog not shown) — will retry');
      }
    } on Object catch (e) {
      _log.w('ATT request failed: $e');
    }
  }

  /// Attend (borné) que l'app atteigne `AppLifecycleState.resumed` — requis
  /// pour qu'iOS affiche le dialog ATT. Retourne immédiatement si déjà
  /// resumed, sinon écoute les transitions de cycle de vie (timeout 5 s).
  Future<void> _waitUntilResumed() async {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState == AppLifecycleState.resumed) return;

    final completer = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed && !completer.isCompleted) {
          completer.complete();
        }
      },
    );
    try {
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } finally {
      listener.dispose();
    }
  }
}

final attServiceProvider = Provider<AttService>((ref) {
  return AttService(ref.watch(sharedPreferencesProvider));
});
