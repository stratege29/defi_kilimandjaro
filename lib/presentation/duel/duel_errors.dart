import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

/// Traduit une erreur d'appel Cloud Function (duel) en message joueur clair.
///
/// Les vues duel ne doivent JAMAIS afficher `$error` brut : le `.toString()`
/// d'une [FirebaseFunctionsException] produit du texte technique
/// (ex. `[firebase_functions/unknown] A data connection is not currently
/// allowed.`) incompréhensible pour le joueur.
///
/// Le cas le plus fréquent en prod est purement côté appareil : iOS renvoie
/// `NSURLErrorDataNotAllowed` (data cellulaire coupée pour l'app, Low Data
/// Mode, mode avion, perte réseau) — remonté sous le code générique `unknown`.
String friendlyDuelError(Object? error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'unauthenticated':
        return "Connexion au serveur refusée. Redémarre l'app et réessaie.";
      case 'not-found':
        return 'Ce défi est introuvable ou a expiré.';
      case 'failed-precondition':
        final msg = error.message ?? '';
        if (msg.contains('full')) return 'Ce défi est déjà complet.';
        if (msg.contains('expired')) return 'Ce défi a expiré.';
        return 'Impossible de rejoindre ce défi.';
      case 'permission-denied':
        return 'Code invalide.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'Connexion trop lente. Vérifie ta connexion et réessaie.';
      case 'unknown':
        final detail = error.message ?? '';
        if (detail.contains('data connection') ||
            detail.contains('not allowed') ||
            detail.contains('network') ||
            detail.contains('offline')) {
          return 'Pas de connexion internet. Vérifie ta connexion et réessaie.';
        }
        return 'Erreur réseau. Vérifie ta connexion et réessaie.';
      default:
        return 'Erreur serveur (${error.code}). Réessaie dans un instant.';
    }
  }
  if (error is TimeoutException) {
    return 'Connexion trop lente. Vérifie ta connexion et réessaie.';
  }
  if (error is SocketException) {
    return 'Pas de connexion internet. Vérifie ta connexion et réessaie.';
  }
  // StateError (réponse serveur invalide) et autres : message générique.
  return "Erreur inattendue. Réessaie ou redémarre l'app.";
}
