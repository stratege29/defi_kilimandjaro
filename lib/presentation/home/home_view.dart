import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/proverb_repository.dart';
import 'package:defi_kilimandjaro/data/services/daily_streak_service.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/proverb.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart'
    show kAltitudeHeroTag;
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/home/greeting.dart';
import 'package:defi_kilimandjaro/presentation/home/providers/current_mountain_provider.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/duels_carousel.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/news_carousel.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/packs_section.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/quickmatch_overlay.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/recommended_match_banner.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/stats_row.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 00 — Hub d'Accueil.
///
/// Page d'atterrissage par défaut au lancement de l'app. Agrège :
/// header (streak + cauris + altitude), salutation contextuelle, griot +
/// sagesse du jour, carte hero « Continue ta montée », carrousel des
/// défis, actualités, stats compactes et CTA sticky dual GRIMPER /
/// DÉFIER.
///
/// Construit incrémentalement — voir les tâches `home_*` du backlog.
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
            const _HomeHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: const [
                  _Greeting(),
                  SizedBox(height: 16),
                  _GriotWisdom(),
                  SizedBox(height: 20),
                  _ContinueAscent(),
                  SizedBox(height: 20),
                  DuelsCarousel(),
                  SizedBox(height: 20),
                  RecommendedMatchBanner(),
                  // RecommendedMatchBanner se réduit à SizedBox.shrink quand
                  // aucune reco n'est dispo — pas besoin de SizedBox conditionnel.
                  PacksSection(),
                  SizedBox(height: 20),
                  NewsCarousel(),
                  SizedBox(height: 20),
                  StatsRow(),
                  SizedBox(height: 12),
                ],
              ),
            ),
            const _StickyCtaBar(),
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

/// Header sticky de l'écran d'accueil.
///
/// Layout : streak 🔥 à gauche · KILIMANDJARO centré (scale-down) ·
/// chips cauris + altitude + avatar à droite. Le chip altitude partage
/// le Hero `kAltitudeHeroTag` avec Hub Défi, Lobby et Profile.
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final streakAsync = ref.watch(dailyStreakProvider);
    final myElo = profileAsync.value?.elo ?? 1000;
    final streak = streakAsync.value ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          _StreakChip(days: streak),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'KILIMANDJARO',
                style: AppTypography.bebas(size: 18),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Chip(
            iconWidget: const CaurisIcon(size: 16),
            value: '${progress.cauris}',
            trailingPlus: true,
            onTap: () => context.push(AppRoutes.shop),
          ),
          const SizedBox(width: 8),
          // Hero partagé avec Hub Défi, Lobby et Profile.
          Hero(
            tag: kAltitudeHeroTag,
            child: _AltitudeHeroChip(elo: myElo),
          ),
        ],
      ),
    );
  }
}

/// Salutation contextuelle : `{salut} {prénom} !` + date du jour.
///
/// Le mot de salutation tourne en fonction de l'heure (matin/après-midi/
/// soir/nuit) et du jour de l'année, couvrant baoulé, dioula, bété et
/// français. Voir `greeting.dart`.
class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final name = profileAsync.value?.displayName;
    final hasName = (name ?? '').trim().isNotEmpty;
    final now = DateTime.now();
    final salutation = greetingFor(now);
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasName ? '$salutation ${name!.trim()} !' : '$salutation !',
          style: AppTypography.bebas(size: 26, color: AppColors.orSoleil),
        ),
        const SizedBox(height: 4),
        Text(
          _capitalize(dateLabel),
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.texteSecondaire,
            style: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Bloc Griot + Sagesse du jour.
///
/// Illustration de griot (asset existant) à gauche + carte parchemin
/// avec proverbe + attribution. Le proverbe est sélectionné de manière
/// déterministe pour la journée — voir `dailyProverbProvider`.
class _GriotWisdom extends ConsumerWidget {
  const _GriotWisdom();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proverbAsync = ref.watch(dailyProverbProvider);

    return Row(
      children: [
        Image.asset(
          AppAssets.griotWelcome,
          width: 84,
          height: 100,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _WisdomBubble(proverbAsync: proverbAsync),
        ),
      ],
    );
  }
}

