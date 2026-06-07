import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Écran de sign-in (public, monté quand le user n'est pas authentifié).
///
/// Web : `signInWithPopup` par défaut (le flux le plus fiable en Chrome/Edge ;
/// c'est la méthode recommandée par Firebase pour les navigateurs qui bloquent
/// le stockage tiers). `signInWithRedirect` est dispo en fallback via le toggle
/// (affiché en cas d'erreur), mais FlutterFire web a un bug connu où
/// getRedirectResult() peut retourner null.
///
/// NB Safari : il existe un bug de pointer-events de Flutter web sur certaines
/// versions de Safari où les clics ne sont pas dispatchés à l'app. Si rien ne
/// réagit au clic, utiliser Chrome/Edge (l'admin console est un outil interne).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _signingIn = false;
  String? _error;
  String? _errorDetail;
  bool _useRedirect = false;

  String _firebaseDiagnostic() {
    try {
      final app = Firebase.app();
      final opts = app.options;
      final key = opts.apiKey;
      final maskedKey = key.length > 8
          ? '${key.substring(0, 4)}…${key.substring(key.length - 4)}'
          : '(stub)';
      return 'project=${opts.projectId} apiKey=$maskedKey';
    } catch (e) {
      return 'Firebase non initialisé : $e';
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
      _errorDetail = null;
    });
    developer.log(
      '[SIGN-IN] start (kIsWeb=$kIsWeb, useRedirect=$_useRedirect)',
      name: 'admin.signin',
    );
    developer.log('[SIGN-IN] ${_firebaseDiagnostic()}', name: 'admin.signin');

    try {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      if (kIsWeb) {
        if (_useRedirect) {
          await FirebaseAuth.instance.signInWithRedirect(provider);
        } else {
          await FirebaseAuth.instance.signInWithPopup(provider);
        }
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
    } on FirebaseAuthException catch (e, st) {
      developer.log(
        '[SIGN-IN] FirebaseAuthException code=${e.code} msg=${e.message}',
        name: 'admin.signin',
        error: e,
        stackTrace: st,
      );
      setState(() {
        _error = 'Erreur Firebase: ${e.code}';
        _errorDetail = e.message ?? '(pas de message)';
      });
    } catch (e, st) {
      developer.log(
        '[SIGN-IN] Exception type=${e.runtimeType} : $e',
        name: 'admin.signin',
        error: e,
        stackTrace: st,
      );
      setState(() {
        _error = '${e.runtimeType}';
        _errorDetail = e.toString();
      });
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
                  _signingIn ? 'Connexion…' : 'Se connecter avec Google',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_errorDetail != null) ...[
                          const SizedBox(height: 6),
                          SelectableText(
                            _errorDetail!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _firebaseDiagnostic(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _useRedirect = !_useRedirect;
                      _error = null;
                      _errorDetail = null;
                    });
                  },
                  child: Text(
                    _useRedirect
                        ? 'Essayer en mode popup'
                        : 'Essayer en mode redirect',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
