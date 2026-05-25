import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart' show launchNextLevel;
import 'package:defi_kilimandjaro/presentation/home/providers/current_mountain_provider.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_silhouette_vector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Carte HERO « Continue ta montée » world-class.
///
/// Pièce maîtresse de l'accueil. Hauteur 200px, silhouette vectorielle
/// de la montagne en background, niveau N/total en Fraunces 56pt à droite,
/// progress bar épaisse avec gradient orChaud→orSoleil, glow doré autour
/// de la carte pour l'élévation premium.
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

  @override
  Widget build(BuildContext context) {
    final nextLevel = mountain.completedLevels + 1;
    final progress = mountain.progress;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            // Glow doré subtil autour de la carte premium.
            boxShadow: [
              BoxShadow(
                color: AppColors.orSoleil.withValues(alpha: 0.22),
                blurRadius: 24,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Background gradient diurne (ciel ocre → vert forêt).
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.orSoleil.withValues(alpha: 0.32),
                          AppColors.orChaud.withValues(alpha: 0.20),
                          AppColors.vertForet,
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                // Silhouette de la montagne en background, alignée bas.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 140,
                  child: Opacity(
                    opacity: 0.42,
                    child: MountainSilhouetteVector(
                      mountain: mountain,
                    ),
                  ),
                ),
                // Bordure or fine au-dessus du contenu.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppColors.orSoleil.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                // Contenu.
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top : badge MONT + nom + flag.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _PillBadge(
                                  text: 'CONTINUE TA MONTÉE',
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Text(
                                      mountain.flagEmoji,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'MONT ${mountain.name.toUpperCase()}',
                                        style: AppTypography.bebas(
                                          size: 18,
                                          color: AppColors.orSoleil,
                                          letterSpacing: 2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  mountain.countryName,
                                  style: AppTypography.crimson(
                                    size: 12,
                                    color: AppColors.texteSecondaire,
                                    style: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                            // Bottom : altitude + lifetime.
                            Row(
                              children: [
                                const Icon(
                                  Icons.terrain,
                                  size: 14,
                                  color: AppColors.orSoleil,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${mountain.altitude} m',
                                  style: AppTypography.bebas(
                                    size: 13,
                                    color: AppColors.textePrimaire,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '·  $totalLevelsLifetime niveaux',
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
                      // Niveau N en Fraunces très large à droite.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'NIVEAU',
                            style: AppTypography.bebas(
                              size: 11,
                              color: AppColors.texteSecondaire,
                              letterSpacing: 2,
                            ),
                          ),
                          RichText(
                            textAlign: TextAlign.right,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '$nextLevel',
                                  style: AppTypography.playfair(size: 56),
                                ),
                                TextSpan(
                                  text: ' / ${mountain.totalLevels}',
                                  style: AppTypography.playfair(
                                    size: 22,
                                    color: AppColors.texteSecondaire,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Progress bar arrondie épaisse.
                          SizedBox(
                            width: 120,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                children: [
                                  Container(
                                    height: 8,
                                    color: AppColors.boisFonce
                                        .withValues(alpha: 0.55),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    child: Container(
                                      height: 8,
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
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge pill doré pour le label en haut de la carte HERO.
class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.orSoleil,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTypography.bebas(
          size: 10,
          color: AppColors.vertForet,
          letterSpacing: 2,
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.orSoleil.withValues(alpha: 0.18),
                AppColors.bois.withValues(alpha: 0.16),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.orSoleil.withValues(alpha: 0.55),
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
