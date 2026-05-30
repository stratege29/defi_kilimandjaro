import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/app/root_shell.dart';
import 'package:kilimandjaro_admin/src/auth/sign_in_screen.dart';
import 'package:kilimandjaro_admin/src/catalog/catalog_screen.dart';
import 'package:kilimandjaro_admin/src/moderation/moderation_queue_screen.dart';
import 'package:kilimandjaro_admin/src/pack_editor/pack_editor_screen.dart';

/// Routes nommées centralisées.
///
/// Important : changer un path ici peut casser des bookmarks navigateur.
/// Si on rename `/catalog` en `/packs`, ajouter une redirection legacy.
abstract class AdminRoutes {
  static const String signIn = '/sign-in';
  static const String moderation = '/moderation';
  static const String catalog = '/catalog';
  static const String packEditor = '/pack/:packId';

  static String packEditorPath(String packId) => '/pack/$packId';
}

/// Le routeur de l'admin console.
///
/// Auth gate intégrée via `redirect` :
///   - Pas d'auth → /sign-in
///   - Auth + tentative d'accès à /sign-in → /moderation (default home)
///
/// Le check du custom claim `role` (admin / editor / moderator) est délégué
/// aux règles Firestore et aux Cloud Functions admin (`requireAdmin`,
/// `requireEditor`). L'UI affiche les actions de manière permissive ; un
/// non-autorisé reçoit `permission-denied` au call CF.
final adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AdminRoutes.moderation,
    refreshListenable: GoRouterRefreshStream(
      FirebaseAuth.instance.authStateChanges(),
    ),
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isSignIn = state.matchedLocation == AdminRoutes.signIn;
      if (user == null && !isSignIn) return AdminRoutes.signIn;
      if (user != null && isSignIn) return AdminRoutes.moderation;
      return null;
    },
    routes: [
      GoRoute(
        path: AdminRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            RootShell(currentLocation: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AdminRoutes.moderation,
            builder: (context, state) => const ModerationQueueScreen(),
          ),
          GoRoute(
            path: AdminRoutes.catalog,
            builder: (context, state) => const CatalogScreen(),
          ),
          GoRoute(
            path: AdminRoutes.packEditor,
            builder: (context, state) {
              final packId = state.pathParameters['packId']!;
              return PackEditorScreen(packId: packId);
            },
          ),
        ],
      ),
    ],
  );
});

/// Adapter qui rebuild GoRouter quand le stream auth émet.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (_) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
