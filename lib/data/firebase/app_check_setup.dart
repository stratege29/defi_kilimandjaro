import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Activates Firebase App Check with the right provider per platform/build.
///
/// - Android (release) → Play Integrity
/// - iOS (release)     → DeviceCheck (App Attest sur iOS 14+ via SDK auto-fallback)
/// - Debug/profile     → Debug provider (le token apparaît dans la console
///   logcat / Xcode et doit être ajouté en debug-token dans Firebase Console).
///
/// La console Firebase doit avoir Play Integrity & DeviceCheck enregistrés
/// pour le bundle `com.ultimesgriots.kilimandjaro` avant le premier appel
/// authentifié. Sans cela, Cloud Functions / Firestore / RTDB rejettent les
/// requêtes en mode "enforced".
Future<void> activateAppCheck() async {
  // iOS/macOS : le provider App Check est configuré NATIVEMENT dans
  // AppDelegate.swift — `AppCheckDebugProviderFactory` + `FIRAAppCheckDebugToken`
  // (setenv AVANT `FirebaseApp.configure()`) en `#if DEBUG`, et
  // `DeviceCheckProviderFactory` en release. On NE rappelle donc PAS
  // `activate()` côté Dart sur iOS : le plugin réécrirait le provider factory
  // natif et, sur SIMULATEUR, retombe sur DeviceCheck (« DeviceCheckProvider is
  // not supported on current platform ») → aucun jeton App Check valide → les
  // callables `enforceAppCheck` rejettent tout (unauthenticated).
  //
  // Android n'a pas d'équivalent natif ici : la sélection du provider passe
  // par `activate()` côté Dart.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  }
  // Token auto-refresh: laisser activé en prod. Désactiver localement si tu
  // veux un token fixe par run de debug.
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  // On vérifie systématiquement (debug ET release) que l'activation a bien
  // produit un token exploitable. `getTokenResult` (>=0.4.6) renvoie le JWT
  // + son expiration ; en debug on l'imprime pour `flutter run`. Un échec ici
  // (attestation Play Integrity/DeviceCheck qui ne renvoie pas de token
  // exploitable) est la cause typique d'un rejet silencieux des callables
  // duel enforceAppCheck (cf. lobby qui tourne sans jamais créer de match) —
  // on le remonte donc en non-fatal Crashlytics pour l'avoir en prod sans
  // dépendre d'un accès `adb logcat`.
  try {
    final result = await FirebaseAppCheck.instance.getTokenResult();
    if (result == null) {
      // Pas d'exception mais pas de token non plus : l'attestation native a
      // échoué silencieusement (cas observé sur Play Integrity). À signaler
      // comme l'échec ci-dessous, pas comme un succès.
      throw StateError('getTokenResult returned null (no token available)');
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '🛡️ App Check activated — token len=${result.token.length}, '
        'expires=${result.expirationTime} '
        '(JWT, allow-list the debug UUID printed by native plugin in '
        'Firebase Console > App Check > Apps > ⋮ > Manage debug tokens)',
      );
    }
  } on Object catch (e, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('🛡️ App Check getTokenResult failed: $e');
    }
    try {
      await FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'AppCheckSetup.getTokenResult failed '
            '(platform=$defaultTargetPlatform)',
      );
    } on Object {
      // Crashlytics pas encore disponible/configuré — ne pas bloquer le
      // boot pour un problème de télémétrie.
    }
  }
}
