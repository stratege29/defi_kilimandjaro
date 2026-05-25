import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/continue_ascent_card.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/duels_carousel.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/home_header.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/news_carousel.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/packs_section.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/recommended_match_banner.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/stats_row.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/sticky_cta_bar.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/welcome_card.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 00 — Hub d'Accueil.
///
/// Page d'atterrissage par défaut au lancement de l'app. Composition de
/// blocs world-class :
/// - [HomeHeader] : streak pulsé · KILIMANDJARO · cauris · altitude (Hero)
/// - [WelcomeCard] : griot animé + salutation + bulle parchemin proverbe
/// - [ContinueAscentCard] : HERO sommet en cours, silhouette + Fraunces XL
/// - [DuelsCarousel] : 3 cards défis horizontales
/// - [RecommendedMatchBanner] : stub conditionnel
/// - [PacksSection] : carrousel packs possédés + SYNC
/// - [NewsCarousel] : promos packs payants + UGC + classement
/// - [StatsRow] : 3 carrés stats premium Fraunces
/// - [StickyCtaBar] : GRIMPER (shimmer) + DÉFIER (outline)
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  WelcomeCard(),
                  SizedBox(height: 22),
                  ContinueAscentCard(),
                  SizedBox(height: 22),
                  DuelsCarousel(),
                  SizedBox(height: 22),
                  RecommendedMatchBanner(),
                  // RecommendedMatchBanner se réduit à SizedBox.shrink quand
                  // aucune reco n'est dispo — pas besoin de SizedBox conditionnel.
                  PacksSection(),
                  SizedBox(height: 22),
                  NewsCarousel(),
                  SizedBox(height: 22),
                  StatsRow(),
                  SizedBox(height: 16),
                ],
              ),
            ),
            const StickyCtaBar(),
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
  } on Exception catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur de chargement', style: AppTypography.bebas()),
        backgroundColor: AppColors.rouge,
      ),
    );
  }
}
