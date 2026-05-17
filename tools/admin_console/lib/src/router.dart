import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/app_shell.dart';
import 'package:kilimandjaro_admin/src/auth/auth_gate.dart';
import 'package:kilimandjaro_admin/src/moderation/moderation_queue_screen.dart';
import 'package:kilimandjaro_admin/src/packs/presentation/pack_edit_view.dart';
import 'package:kilimandjaro_admin/src/packs/presentation/packs_list_view.dart';
import 'package:kilimandjaro_admin/src/packs/presentation/question_edit_view.dart';
import 'package:kilimandjaro_admin/src/packs/presentation/questions_list_view.dart';

/// Construit le router go_router de la console.
/// `AuthGate` est appliqué au niveau du `ShellRoute` ; les enfants
/// supposent toujours un admin connecté.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/packs',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AuthGate(
          child: AppShell(
            location: state.matchedLocation,
            child: child,
          ),
        ),
        routes: [
          GoRoute(
            path: '/packs',
            builder: (_, __) => const PacksListView(),
            routes: [
              GoRoute(
                path: ':packId',
                builder: (_, state) => PackEditView(
                  packId: state.pathParameters['packId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'questions',
                    builder: (_, state) => QuestionsListView(
                      packId: state.pathParameters['packId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: ':questionId',
                        builder: (_, state) => QuestionEditView(
                          packId: state.pathParameters['packId']!,
                          questionId: state.pathParameters['questionId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/moderation',
            // Pour la file UGC, on accepte aussi le rôle `moderator`.
            builder: (_, __) => const _ModerationShell(),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route inconnue : ${state.uri.path}')),
    ),
  );
}

class _ModerationShell extends StatelessWidget {
  const _ModerationShell();
  @override
  Widget build(BuildContext context) {
    // L'AuthGate au niveau ShellRoute applique already requireAdmin=true,
    // mais on ré-héberge ici pour éventuellement assouplir plus tard.
    return const ModerationQueueScreen();
  }
}
