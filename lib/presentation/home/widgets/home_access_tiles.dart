import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart'
    show launchDailyChallenge;
import 'package:defi_kilimandjaro/presentation/home/widgets/quickmatch_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Zone 3 de l'accueil — tuiles d'accès rapide façon maquette Vert Nuit.
///
/// Grille 2×2 de tuiles carrées : « Défier en ligne » (matchmaking ELO) et
/// « Défier un ami » (QR) en première rangée, puis « Défi du jour » et
/// « Sommets ». Surfaces opaques `surfaceContainer`, bordures hairline,
/// pastilles d'icône teintées par fonction (kola = duel, info = quotidien,
/// or = ascension).
class HomeAccessTiles extends ConsumerWidget {
  const HomeAccessTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final mountainsAsync = ref.watch(mountainsProvider);
    final playedToday = DailyChallengeService.isPlayedOn(
      progress: progress,
      date: DateTime.now(),
    );

    final (conquered, total) = mountainsAsync.maybeWhen(
      data: (mountains) => (
        mountains.where((m) => m.completedLevels >= m.totalLevels).length,
        mountains.length,
      ),
      orElse: () => (0, 0),
    );

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SquareTile(
                  icon: Icons.public_rounded,
                  accent: AppColors.kola,
                  title: 'Défier en ligne',
                  subtitle: 'Adversaire au hasard',
                  onTap: () => showQuickmatchOverlay(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SquareTile(
                  icon: Icons.people_alt_rounded,
                  accent: AppColors.kola,
                  title: 'Défier un ami',
                  subtitle: 'Crée ou rejoins via QR',
                  onTap: () => context.push(AppRoutes.duel),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SquareTile(
                  icon: Icons.bolt_rounded,
                  accent: AppColors.info,
                  title: 'Défi du jour',
                  subtitle: playedToday
                      ? "Fait aujourd'hui"
                      : '+${DailyChallengeService.rewardCauris} cauris',
                  onTap: () => launchDailyChallenge(context, ref),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SquareTile(
                  icon: Icons.terrain_rounded,
                  accent: AppColors.orJour,
                  title: 'Sommets',
                  subtitle: total == 0
                      ? 'Explorer la carte'
                      : '$conquered / $total conquis',
                  onTap: () => context.go(AppRoutes.mountains),
                ),
              ),
            ],
          ),
        ),
      ],
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

/// Tuile carrée d'une rangée (icône en haut, texte en bas).
class _SquareTile extends StatelessWidget {
  const _SquareTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      minHeight: 96,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconBadge(icon: icon, accent: accent),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTypography.headingSm
                .copyWith(color: AppColors.textePrimaire),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style:
                AppTypography.bodySm.copyWith(color: AppColors.texteTertiaire),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Conteneur commun des tuiles : surface opaque, bordure hairline, ripple.
class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.child,
    required this.onTap,
    this.minHeight = 0,
  });

  final Widget child;
  final VoidCallback onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.all(16),
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
