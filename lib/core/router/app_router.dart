import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/game/game_view.dart';
import 'package:defi_kilimandjaro/presentation/hub/hub_view.dart';
import 'package:defi_kilimandjaro/presentation/splash/splash_view.dart';
import 'package:go_router/go_router.dart';

/// Routes nommées de l'application.
abstract final class AppRoutes {
  static const splash = '/';
  static const hub = '/hub';
  static const game = '/game';
  static const result = '/result';
  static const map = '/map';
  static const mountain = '/mountain/:countryCode';
  static const profile = '/profile';
  static const duel = '/duel/:matchId';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (_, __) => const SplashView(),
    ),
    GoRoute(
      path: AppRoutes.hub,
      name: 'hub',
      builder: (_, __) => const HubView(),
    ),
    GoRoute(
      path: AppRoutes.game,
      name: 'game',
      builder: (_, state) {
        final devinette = state.extra! as Devinette;
        return GameView(devinette: devinette);
      },
    ),
    // TODO(phase-1.3): result (victory / failure screens)
    // TODO(phase-2): map, mountain
    // TODO(phase-3): profile
    // TODO(phase-6): duel
  ],
);
