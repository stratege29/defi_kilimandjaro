import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_daily_challenge_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/continue_ascent_card.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/daily_streak_dialog.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/home_access_tiles.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/home_header.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/packs_section.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 00 — Hub d'Accueil.
///
/// Page d'atterrissage par défaut au lancement de l'app. **Retenue radicale** :
/// 3 zones à l'espace négatif généreux, centrées sur l'ascension.
/// Composition :
/// - [HomeHeader] : pastilles série + cauris
/// - [ContinueAscentCard] : HERO sommet en cours + CTA GRIMPER intégré
/// - [HomeAccessTiles] : Défier en ligne · Défier un ami · Défi du jour · Sommets
/// - [PacksSection] : carrousel TES PACKS (packs possédés + Découvrir)
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  /// True une fois que le popup streak a été affiché (ou ignoré) sur cette
  /// session. Évite de le ré-déclencher si l'utilisateur revient à l'accueil
  /// via la bottom nav après l'avoir vu.
  bool _streakDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowStreak());
  }

  /// Affiche le popup streak escalier si claimable et pas déjà montré
  /// dans la session. Best-effort : si Remote Config n'est pas prêt on
  /// utilise les defaults, donc toujours fonctionnel.
  Future<void> _maybeShowStreak() async {
    if (_streakDialogShown) return;
    if (!mounted) return;
    final config = ref.read(gameEconomyConfigProvider);
    final claim = ref
        .read(playerProgressProvider.notifier)
        .peekClaimableStreak(config: config);
    if (claim == null) return;
    _streakDialogShown = true;
    await showDialog<int>(
      context: context,
      builder: (_) => DailyStreakDialog(streakDay: claim.streakDay),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const HomeHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: const [
                  // Zone 1 — HÉROS : continuer l'ascension + CTA GRIMPER.
                  ContinueAscentCard(),
                  SizedBox(height: 16),
                  // Zone 2 — accès rapide : duels, défi du jour, sommets.
                  HomeAccessTiles(),
                  SizedBox(height: 24),
                  // Zone 3 — TES PACKS : carrousel des packs possédés.
                  PacksSection(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.accueil,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              break;
            case NavTab.defi:
              context.go(AppRoutes.hub);
            case NavTab.sommets:
              context.go(AppRoutes.mountains);
            case NavTab.profil:
              context.go(AppRoutes.profile);
          }
        },
      ),
    );
  }
}

/// Lance le niveau suivant d'un sommet : résout config + devinette,
/// enregistre l'id pour anti-répétition et navigue vers `/game`.
///
/// Helper public partagé entre la carte HERO et le bouton GRIMPER du
/// sticky CTA. Conservé ici (hors widget) pour rester à la frontière
/// présentation/data sans dépendance circulaire.
Future<void> launchNextLevel(
  BuildContext context,
  WidgetRef ref,
  Mountain mountain,
) async {
  final levelNumber = mountain.completedLevels + 1;
  try {
    final selectionService = ref.read(devinetteSelectionServiceProvider);
    final progress = ref.read(playerProgressProvider);
    final config = LevelDifficultyResolver.resolve(
      mountain: mountain,
      levelIndex: levelNumber,
    );
    final devinette = await selectionService.nextDevinette(
      mix: progress.activePackMix,
      targetDifficulty: config.difficultyTier,
      wordLengthBucket: config.wordLengthBucket,
      excludeIds: progress.recentDevinetteIds.toSet(),
      fallbackPackIds: progress.ownedPacks,
    );
    await ref
        .read(playerProgressProvider.notifier)
        .recordRecentDevinette(devinette.id);
    if (!context.mounted) return;
    await context.push<void>(
      AppRoutes.game,
      extra: GameArgs(
        devinette: devinette,
        mountainId: mountain.id,
        levelIndex: levelNumber,
        config: config,
      ),
    );
  } on Object catch (_) {
    // `on Object` (pas `on Exception`) : un tirage épuisé lève un
    // `StateError`, qui étend `Error` et n'est PAS une `Exception`.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur de chargement', style: AppTypography.bebas()),
        backgroundColor: AppColors.rouge,
      ),
    );
  }
}

/// Lance le Défi du jour : calibre une config Tier 3 via une montagne
/// virtuelle, lit le mot du jour partagé (Firestore d'abord, fallback
/// bundle) puis navigue vers `/game` en mode daily.
///
/// Helper public partagé entre la tuile « Défi du jour » de l'accueil et
/// tout autre point d'entrée. Si le pool est vide (ni Firestore ni bundle),
/// affiche un snackbar d'erreur.
Future<void> launchDailyChallenge(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  try {
    const virtualMountain = Mountain(
      id: '__daily__',
      name: 'Daily',
      countryCode: 'XX',
      countryName: 'Daily',
      flagEmoji: '★',
      altitude: 2000,
      totalLevels: 1,
    );
    final config = LevelDifficultyResolver.resolve(
      mountain: virtualMountain,
      levelIndex: 1,
    );
    final devinette = await ref
        .read(dailyChallengeRepositoryProvider)
        .fetchDevinetteForDate(today);
    if (!context.mounted) return;
    if (devinette == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('daily.pool_empty'.tr(), style: AppTypography.bebas()),
          backgroundColor: AppColors.rouge,
        ),
      );
      return;
    }
    await context.push<void>(
      AppRoutes.game,
      extra: GameArgs.daily(devinette: devinette, config: config, date: today),
    );
  } on Exception catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('daily.pool_empty'.tr(), style: AppTypography.bebas()),
        backgroundColor: AppColors.rouge,
      ),
    );
  }
}
