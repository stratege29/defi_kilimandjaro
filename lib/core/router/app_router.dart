import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/discover/discover_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_create_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_deep_link_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_entry_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_hub_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_play_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_result_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_scan_view.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_view.dart';
import 'package:defi_kilimandjaro/presentation/grimper/grimper_view.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/add_friend_confirm_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/add_friend_scan_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/add_friend_view.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/leaderboard_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_detail_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_list_view.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_reveal_intent.dart';
import 'package:defi_kilimandjaro/presentation/my_packs/my_packs_view.dart';
import 'package:defi_kilimandjaro/presentation/onboarding/onboarding_view.dart';
import 'package:defi_kilimandjaro/presentation/pack_chooser/pack_chooser_view.dart';
import 'package:defi_kilimandjaro/presentation/profile/avatar_picker_view.dart';
import 'package:defi_kilimandjaro/presentation/profile/profile_view.dart';
import 'package:defi_kilimandjaro/presentation/shop/shop_view.dart';
import 'package:defi_kilimandjaro/presentation/splash/splash_view.dart';
import 'package:defi_kilimandjaro/presentation/tournament/tournament_arena_view.dart';
import 'package:defi_kilimandjaro/presentation/tournament/tournament_detail_view.dart';
import 'package:defi_kilimandjaro/presentation/tournament/tournament_list_view.dart';
import 'package:defi_kilimandjaro/presentation/tournament/tournament_results_view.dart';
import 'package:defi_kilimandjaro/presentation/ugc/my_submissions/my_submissions_view.dart';
import 'package:defi_kilimandjaro/presentation/ugc/submit_devinette/submit_devinette_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Arguments de navigation vers [AppRoutes.duelPlay] pour un match de tournoi.
///
/// Le duel classique passe directement un [DuelSession] en `extra` ; un match
/// d'arène passe ce wrapper pour transporter le `tournamentId` (retour à
/// l'arène en fin de match).
class DuelPlayArgs {
  const DuelPlayArgs({required this.session, required this.tournamentId});
  final DuelSession session;
  final String tournamentId;
}

/// Routes nommées de l'application.
abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';

  /// Hub d'accueil — page d'atterrissage par défaut après onboarding.
  static const home = '/accueil';

  /// Hub Défi 1v1 (onglet « Défi » de la nav bottom).
  static const hub = '/hub';

  /// Hub de jeu plein écran (CTA sticky GRIMPER de l'accueil) — modes solo /
  /// en ligne / tournoi / ami. Cf [GrimperView].
  static const grimper = '/grimper';
  static const game = '/game';
  static const result = '/result';
  static const mountains = '/mountains';

  /// Détail d'une montagne — **niché** sous [mountains]. Naviguer via
  /// `context.go(AppRoutes.mountain, extra: m)` reconstruit la pile
  /// `[Sommets → détail]` de façon atomique (cf. flux de conquête dans
  /// `game_view`), ce qui évite l'empilement de détails successifs.
  static const mountain = '/mountains/mountain';
  static const profile = '/profile';
  static const avatarPicker = '/profile/avatar';
  static const shop = '/shop';

  /// Écran « Découvrir » — packs de contenu, promos & actualités
  /// (relocalisés hors de l'accueil). Distinct de [shop] (recharge cauris).
  static const discover = '/discover';
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

  // UGC — devinettes communautaires.
  static const ugcSubmit = '/ugc/submit';
  static const ugcMine = '/ugc/mine';

  // Phase 3 — packs thématiques.
  static const packChooser = '/pack-chooser';
  static const myPacks = '/my-packs';

  // Tournois « arène » (mode multi-joueurs temporisé).
  static const tournaments = '/tournaments';

  static String tournamentDetailPath(String tid) => '/tournaments/$tid';
  static String tournamentArenaPath(String tid) => '/tournaments/$tid/arena';
  static String tournamentResultsPath(String tid) =>
      '/tournaments/$tid/results';
}

/// Clé de navigation globale exposée pour DeepLinkService et le handler FCM.
///
/// L'agent backend (FCM) peut récupérer cette clé depuis `app_router.dart`
/// pour accéder au contexte de navigation sans dépendre de BuildContext.
final GlobalKey<NavigatorState> appRouterNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appRouter');

/// Notifier qui réévalue le redirect go_router quand [hasChosenFreePackProvider]
/// change. Pattern officiel recommandé par go_router + Riverpod.
///
/// Voir : https://pub.dev/packages/go_router#refreshing-with-listenable
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<bool>(hasChosenFreePackProvider, (_, __) => notifyListeners());
  }
}

