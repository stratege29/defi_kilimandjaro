import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/world.dart';
import 'package:flutter/material.dart';

/// Carte d'un monde dans le Hub (cf. maquette p.4).
///
/// - Cartes débloquées : bois 22% opacity
/// - Cartes verrouillées : bois 12% opacity + icône cadenas
/// - Barre de progression : vert clair
class WorldCard extends StatelessWidget {
  const WorldCard({
    required this.world,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final World world;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bgColor = world.unlocked
        ? AppColors.bois.withValues(alpha: 0.22)
        : AppColors.bois.withValues(alpha: 0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                // Icône emoji
                _WorldEmoji(emoji: world.emoji, locked: !world.unlocked),
                const SizedBox(width: 14),
                // Nom + progression
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        world.name,
                        style: AppTypography.bebas(
                          size: 18,
                          color: world.unlocked
                              ? AppColors.ivoire
                              : AppColors.ivoire.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ProgressBar(
                        progress: world.progress,
                        completedLevels: world.completedLevels,
                        totalLevels: world.totalLevels,
                        unlocked: world.unlocked,
                      ),
                    ],
                  ),
                ),
                // Verrou ou flèche
                if (!world.unlocked)
                  _LockBadge(unlockCost: world.unlockCost)
                else
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.orSoleil,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorldEmoji extends StatelessWidget {
  const _WorldEmoji({required this.emoji, required this.locked});

  final String emoji;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.bois.withValues(alpha: locked ? 0.2 : 0.4),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: locked ? 0.3 : 0.7),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(
            fontSize: 26,
            color: locked ? Colors.white24 : null,
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.completedLevels,
    required this.totalLevels,
    required this.unlocked,
  });

  final double progress;
  final int completedLevels;
  final int totalLevels;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: unlocked ? progress : 0,
            minHeight: 6,
            backgroundColor: AppColors.boisFonce.withValues(alpha: 0.5),
            valueColor: const AlwaysStoppedAnimation(AppColors.vertClair),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$completedLevels / $totalLevels',
          style: AppTypography.crimson(
            size: 12,
            color: AppColors.ivoire.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.unlockCost});

  final int unlockCost;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock, color: AppColors.orSoleil, size: 22),
        const SizedBox(height: 2),
        Text(
          '$unlockCost',
          style: AppTypography.bebas(size: 12, color: AppColors.orSoleil),
        ),
      ],
    );
  }
}
