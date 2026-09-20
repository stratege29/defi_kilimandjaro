import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Résultat de la dernière tentative d'attestation App Check au démarrage.
///
/// Permet aux écrans qui dépendent des callables `enforceAppCheck` (duel,
/// tournoi) d'expliquer un refus serveur au lieu d'un message générique.
/// Classé à partir du message d'erreur du plugin `firebase_app_check`.
enum AppCheckFailure {
  /// Aucun échec observé (ou attestation pas encore tentée).
  none,

  /// Play Integrity injoignable : `Integrity API error (-9)` — le Play Store
  /// de l'appareil est trop ancien (ou absent) pour lier le service.
  /// Seule issue côté joueur : mettre à jour le Play Store.
  playStoreOutdated,

  /// Le backend App Check a rejeté l'attestation (HTTP 403).
  attestationRejected,

  /// Pas de réseau au moment de l'attestation (DNS / socket).
  offline,

  /// Toute autre erreur.
  unknown,
}

/// Classe une erreur levée par `FirebaseAppCheck.getTokenResult`.
AppCheckFailure classifyAppCheckError(Object error) {
  final message = error.toString();
  if (message.contains('Integrity API error (-9)') ||
      message.contains('CANNOT_BIND_TO_SERVICE')) {
    return AppCheckFailure.playStoreOutdated;
  }
  if (message.contains('code: 403') ||
      message.contains('App attestation failed')) {
    return AppCheckFailure.attestationRejected;
  }
  if (message.contains('Unable to resolve host') ||
      message.contains('SocketException') ||
      message.contains('No address associated with hostname')) {
    return AppCheckFailure.offline;
  }
  return AppCheckFailure.unknown;
}

/// Mémorise l'état de la dernière attestation.
///
/// Statique car renseigné dans `activateAppCheck()` avant `runApp` (donc
/// avant tout `ProviderScope`). Lu ensuite via [appCheckFailureProvider].
class AppCheckHealth {
  AppCheckHealth._();

  static AppCheckFailure lastFailure = AppCheckFailure.none;
}

/// Dernier échec App Check connu au moment de la lecture.
final appCheckFailureProvider =
    Provider<AppCheckFailure>((_) => AppCheckHealth.lastFailure);