class _WisdomBubble extends StatelessWidget {
  const _WisdomBubble({required this.proverbAsync});

  final AsyncValue<Proverb> proverbAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.ivoire.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.bois.withValues(alpha: 0.6)),
      ),
      child: proverbAsync.when(
        loading: () => Text(
          '...',
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.boisFonce,
            style: FontStyle.italic,
          ),
        ),
        error: (_, __) => Text(
          'La parole du jour est en chemin.',
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.boisFonce,
            style: FontStyle.italic,
          ),
        ),
        data: (p) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '« ${p.text} »',
              style: AppTypography.crimson(
                size: 14,
                color: AppColors.boisFonce,
                style: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Proverbe ${p.ethnie} · ${p.region}',
              style: AppTypography.bebas(
                size: 11,
                color: AppColors.boisFonce.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte HERO « Continue ta montée ».
///
/// Bloc visuel principal de l'accueil — montre le sommet en cours,
/// niveau N/total, barre de progression, stats lifetime, et lance le
/// niveau suivant au tap. État "tout gravi" renvoie vers la liste des
/// sommets.
class _ContinueAscent extends ConsumerWidget {
  const _ContinueAscent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(currentMountainProvider);
    final progress = ref.watch(playerProgressProvider);

    return currentAsync.when(
      loading: () => const _AscentSkeleton(),
      error: (_, __) => const _AscentSkeleton(),
      data: (mountain) {
        if (mountain == null) {
          return _AscentAllDone(
            totalLevels: progress.totalLevelsCompleted,
            onTap: () => context.go(AppRoutes.mountains),
          );
        }
        return _AscentCard(
          mountain: mountain,
          totalLevelsLifetime: progress.totalLevelsCompleted,
          onTap: () => launchNextLevel(context, ref, mountain),
        );
      },
    );
  }
}

class _AscentCard extends StatelessWidget {
  const _AscentCard({
    required this.mountain,
    required this.totalLevelsLifetime,
    required this.onTap,
  });

  final Mountain mountain;
  final int totalLevelsLifetime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nextLevel = mountain.completedLevels + 1;
    final progress = mountain.progress;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.vertClair.withValues(alpha: 0.22),
                AppColors.orChaud.withValues(alpha: 0.22),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.orSoleil.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    mountain.flagEmoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MONT ${mountain.name.toUpperCase()}',
                      style: AppTypography.bebas(color: AppColors.orSoleil),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'NIVEAU $nextLevel/${mountain.totalLevels}',
                    style: AppTypography.bebas(size: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                mountain.countryName,
                style: AppTypography.crimson(
                  size: 13,
                  color: AppColors.texteSecondaire,
                  style: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.boisFonce.withValues(alpha: 0.45),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.orSoleil,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.terrain,
                    size: 14,
                    color: AppColors.ivoire.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${mountain.altitude} m',
                    style: AppTypography.bebas(
                      size: 12,
                      color: AppColors.ivoire.withValues(alpha: 0.85),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$totalLevelsLifetime niveaux gravis',
                    style: AppTypography.crimson(
                      size: 12,
                      color: AppColors.texteSecondaire,
                      style: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AscentAllDone extends StatelessWidget {
  const _AscentAllDone({required this.totalLevels, required this.onTap});

  final int totalLevels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bois.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.orSoleil.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOUS LES SOMMETS GRAVIS',
                style: AppTypography.bebas(color: AppColors.orSoleil),
              ),
              const SizedBox(height: 6),
              Text(
                '$totalLevels niveaux à ton actif. Explore un autre versant.',
                style: AppTypography.crimson(
                  size: 13,
                  color: AppColors.texteSecondaire,
                  style: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AscentSkeleton extends StatelessWidget {
  const _AscentSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

/// Lance le niveau suivant d'un sommet : résout config + devinette,
/// enregistre l'id pour anti-répétition et navigue vers `/game`.
///
/// Helper public pour pouvoir être appelé à la fois depuis la carte HERO
/// et depuis le bouton GRIMPER du CTA sticky.
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

/// Barre sticky d'actions principales : GRIMPER + DÉFIER.
///
/// Pondération flex selon le profil joueur :
/// - Nouveau joueur (0 niveau) : GRIMPER 100 %.
/// - ELO < 1100 et sommet en cours : 70/30.
/// - Tous sommets gravis : DÉFIER 70/30 (GRIMPER → liste sommets).
/// - Par défaut : 50/50.
class _StickyCtaBar extends ConsumerWidget {
  const _StickyCtaBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final currentAsync = ref.watch(currentMountainProvider);
    final elo = profileAsync.value?.elo ?? 1000;
    final mountain = currentAsync.value;
    final isNewbie = progress.totalLevelsCompleted == 0;
    final allDone = mountain == null;

    final (int grimperFlex, int defierFlex) = switch ((
      isNewbie,
      allDone,
      elo,
    )) {
      (true, _, _) => (1, 0),
      (_, true, _) => (3, 7),
      (_, _, final int e) when e < 1100 => (7, 3),
      _ => (5, 5),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.vertForet,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (grimperFlex > 0)
            Expanded(
              flex: grimperFlex,
              child: _CtaButton(
                icon: Icons.terrain,
                label: 'GRIMPER',
                color: AppColors.orSoleil,
                onTap: () {
                  if (mountain != null) {
                    launchNextLevel(context, ref, mountain);
                  } else {
                    context.go(AppRoutes.mountains);
                  }
                },
              ),
            ),
          if (grimperFlex > 0 && defierFlex > 0) const SizedBox(width: 10),
          if (defierFlex > 0)
            Expanded(
              flex: defierFlex,
              child: _CtaButton(
                icon: Icons.bolt,
                label: 'DÉFIER',
                color: AppColors.vertClair,
                // Overlay quickmatch : démarre le matchmaking en modale sans
                // quitter l'accueil. Navigation auto vers /duel/play à la
                // détection d'un adversaire.
                onTap: () => showQuickmatchOverlay(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.75), width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: AppTypography.bebas(size: 18, color: color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip série quotidienne : 🔥 + nombre de jours consécutifs.
///
/// Couleur dérivée du palier : ≥7 jours → or vif, ≥3 → or chaud, sinon
/// or doux. Tap = no-op pour l'instant (vue détaillée Phase ultérieure).
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final accent = days >= 7
        ? AppColors.orSoleil
        : days >= 3
            ? AppColors.orChaud
            : AppColors.bois;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            days > 0 ? AppAssets.iconStreak : AppAssets.iconStreakBroken,
            width: 16,
            height: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '$days',
            style: AppTypography.bebas(size: 14, color: accent),
          ),
        ],
      ),
    );
  }
}

/// Chip altitude partagée via Hero (cf. hub_view, lobby_view, profile_view).
class _AltitudeHeroChip extends StatelessWidget {
  const _AltitudeHeroChip({required this.elo});

  final int elo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terrain, size: 14, color: AppColors.orSoleil),
          const SizedBox(width: 4),
          Text(
            '$elo m',
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
        ],
      ),
    );
  }
}

/// Chip générique avec icône (emoji ou widget) + valeur.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.value,
    this.icon,
    this.iconWidget,
    this.trailingPlus = false,
    this.onTap,
  }) : assert(
          icon != null || iconWidget != null,
          'Provide either icon (emoji) or iconWidget',
        );

  final String? icon;
  final Widget? iconWidget;
  final String value;
  final bool trailingPlus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget ?? Text(icon!, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            value,
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
          if (trailingPlus) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.add_circle,
              size: 16,
              color: AppColors.orSoleil.withValues(alpha: 0.85),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: body,
      ),
    );
  }
}
