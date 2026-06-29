import 'dart:async';

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart'
    show launchNextLevel;
import 'package:defi_kilimandjaro/presentation/home/providers/current_mountain_provider.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Page « Grimper » — hub de jeu plein écran (benchmark : l'écran « Jouer »
/// de chess.com). Atteinte depuis le CTA sticky GRIMPER de l'accueil.
///
/// Structure : héros + **CTA primaire dominant** « Continuer l'ascension »
/// (solo), puis modes secondaires empilés (défis en ligne, tournoi, défier
/// un ami). La bottom nav reste pour la navigation latérale.
class GrimperView extends ConsumerWidget {
  const GrimperView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mountain = ref.watch(currentMountainProvider).valueOrNull;
    final hasMountain = mountain != null;

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: AppColors.orJour),
        title: Text('Grimper', style: AppTypography.headingLg),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Héros : pastille montagne dorée (équiv. du pion chess.com).
          Center(
            child: Container(
              width: 92,
              height: 92,
              margin: const EdgeInsets.only(top: 8, bottom: 24),
              decoration: BoxDecoration(
                color: AppColors.orJour.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.orJour.withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.terrain_rounded,
                size: 46,
                color: AppColors.orJour,
              ),
            ),
          ),

          // CTA PRIMAIRE — Continuer l'ascension (solo). Le bouton dominant.
          _PrimaryAscentButton(
            title: hasMountain
                ? "CONTINUER L'ASCENSION"
                : 'EXPLORER LES SOMMETS',
            subtitle: hasMountain
                ? 'Mont ${mountain.name} · Niveau '
                    '${mountain.completedLevels + 1}'
                : 'Choisis un versant à gravir',
            onTap: () {
              if (hasMountain) {
                unawaited(launchNextLevel(context, ref, mountain));
              } else {
                context.go(AppRoutes.mountains);
              }
            },
          ),
          const SizedBox(height: 18),

          // Modes secondaires empilés.
          _ModeRow(
            icon: Icons.public_rounded,
            accent: AppColors.kola,
            title: 'Défis en ligne',
            subtitle: 'Adversaire au hasard · ELO',
            onTap: () => context.go(AppRoutes.hub),
          ),
          const SizedBox(height: 10),
          _ModeRow(
            icon: Icons.emoji_events_rounded,
            accent: AppColors.orJour,
            title: 'Tournoi',
            subtitle: 'Arène — classement cauris',
            comingSoon: true,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.boisFonce,
                  content: Text(
                    'Tournoi — bientôt disponible',
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.textePrimaire),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _ModeRow(
            icon: Icons.people_alt_rounded,
            accent: AppColors.kola,
            title: 'Défier un ami',
            subtitle: 'Crée ou rejoins via QR',
            onTap: () => unawaited(context.push<void>(AppRoutes.duel)),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.accueil,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              context.go(AppRoutes.home);
            case NavTab.defi:
              context.go(AppRoutes.hub);
            case NavTab.sommets:
              context.go(AppRoutes.mountains);
            case NavTab.packs:
              context.go(AppRoutes.myPacks);
            case NavTab.profil:
              context.go(AppRoutes.profile);
          }
        },
      ),
    );
  }
}

/// Bouton primaire plein de la page : grande surface or, icône + titre +
/// sous-titre contextuel. Équivalent du « Commencer la partie » de chess.com.
class _PrimaryAscentButton extends StatelessWidget {
  const _PrimaryAscentButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.orJour,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.terrain, color: AppColors.surface, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bebas(
                        size: 20,
                        color: AppColors.surface,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.surface.withValues(alpha: 0.72),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.surface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne de mode secondaire : pastille d'icône teintée + titre + sous-titre +
/// affordance (chevron, ou badge « Bientôt »).
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.comingSoon = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: comingSoon ? 0.72 : 1,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 21, color: accent),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTypography.headingSm
                            .copyWith(color: AppColors.textePrimaire),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.texteSecondaire),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (comingSoon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.orJour,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'BIENTÔT',
                      style: AppTypography.labelXs
                          .copyWith(color: AppColors.boisFonce),
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.texteTertiaire,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
