import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart'
    show launchDailyChallenge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Zone 2 de l'accueil — désormais une **bande unique « Défi du jour »**.
///
/// Les anciens accès rapides (défier en ligne, défier un ami, sommets) ont
/// migré : en ligne/ami vivent dans la feuille du CTA sticky GRIMPER, les
/// sommets dans la bottom nav. Ne reste ici que le rituel quotidien, gardé
/// visible pour son caractère temporel (FOMO + série).
class HomeAccessTiles extends ConsumerWidget {
  const HomeAccessTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final playedToday = DailyChallengeService.isPlayedOn(
      progress: progress,
      date: DateTime.now(),
    );

    return _TileShell(
      onTap: () => launchDailyChallenge(context, ref),
      child: Row(
        children: [
          const _IconBadge(icon: Icons.bolt_rounded, accent: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Défi du jour',
                  style: AppTypography.headingSm
                      .copyWith(color: AppColors.textePrimaire),
                ),
                const SizedBox(height: 2),
                Text(
                  playedToday
                      ? "Fait aujourd'hui"
                      : '+${DailyChallengeService.rewardCauris} cauris',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.texteTertiaire),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            playedToday
                ? Icons.check_circle_rounded
                : Icons.chevron_right_rounded,
            color: playedToday ? AppColors.vertClair : AppColors.texteTertiaire,
          ),
        ],
      ),
    );
  }
}

/// Pastille d'icône carrée 34×34 teintée par fonction.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}

/// Conteneur commun : surface opaque, bordure hairline, ripple.
class _TileShell extends StatelessWidget {
  const _TileShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline),
          ),
          child: child,
        ),
      ),
    );
  }
}
