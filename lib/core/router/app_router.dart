import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_create_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_entry_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_play_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_result_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_scan_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_view.dart';
import 'package:defi_kilimandjaro/presentation/hub/hub_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_detail_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_list_view.dart';
import 'package:defi_kilimandjaro/presentation/onboarding/onboarding_view.dart';
import 'package:defi_kilimandjaro/presentation/profile/profile_view.dart';
import 'package:defi_kilimandjaro/presentation/shop/shop_view.dart';
import 'package:defi_kilimandjaro/presentation/splash/splash_view.dart';
import 'package:go_router/go_router.dart';

/// Routes nommées de l'application.
abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const hub = '/hub';
  static const game = '/game';
  static const result = '/result';
  static const mountains = '/mountains';
  static const mountain = '/mountain';
  static const profile = '/profile';
  static const shop = '/shop';
  static const duel = '/duel';
  static const duelCreate = '/duel/create';
  static const duelScan = '/duel/scan';
  static const duelPlay = '/duel/play';
  static const duelResult = '/duel/result';

  /// Lobby matchmaking ELO (Phase 6).
  static const duelLobby = '/duel/lobby';
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
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (_, __) => const OnboardingView(),
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
        // Accepts either GameArgs (Phase 2.3+) or a bare Devinette (legacy
        // Hub call from Phase 1).
        final extra = state.extra;
        final args = extra is GameArgs
            ? extra
            : GameArgs(devinette: extra! as Devinette);
        return GameView(args: args);
      },
    ),
    GoRoute(
      path: AppRoutes.mountains,
      name: 'mountains',
      builder: (_, __) => const MountainListView(),
    ),
    GoRoute(
      path: AppRoutes.mountain,
      name: 'mountain',
      builder: (_, state) => MountainDetailView(
        mountain: state.extra! as Mountain,
      ),
    ),
    GoRoute(
      path: AppRoutes.profile,
      name: 'profile',
      builder: (_, __) => const ProfileView(),
    ),
    GoRoute(
      path: AppRoutes.shop,
      name: 'shop',
      builder: (_, __) => const ShopView(),
    ),
    GoRoute(
      path: AppRoutes.duel,
      name: 'duel',
      builder: (_, __) => const DuelEntryView(),
    ),
    GoRoute(
      path: AppRoutes.duelCreate,
      name: 'duel-create',
      builder: (_, __) => const DuelCreateView(),
    ),
    GoRoute(
      path: AppRoutes.duelScan,
      name: 'duel-scan',
      builder: (_, __) => const DuelScanView(),
    ),
    GoRoute(
      path: AppRoutes.duelPlay,
      name: 'duel-play',
      builder: (_, state) => DuelPlayView(
        initialSession: state.extra! as DuelSession,
      ),
    ),
    GoRoute(
      path: AppRoutes.duelResult,
      name: 'duel-result',
      builder: (_, state) => DuelResultView(
        session: state.extra! as DuelSession,
      ),
    ),
    // Phase 6 — matchmaking ELO lobby.
    GoRoute(
      path: AppRoutes.duelLobby,
      name: 'duel-lobby',
      builder: (_, __) => const LobbyView(),
    ),
  ],
);
