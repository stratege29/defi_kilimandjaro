import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_create_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_deep_link_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_entry_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_play_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_result_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_scan_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_view.dart';
import 'package:defi_kilimandjaro/presentation/hub/hub_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/add_friend_confirm_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/add_friend_scan_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/add_friend_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/leaderboard_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_detail_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_list_view.dart';
import 'package:defi_kilimandjaro/presentation/onboarding/onboarding_view.dart';
import 'package:defi_kilimandjaro/presentation/profile/profile_view.dart';
import 'package:defi_kilimandjaro/presentation/shop/shop_view.dart';
import 'package:defi_kilimandjaro/presentation/splash/splash_view.dart';
import 'package:flutter/material.dart';
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

  /// Deep link entrant : `kilimandjaro://duel/<matchId>` → `/duel/join/:matchId`.
  ///
  /// Utilisé par DeepLinkService et par le handler FCM de l'agent backend.
  /// Le paramètre path est `:matchId`.
  static const duelJoin = '/duel/join/:matchId';

  /// Construit le path de navigation vers un match via deep link.
  static String duelJoinPath(String matchId) => '/duel/join/$matchId';

  // Leaderboard & amis (PR #4).
  static const leaderboard = '/leaderboard';
  static const addFriend = '/leaderboard/add-friend';
  static const addFriendScan = '/leaderboard/add-friend/scan';

  /// Route deep link `kilimandjaro://friend/<uid>` → `/friend/add/<uid>`.
  static const friendAdd = '/friend/add';

  /// Construit le path de navigation vers la confirmation d'ajout d'ami.
  static String friendAddPath(String uid) => '/friend/add/$uid';
}

/// Clé de navigation globale exposée pour DeepLinkService et le handler FCM.
///
/// L'agent backend (FCM) peut récupérer cette clé depuis `app_router.dart`
/// pour accéder au contexte de navigation sans dépendre de BuildContext.
final GlobalKey<NavigatorState> appRouterNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appRouter');

final GoRouter appRouter = GoRouter(
  navigatorKey: appRouterNavigatorKey,
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  // Quand iOS/Android forwarde un URI custom-scheme (kilimandjaro://X/Y),
  // go_router le reçoit comme location avant que DeepLinkService ne puisse
  // intervenir. On réécrit :
  // - kilimandjaro://duel/<matchId>   → /duel/join/<matchId>
  // - kilimandjaro://friend/<uid>     → /friend/add/<uid>
  redirect: (context, state) {
    final uri = state.uri;
    if (uri.scheme == 'kilimandjaro') {
      if (uri.host == 'duel') {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty && segments.first.isNotEmpty) {
          return AppRoutes.duelJoinPath(segments.first);
        }
      } else if (uri.host == 'friend') {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty && segments.first.isNotEmpty) {
          return AppRoutes.friendAddPath(segments.first);
        }
      }
    }
    return null;
  },
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
    // duelPlay : transition crossfade 400ms depuis le lobby.
    GoRoute(
      path: AppRoutes.duelPlay,
      name: 'duel-play',
      pageBuilder: (_, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: DuelPlayView(
          initialSession: state.extra! as DuelSession,
        ),
        transitionDuration: const Duration(milliseconds: 400),
        // reverseTransitionDuration defaults to transitionDuration (400ms) —
        // explicitly set a shorter one for the back gesture.
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
          child: child,
        ),
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
    // Accepte un [LobbyArgs] optionnel en extra pour le mode rematch.
    GoRoute(
      path: AppRoutes.duelLobby,
      name: 'duel-lobby',
      builder: (_, state) {
        // Réinitialise l'UID rematch quand on arrive via navigation directe
        // (sans LobbyArgs). Le provider est mis à jour avant la navigation
        // dans DuelResultView._onRematch via lobbyRematchUidProvider.
        return const LobbyView();
      },
    ),
    // PR #3 — Deep link : `kilimandjaro://duel/<matchId>`.
    // [DuelDeepLinkView] gère le join asynchrone puis redirige vers
    // [DuelPlayView] ou affiche un message d'erreur.
    GoRoute(
      path: '/duel/join/:matchId',
      name: 'duel-join',
      builder: (_, state) => DuelDeepLinkView(
        matchId: state.pathParameters['matchId']!,
      ),
    ),
    // -------------------------------------------------------------------------
    // PR #4 — Leaderboard & amis
    // -------------------------------------------------------------------------
    GoRoute(
      path: AppRoutes.leaderboard,
      name: 'leaderboard',
      builder: (_, __) => const LeaderboardView(),
    ),
    GoRoute(
      path: AppRoutes.addFriend,
      name: 'add-friend',
      builder: (_, __) => const AddFriendView(),
    ),
    GoRoute(
      path: AppRoutes.addFriendScan,
      name: 'add-friend-scan',
      builder: (_, __) => const AddFriendScanView(),
    ),
    // Route deep link `kilimandjaro://friend/{uid}` → `/friend/add/:uid`.
    GoRoute(
      path: '/friend/add/:uid',
      name: 'friend-add-confirm',
      builder: (_, state) => AddFriendConfirmView(
        friendUid: state.pathParameters['uid'] ?? '',
      ),
    ),
  ],
);
