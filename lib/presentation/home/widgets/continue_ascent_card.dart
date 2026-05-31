import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart' show launchNextLevel;
import 'package:defi_kilimandjaro/presentation/home/providers/current_mountain_provider.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_silhouette_vector.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/mountain_hero_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Carte HERO « Continuer l'ascension » — pièce maîtresse de l'accueil.
///
/// Layout vertical façon maquette Vert Nuit : eyebrow doré, numéro de niveau
/// en Fraunces XL, nom du sommet, méta (niveau / total · altitude), barre de
/// progression pleine largeur, puis le CTA GRIMPER intégré dans la carte.
/// La peinture du sommet déborde discrètement depuis le bord droit.
/// Élévation par surface opaque + une seule ombre noire (pas de glow coloré),
/// la chaleur dorée venant d'un radial subtil dans le fond.
class ContinueAscentCard extends ConsumerWidget {
  const ContinueAscentCard({super.key});

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

  /// Formate une altitude en mètres avec une espace fine comme séparateur
  /// de milliers (1752 → « 1 752 »), façon maquette.
  static String _formatAltitude(int alt) {
    final s = alt.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)} ${s.substring(s.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    final nextLevel = mountain.completedLevels + 1;
    final progress = mountain.progress;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Radial doré discret en haut à droite (seule chaleur de la carte).
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -0.9),
                    radius: 1.05,
                    colors: [
                      AppColors.orJour.withValues(alpha: 0.18),
                      AppColors.orJour.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.55],
                  ),
                ),
              ),
            ),
            // Peinture du sommet en cours, débordant depuis le bord droit
            // (repli : silhouette vectorielle pour les sommets sans hero).
            Positioned(
              right: -14,
              top: 2,
              height: 150,
              width: 150,
              child: MountainHeroImage(
                mountainId: mountain.id,
                alignment: Alignment.topRight,
                opacity: 0.85,
                fallback: Align(
                  alignment: Alignment.topRight,
                  child: Opacity(
                    opacity: 0.42,
                    child: MountainSilhouetteVector(mountain: mountain),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CONTINUER L'ASCENSION",
                    style: AppTypography.bebas(
                      size: 12,
                      color: AppColors.orJour,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nextLevel.toString().padLeft(2, '0'),
                    style: AppTypography.displayLg.copyWith(
                      color: AppColors.orJour,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MONT ${mountain.name.toUpperCase()}',
                    style: AppTypography.headingMd.copyWith(letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Niveau $nextLevel / ${mountain.totalLevels}  ·  '
                    '${_formatAltitude(mountain.altitude)} m',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.texteSecondaire,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Barre de progression pleine largeur.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      children: [
                        Container(
                          height: 7,
                          color: Colors.black.withValues(alpha: 0.35),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 7,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.orChaud,
                                  AppColors.orSoleil,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'GRIMPER',
                    icon: Icons.terrain,
                    fullWidth: true,
                    onPressed: onTap,
                  ),
                ],
              ),
            ),
          ],
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
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.surfaceContainer,
                AppColors.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.orSoleil.withValues(alpha: 0.30),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOUS LES SOMMETS GRAVIS',
                style: AppTypography.bebas(
                  size: 18,
                  color: AppColors.orSoleil,
                  letterSpacing: 2,
                ),
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
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}
