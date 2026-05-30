import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Écran de sign-in (public, monté quand le user n'est pas authentifié).
///
/// Sur Web, on utilise `FirebaseAuth.signInWithPopup(GoogleAuthProvider())`
/// nativement — pas besoin du plugin `google_sign_in` ni de meta tag
/// `google-signin-client_id` dans index.html. C'est l'API recommandée par
/// Firebase pour les SPAs.
///
/// Note : si on porte un jour cette console en desktop/mobile, basculer sur
/// `GoogleSignIn().signIn()` + credentials, cf historique git.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _signingIn = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Fallback non-web (desktop/mobile) — non utilisé en pratique.
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
      // Le router redirect prendra le relais.
    } on FirebaseAuthException catch (e) {
      // popup-closed-by-user = annulation utilisateur, pas une erreur à afficher
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        // Silencieux
      } else {
        setState(() => _error = e.message ?? 'Erreur d\'authentification.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFD2A24C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    'K',
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Kilimandjaro Admin',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Console de modération et de gestion des packs',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _signingIn ? null : _signIn,
                icon: _signingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _signingIn
                      ? 'Connexion…'
                      : 'Se connecter avec Google',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
