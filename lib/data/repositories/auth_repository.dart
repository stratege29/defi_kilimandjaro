import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Fournisseur d'identité courant du joueur.
enum AccountProvider { anonymous, google, apple }

/// Résultat d'une tentative de liaison de compte.
enum LinkOutcome {
  /// Le credential a été lié à l'uid anonyme existant — toute la progression
  /// serveur (ELO, wallet, duels) est conservée.
  linked,

  /// Le credential appartenait déjà à un compte permanent : on s'y est
  /// reconnecté. **L'uid a changé** → la progression locale de cet appareil
  /// (SharedPreferences) n'est pas fusionnée automatiquement.
  switchedToExisting,

  /// L'utilisateur a annulé la fenêtre système de connexion.
  cancelled,
}

/// Erreur typée des flux d'authentification (hors annulation utilisateur).
class AuthException implements Exception {
  AuthException({required this.code, required this.message});

  factory AuthException.fromFirebase(FirebaseAuthException e) =>
      AuthException(code: e.code, message: e.message ?? 'Erreur inconnue');

  final String code;
  final String message;

  @override
  String toString() => 'AuthException($code): $message';
}

/// Couche data pour l'authentification optionnelle (anonyme-first).
///
/// L'app signe l'utilisateur en anonyme au boot (`main.dart`). Ce repository
/// permet de **lier** un compte Google/Apple à cet uid anonyme via
/// `linkWithCredential` — l'uid est préservé, donc le profil ELO, le wallet
/// serveur et l'historique de duels survivent à la liaison.
///
/// Aucun mur de connexion : toutes les fonctionnalités marchent en anonyme.
class AuthRepository {
  AuthRepository({
    required FirebaseAuth auth,
    GoogleSignIn? googleSignIn,
    FirebaseFunctions? functions,
  })  : _auth = auth,
        _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']),
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFunctions _functions;
  final Logger _log = Logger();

  /// Uid courant (anonyme ou permanent), ou `null` durant la fenêtre de
  /// re-connexion anonyme.
  String? get currentUid => _auth.currentUser?.uid;

  /// `true` si la session courante est anonyme (non liée à un fournisseur).
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  /// Email du compte permanent lié, si disponible.
  String? get email => _auth.currentUser?.email;

  /// Stream des changements d'état d'auth (liaison, déconnexion, suppression).
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Fournisseur d'identité inféré depuis `providerData`.
  AccountProvider get currentProvider {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return AccountProvider.anonymous;
    for (final info in user.providerData) {
      if (info.providerId == 'google.com') return AccountProvider.google;
      if (info.providerId == 'apple.com') return AccountProvider.apple;
    }
    return AccountProvider.anonymous;
  }

  // ---- Liaison Google -----------------------------------------------------

  Future<LinkOutcome> linkWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return LinkOutcome.cancelled;

    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    return _linkOrSwitch(credential);
  }

  // ---- Liaison Apple ------------------------------------------------------

  Future<LinkOutcome> linkWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID appleCred;
    try {
      appleCred = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return LinkOutcome.cancelled;
      }
      throw AuthException(code: e.code.name, message: e.message);
    }

    final credential = OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCred.authorizationCode,
    );
    return _linkOrSwitch(credential);
  }

  /// Lie [credential] à l'uid anonyme courant. En cas de collision (le
  /// credential appartient déjà à un compte permanent), se reconnecte au
  /// compte existant et signale [LinkOutcome.switchedToExisting].
  Future<LinkOutcome> _linkOrSwitch(AuthCredential credential) async {
    final user = _auth.currentUser;
    try {
      if (user == null) {
        await _auth.signInWithCredential(credential);
        return LinkOutcome.switchedToExisting;
      }
      await user.linkWithCredential(credential);
      _log.i('account linked → uid=${user.uid}');
      return LinkOutcome.linked;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        return LinkOutcome.linked;
      }
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        // Le credential pointe sur un compte permanent déjà existant.
        await _auth.signInWithCredential(e.credential ?? credential);
        _log.w('credential already in use → switched to existing account');
        return LinkOutcome.switchedToExisting;
      }
      _log.e('linkWithCredential error', error: e);
      throw AuthException.fromFirebase(e);
    }
  }

  // ---- Déconnexion --------------------------------------------------------

  /// Déconnecte le compte permanent puis re-signe en anonyme pour garder
  /// l'app fonctionnelle (toutes les couches dépendent d'un uid non nul).
  ///
  /// Note : l'uid anonyme regénéré est différent de l'ancien — la progression
  /// serveur du compte lié reste accessible en se reconnectant au même
  /// fournisseur.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on Object catch (e) {
      _log.w('google signOut failed (ignoré): $e');
    }
    await _auth.signOut();
    await _auth.signInAnonymously();
    _log.i('signed out → re-anon uid=${_auth.currentUser?.uid}');
  }

  // ---- Suppression de compte ---------------------------------------------

  /// Supprime définitivement le compte côté serveur (profil, wallet, audit,
  /// matchs, utilisateur Auth) via la Cloud Function `deleteAccount`, puis
  /// re-signe en anonyme avec un nouvel uid vierge.
  ///
  /// L'appelant est responsable d'effacer la progression locale
  /// (SharedPreferences) avant ou après cet appel.
  Future<void> deleteAccount() async {
    try {
      await _functions.httpsCallable('deleteAccount').call<dynamic>();
    } on FirebaseFunctionsException catch (e) {
      _log.e('deleteAccount CF error', error: e);
      throw AuthException(code: e.code, message: e.message ?? 'Erreur serveur');
    }
    try {
      await _googleSignIn.signOut();
    } on Object catch (_) {}
    await _auth.signOut();
    await _auth.signInAnonymously();
    _log.i('account deleted → fresh anon uid=${_auth.currentUser?.uid}');
  }

  /// Nonce cryptographique pour Sign in with Apple (anti-rejeu).
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}

// ===========================================================================
// Providers Riverpod
// ===========================================================================

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(auth: ref.watch(firebaseAuthProvider));
});

/// Stream de l'utilisateur Firebase courant (réémet à chaque liaison /
/// déconnexion / suppression).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// `true` si la session courante est anonyme (non liée).
final isAnonymousProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  return user?.isAnonymous ?? true;
});

/// Fournisseur d'identité courant (anonyme / google / apple).
final currentAccountProviderProvider = Provider<AccountProvider>((ref) {
  // Dépend du stream pour se recalculer après une liaison.
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentProvider;
});
