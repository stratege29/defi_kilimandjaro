import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logger/logger.dart';

/// Wrap autour de Google User Messaging Platform (RGPD EU).
///
/// Demande l'info de consentement au boot ; si un formulaire est requis
/// (utilisateurs UE), le présente avant que les pubs personnalisées
/// soient demandées. Hors EU c'est un no-op fail-soft.
class ConsentService {
  ConsentService();

  final Logger _log = Logger();

  /// Appelé une fois au boot avant `AdsService.init()`.
  ///
  /// - Remplir `testIdentifiers` avec l'IDFA du device de test pour forcer
  ///   le formulaire en dev (cf. AdMob Console → UMP → Testing).
  Future<void> requestConsent({
    List<String> testIdentifiers = const <String>[],
  }) async {
    final params = ConsentRequestParameters(
      consentDebugSettings: kDebugMode
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: testIdentifiers,
            )
          : null,
    );

    try {
      await _request(params);
    } on Exception catch (e) {
      _log.w('UMP request failed: $e');
    }
  }

  Future<void> _request(ConsentRequestParameters params) async {
    final completer = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          // Charge et présente le formulaire si nécessaire (utilisateurs EU).
          await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null) {
              _log.w('UMP form error: ${formError.message}');
            }
            if (!completer.isCompleted) completer.complete();
          });
        } on Exception catch (e) {
          _log.w('UMP form exception: $e');
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error) {
        _log.w('UMP info update error: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  /// Renvoie true si on peut demander des pubs (ConsentStatus = obtained ou notRequired).
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } on Exception {
      return true; // fail-soft
    }
  }
}

final consentServiceProvider = Provider<ConsentService>((ref) {
  return ConsentService();
});
