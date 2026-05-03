import 'package:defi_kilimandjaro/presentation/splash/splash_view.dart';
import 'package:go_router/go_router.dart';

/// Routes nommées de l'application.
///
/// Les écrans 02-08 seront branchés au fil des phases (cf. plan.md §2).
abstract final class AppRoutes {
  static const splash = '/';
  static const hub = '/hub';
  static const game = '/game/:levelId';
  static const result = '/result';
  static const map = '/map';
  static const mountain = '/mountain/:countryCode';
  static const profile = '/profile';
  static const duel = '/duel/:matchId';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (_, __) => const SplashView(),
    ),
    // TODO(phase-1): hub, game, result
    // TODO(phase-2): map, mountain
    // TODO(phase-3): profile
    // TODO(phase-6): duel
  ],
);
