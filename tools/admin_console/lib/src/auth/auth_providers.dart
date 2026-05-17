// AdminClaims est un simple value-object — chaque getter est trivial et
// nommé explicitement (uid, email, role, isAdmin…). Pas d'intérêt à
// doc-commenter chaque champ.
// ignore_for_file: public_member_api_docs

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream brut de l'utilisateur Firebase courant.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// État authentique + claims du compte courant.
///
/// On force un `getIdTokenResult(true)` pour récupérer les custom claims
/// poussés out-of-band via Firebase Admin SDK (claim `role: admin` ou
/// `role: moderator`).
final adminClaimsProvider = FutureProvider<AdminClaims>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const AdminClaims.unauthenticated();
  final token = await user.getIdTokenResult(true);
  final role = token.claims?['role'] as String?;
  return AdminClaims(
    uid: user.uid,
    email: user.email,
    displayName: user.displayName,
    role: role,
  );
});

/// Claims pertinents pour autoriser l'accès aux écrans de la console.
class AdminClaims {
  const AdminClaims({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
  });

  const AdminClaims.unauthenticated()
      : uid = null,
        email = null,
        displayName = null,
        role = null;

  final String? uid;
  final String? email;
  final String? displayName;
  final String? role;

  bool get isAdmin => role == 'admin';
  bool get isModerator => role == 'moderator' || role == 'admin';
  bool get isAuthenticated => uid != null;
}
