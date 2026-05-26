import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Coordonne la demande d'autorisation **App Tracking Transparency**
/// (iOS 14.5+) pour AdMob.
///
/// **Pourquoi pas au boot** : le prompt système ATT est l'un des plus
/// rejetés sur l'App Store (~30-50 % d'opt-in à froid contre 50-70 %
/// quand demandé après engagement). On attend que l'utilisateur ait
/// vraiment essayé le jeu (2 victoires) pour maximiser le taux d'opt-in.
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

  /// True dès que [maybePromptAfterEngagement] a été appelé une fois
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
  /// À appeler après un moment d'engagement (ex: 2e victoire — cf.
  /// `_advanceAfterVictory`). Idempotent et fail-soft.
  Future<void> maybePromptAfterEngagement() async {
    if (!Platform.isIOS) return;
    if (!_initialized) await init();
    if (hasPromptedOnce) return;
    if (_status != TrackingStatus.notDetermined) return;

    try {
      _status = await AppTrackingTransparency.requestTrackingAuthorization();
      _log.i('ATT prompt result: $_status');
      await _prefs.setBool(_kPromptDoneKey, true);
    } on Object catch (e) {
      _log.w('ATT request failed: $e');
    }
  }
}

final attServiceProvider = Provider<AttService>((ref) {
  return AttService(ref.watch(sharedPreferencesProvider));
});
