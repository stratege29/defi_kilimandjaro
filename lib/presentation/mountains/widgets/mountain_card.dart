import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:flutter/material.dart';

/// IDs de montagnes pour lesquelles une illustration hero a été générée.
const Set<String> _heroIds = {
  'ci_nimba',
  'cm_cameroon',
  'ma_toubkal',
  'et_ras_dashen',
  'ke_mount_kenya',
  'ug_stanley',
  'tz_kilimanjaro',
};

/// Sélectionne le biome (1-4) depuis l'altitude.
int _biomeTier(int altitudeM) {
  if (altitudeM < 1000) return 1;
  if (altitudeM < 2500) return 2;
  if (altitudeM < 4000) return 3;
  return 4;
}

/// Renvoie l'asset à afficher : hero si disponible, sinon biome par altitude.
String _illustrationFor(Mountain m) {
  if (_heroIds.contains(m.id)) return AppAssets.mountainHero(m.id);
  return AppAssets.mountainBiome(_biomeTier(m.altitude));
}

/// Carte d'une montagne africaine dans la liste de progression.
///
/// Visuellement : drapeau pays + nom montagne + altitude + barre progression.
/// Verrouillée → opacité réduite + cadenas + altitude masquée derrière "▒▒".
class MountainCard extends StatelessWidget {
  const MountainCard({
    required this.mountain,
    required this.rank,
    required this.onTap,
    super.key,
  });

  final Mountain mountain;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = mountain.unlocked;
    final completed = mountain.completedLevels >= mountain.totalLevels &&
        mountain.totalLevels > 0;

    final bgColor = completed
        ? AppColors.vertClair.withValues(alpha: 0.15)
        : unlocked
            ? AppColors.bois.withValues(alpha: 0.22)
            : AppColors.bois.withValues(alpha: 0.10);

    final borderColor = completed
        ? AppColors.vertClair.withValues(alpha: 0.6)
        : unlocked
            ? AppColors.orSoleil.withValues(alpha: 0.4)
            : AppColors.orSoleil.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                _RankBadge(rank: rank, locked: !unlocked),
                const SizedBox(width: 12),
                _MountainAvatar(
                  illustration: _illustrationFor(mountain),
                  flagEmoji: mountain.flagEmoji,
                  locked: !unlocked,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mountain.name,
                        style: AppTypography.bebas(
                          size: 17,
                          color: unlocked
                              ? AppColors.ivoire
                              : AppColors.ivoire.withValues(alpha: 0.4),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mountain.countryName,
                        style: AppTypography.crimson(
                          size: 12,
                          color: AppColors.ivoire.withValues(alpha: 0.6),
                          style: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _ProgressBar(mountain: mountain),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _AltitudeBadge(
                  altitude: mountain.altitude,
                  locked: !unlocked,
                  completed: completed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.locked});
  final int rank;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        '#$rank',
        style: AppTypography.bebas(
          size: 14,
          color: locked
              ? AppColors.orSoleil.withValues(alpha: 0.3)
              : AppColors.orSoleil.withValues(alpha: 0.7),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _MountainAvatar extends StatelessWidget {
  const _MountainAvatar({
    required this.illustration,
    required this.flagEmoji,
    required this.locked,
  });

  final String illustration;
  final String flagEmoji;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.bois.withValues(alpha: locked ? 0.15 : 0.35),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: locked ? 0.2 : 0.6),
          width: 1.4,
        ),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Illustration (silhouette + couleurs).
            Padding(
              padding: const EdgeInsets.all(3),
              child: Opacity(
                opacity: locked ? 0.35 : 1,
                child: Image.asset(illustration, fit: BoxFit.cover),
              ),
            ),
            // Drapeau pays — petit overlay coin bas-droit.
            Positioned(
              right: 2,
              bottom: 0,
              child: Opacity(
                opacity: locked ? 0.4 : 1,
                child: Text(flagEmoji, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AltitudeBadge extends StatelessWidget {
  const _AltitudeBadge({
    required this.altitude,
    required this.locked,
    required this.completed,
  });

  final int altitude;
  final bool locked;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.vertClair
        : locked
            ? AppColors.ivoire.withValues(alpha: 0.3)
            : AppColors.orSoleil;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (locked)
          Icon(Icons.lock, size: 16, color: color)
        else
          Text(
            '$altitude',
            style: AppTypography.bebas(size: 18, color: color),
          ),
        Text(
          'm',
          style: AppTypography.crimson(size: 11, color: color),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.mountain});
  final Mountain mountain;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: mountain.unlocked ? mountain.progress : 0,
              minHeight: 5,
              backgroundColor: AppColors.boisFonce.withValues(alpha: 0.5),
              valueColor: const AlwaysStoppedAnimation(AppColors.vertClair),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${mountain.completedLevels}/${mountain.totalLevels}',
          style: AppTypography.crimson(
            size: 11,
            color: AppColors.ivoire.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
