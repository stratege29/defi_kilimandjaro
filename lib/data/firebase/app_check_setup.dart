import 'package:firebase_app_check/firebase_app_check.dart';
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
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleDeviceCheckProvider(),
  );
  // Token auto-refresh: laisser activé en prod. Désactiver localement si tu
  // veux un token fixe par run de debug.
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}
