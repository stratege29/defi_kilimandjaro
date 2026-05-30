import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Écran de sign-in (public, monté quand le user n'est pas authentifié).
///
/// Sur Web, on utilise `signInWithRedirect` plutôt que `signInWithPopup` :
///
///   - signInWithPopup échoue sur localhost à cause de Cross-Origin-Opener-Policy
///     (COOP) qui empêche la fenêtre popup OAuth de communiquer le résultat à
///     la fenêtre parent. Symptôme : la popup s'ouvre, fait l'OAuth, puis se
///     referme avec un "Error" générique sans connecter l'utilisateur.
///
///   - signInWithRedirect redirige la page entière → pas de cross-window
///     communication → pas de problème COOP. Au retour, `getRedirectResult()`
///     dans main() récupère le user.
///
/// La récupération du résultat est dans `main.dart` (cf `getRedirectResult`
/// avant `runApp`). Le router redirect prend ensuite le relais.
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
        // Redirige la page entière vers Google → retour via Firebase auth
        // handler → page reload → main() appelle getRedirectResult().
        await FirebaseAuth.instance.signInWithRedirect(provider);
        // Pas de code après ici : la page est en train de naviguer.
      } else {
        // Fallback non-web (desktop/mobile) — non utilisé en pratique.
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Erreur d\'authentification.');
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
