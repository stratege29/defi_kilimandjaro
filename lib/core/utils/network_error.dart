import 'package:cloud_functions/cloud_functions.dart';

/// True si l'erreur vient d'une absence de connexion exploitable côté
/// appareil (données cellulaires désactivées pour l'app, Mode Données
/// Faibles, wifi captif sans vraie connexion...) plutôt que d'un problème
/// serveur. Ces erreurs ne sortent jamais du téléphone — reconnaissable au
/// code `unknown`/`unavailable`/`deadline-exceeded` de `cloud_functions` ou
/// au message d'erreur système typique (ex. iOS "A data connection is not
/// currently allowed.").
bool isDeviceNetworkError(Object error) {
  final code = error is FirebaseFunctionsException ? error.code : null;
  if (code == 'unavailable' || code == 'deadline-exceeded') return true;

  final message = error.toString().toLowerCase();
  const keywords = [
    'data connection',
    'internet connection',
    'network connection',
    'offline',
    'timed out',
    'could not connect',
    'network error',
    'socketexception',
  ];
  return keywords.any(message.contains);
}

/// Message utilisateur pour une erreur de connexion appareil.
const String kNetworkErrorMessage =
    'Pas de connexion internet. Vérifie ton wifi ou tes données mobiles, '
    'puis réessaie.';
