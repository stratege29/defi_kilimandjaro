import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Gates the console behind a Google Sign-in.
///
/// The Cloud Function rule check on the moderator side relies on a custom
/// claim `role: moderator` set via Firebase Admin (out-of-band). This widget
/// only authenticates — it does not authorize.
class AuthGate extends StatelessWidget {
  const AuthGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = snapshot.data;
        if (user == null) return const _SignInScreen();
        return child;
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

class _SignInScreen extends StatelessWidget {
  const _SignInScreen();

  Future<void> _signIn() async {
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
            const Text('Console de modération'),
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