/// Provider du [GoRouter] configuré avec le gate "hasChosenFreePack".
///
/// Exposé comme provider pour que le notifier ait accès au [Ref] Riverpod.
/// Consommé dans `KilimandjaroApp` via `ref.watch(appRouterProvider)`.
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    navigatorKey: appRouterNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      // ---- Deep-link scheme rewriting (unchanged) ----
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

      // ---- Pack-chooser gate ----
      // Splash et onboarding sont autorisés sans vérification (le joueur
      // n'a pas encore vu le flow et hasChosenFreePack est forcément false).
      final loc = state.matchedLocation;
      final isSplash = loc == AppRoutes.splash;
      final isOnboarding = loc == AppRoutes.onboarding;
      if (isSplash || isOnboarding) return null;

      final hasChosen = ref.read(hasChosenFreePackProvider);
      final goingToChooser = loc == AppRoutes.packChooser;

      if (!hasChosen && !goingToChooser) return AppRoutes.packChooser;
      if (hasChosen && goingToChooser) return AppRoutes.home;
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
      path: AppRoutes.home,
      name: 'home',
      builder: (_, __) => const HomeView(),
    ),
    GoRoute(
      path: AppRoutes.hub,
      name: 'hub',
      // Phase 5b: Défi tab now lands on the new DuelHubView (Vert Nuit redesign).
      builder: (_, __) => const DuelHubView(),
    ),
    GoRoute(
      path: AppRoutes.grimper,
      name: 'grimper',
      builder: (_, __) => const GrimperView(),
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
            : GameArgs.legacy(devinette: extra! as Devinette);
        return GameView(args: args);
      },
    ),
    GoRoute(
      path: AppRoutes.mountains,
      name: 'mountains',
      // `extra` optionnel : un MountainRevealIntent déclenche l'animation
      // d'ascension (atterrir sur le sommet conquis puis scroller vers le
      // suivant). Toute autre valeur / null → comportement par défaut.
      builder: (_, state) => MountainListView(
        revealIntent: state.extra is MountainRevealIntent
            ? state.extra! as MountainRevealIntent
            : null,
      ),
      routes: <RouteBase>[
        // Détail montagne niché sous Sommets. Le path est relatif
        // (`mountain`) → résout en `/mountains/mountain` (= AppRoutes.mountain).
        // Conséquence : `context.go(AppRoutes.mountain, …)` rebâtit la pile
        // complète [Sommets → détail], donc « retour » ramène toujours au
        // hub Sommets et les conquêtes en chaîne n'empilent plus de détails.
        GoRoute(
          path: 'mountain',
          name: 'mountain',
          builder: (_, state) => MountainDetailView(
            mountain: state.extra! as Mountain,
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.profile,
      name: 'profile',
      builder: (_, __) => const ProfileView(),
    ),
    GoRoute(
      path: AppRoutes.avatarPicker,
      name: 'avatar-picker',
      builder: (_, __) => const AvatarPickerView(),
    ),
    GoRoute(
      path: AppRoutes.shop,
      name: 'shop',
      builder: (_, __) => const ShopView(),
    ),
    GoRoute(
      path: AppRoutes.discover,
      name: 'discover',
      builder: (_, __) => const DiscoverView(),
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
        child: () {
          final extra = state.extra;
          // Soit un [DuelSession] (duel classique), soit un [DuelPlayArgs]
          // (match de tournoi, avec tournamentId pour le retour à l'arène).
          if (extra is DuelPlayArgs) {
            return DuelPlayView(
              initialSession: extra.session,
              tournamentId: extra.tournamentId,
            );
          }
          return DuelPlayView(initialSession: extra! as DuelSession);
        }(),
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
    // -------------------------------------------------------------------------
    // Tournois « arène »
    // -------------------------------------------------------------------------
    GoRoute(
      path: AppRoutes.tournaments,
      name: 'tournaments',
      builder: (_, __) => const TournamentListView(),
      routes: [
        GoRoute(
          path: ':tid',
          name: 'tournament-detail',
          builder: (_, state) => TournamentDetailView(
            tournamentId: state.pathParameters['tid']!,
          ),
          routes: [
            GoRoute(
              path: 'arena',
              name: 'tournament-arena',
              builder: (_, state) => TournamentArenaView(
                tournamentId: state.pathParameters['tid']!,
              ),
            ),
            GoRoute(
              path: 'results',
              name: 'tournament-results',
              builder: (_, state) => TournamentResultsView(
                tournamentId: state.pathParameters['tid']!,
              ),
            ),
          ],
        ),
      ],
    ),
    // -------------------------------------------------------------------------
    // UGC — devinettes communautaires
    // -------------------------------------------------------------------------
    GoRoute(
      path: AppRoutes.ugcSubmit,
      name: 'ugc-submit',
      builder: (_, __) => const SubmitDevinetteView(),
    ),
    GoRoute(
      path: AppRoutes.ugcMine,
      name: 'ugc-mine',
      builder: (_, __) => const MySubmissionsView(),
    ),
    // -------------------------------------------------------------------------
    // Phase 3 — packs thématiques
    // -------------------------------------------------------------------------
    GoRoute(
      path: AppRoutes.packChooser,
      name: 'pack-chooser',
      builder: (_, __) => const PackChooserView(),
    ),
    GoRoute(
      path: AppRoutes.myPacks,
      name: 'my-packs',
      builder: (_, __) => const MyPacksView(),
    ),
  ],
  );
});
