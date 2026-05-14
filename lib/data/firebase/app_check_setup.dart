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
  // firebase_app_check 0.4.x has both the deprecated `appleProvider`
  // (defaulting to `AppleProvider.deviceCheck`) and the new `providerApple`
  // (defaulting to `AppleDeviceCheckProvider()`). Both get forwarded to the
  // native delegate, and DeviceCheck takes precedence on simulator/older
  // devices unless we explicitly opt-into debug on the legacy param too.
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode
        ? AppleProvider.debug
        : AppleProvider.deviceCheck,
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

  // En debug, on imprime le token via Dart pour qu'il apparaisse dans
  // `flutter run`. La valeur retournée est le token JWT signé (long).
  // Le debug-token UUID à allow-lister en Firebase Console est imprimé
  // séparément par le plugin natif côté iOS/Android (cf. console Xcode /
  // logcat), MAIS sur le simulator iOS récent il est silencieux — on peut
  // forcer l'extraction de l'UUID en passant par les UserDefaults iOS
  // (clé `FIRAAppCheckDebugToken`). Pour l'instant on log juste la
  // confirmation que la procédure d'activation s'est bien terminée et que
  // le plugin a généré un token utilisable.
  if (kDebugMode) {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      // ignore: avoid_print
      print(
        '🛡️ App Check activated — token len=${token?.length ?? 0} '
        '(JWT, allow-list the debug UUID printed by native plugin in '
        'Firebase Console > App Check > Apps > ⋮ > Manage debug tokens)',
      );
    } catch (e) {
      // ignore: avoid_print
      print('🛡️ App Check getToken failed: $e');
    }
  }
}
