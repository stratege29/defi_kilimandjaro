import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kilimandjaro_admin/src/auth/auth_providers.dart';

/// Gate l'accès à la console derrière une connexion Google + un check de
/// custom claim (`admin` requis pour gérer les packs ; `moderator` accepté
/// uniquement pour la file UGC).
///
/// L'attribution des claims est faite out-of-band via Firebase Admin SDK
/// (cf. `tools/admin_console/README.md`). Cette gate ne fait QUE vérifier.
class AuthGate extends ConsumerWidget {
  /// Si `requireAdmin` est `true`, seuls les comptes avec `role == 'admin'`
  /// peuvent entrer. Sinon, `role == 'moderator'` est accepté.
  const AuthGate({required this.child, super.key, this.requireAdmin = true});

  /// Si `true`, seuls les comptes avec `role == 'admin'` peuvent entrer.
  /// Si `false`, `role == 'moderator'` est accepté (utilisé pour la file).
  final bool requireAdmin;

  /// Sub-tree rendu une fois l'utilisateur authentifié et autorisé.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      loading: () => const _Loading(),
      error: (e, _) => _ErrorScreen(message: 'Erreur auth : $e'),
      data: (user) {
        if (user == null) return const _SignInScreen();
        final claims = ref.watch(adminClaimsProvider);
        return claims.when(
          loading: () => const _Loading(),
          error: (e, _) => _ErrorScreen(message: 'Erreur claims : $e'),
          data: (c) {
            final allowed = requireAdmin ? c.isAdmin : c.isModerator;
            if (!allowed) return _AccessDeniedScreen(claims: c);
            return child;
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen();

  Future<void> _signIn() async {
    // Web : signInWithRedirect plutôt que popup. Safari/iOS bloquent les
    // popups cross-origin sans throw catchable. Le redirect navigue vers
    // Google, l'utilisateur autorise, retour automatique — la session est
    // restaurée via authStateChanges() au reload.
    final provider = GoogleAuthProvider()..addScope('email');
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithRedirect(provider);
      return;
    }
    final googleUser = await GoogleSignIn().signIn();
    final googleAuth = await googleUser?.authentication;
    if (googleAuth == null) return;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Kilimandjaro Admin',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('Console de gestion du contenu'),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _signIn,
              icon: const Icon(Icons.login),
              label: const Text('Se connecter avec Google'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen({required this.claims});
  final AdminClaims claims;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accès refusé',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Compte connecté : ${claims.email ?? claims.uid ?? "?"}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Rôle actuel : ${claims.role ?? "(aucun)"}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Le rôle "admin" est requis pour gérer les packs et les '
                  'questions. Il est attribué via Firebase Admin SDK '
                  '(custom claim `role: admin`). Voir le README.',
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
