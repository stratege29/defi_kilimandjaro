import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/section_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Trio de cartes statistiques compactes : sommets · duels · précision.
///
/// Chiffres en Fraunces 28 (signature éditoriale premium type Apple/Stripe),
/// labels en Crimson italique. Fond surfaceContainer avec gradient diagonal
/// pour la profondeur, accent or sur l'icône.
class StatsRow extends ConsumerWidget {
  const StatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final mountainsAsync = ref.watch(mountainsProvider);

    final mountains = mountainsAsync.value ?? const [];
    final conquered = mountains
        .where((m) => progress.levelsOn(m.id) >= m.totalLevels)
        .length;
    final wins = profileAsync.value?.wins ?? 0;
    final winRate = profileAsync.value?.winRate;
    final accuracy = winRate == null ? '—' : '${(winRate * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'STATISTIQUES'),
        Row(
          children: [
            Expanded(
              child: _StatSquare(
                icon: Icons.terrain,
                value: '$conquered',
                label: 'Sommets',
                onTap: () => context.go(AppRoutes.profile),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatSquare(
                icon: Icons.bolt,
                value: '$wins',
                label: 'Duels gagnés',
                onTap: () => context.go(AppRoutes.profile),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatSquare(
                icon: Icons.center_focus_strong,
                value: accuracy,
                label: 'Précision',
                onTap: () => context.go(AppRoutes.profile),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatSquare extends StatelessWidget {
  const _StatSquare({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.surfaceContainer.withValues(alpha: 0.55),
                AppColors.surfaceContainer.withValues(alpha: 0.25),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.orSoleil.withValues(alpha: 0.32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.orSoleil.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.orSoleil, size: 16),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: AppTypography.playfair(
                    size: 26,
                    color: AppColors.textePrimaire,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.crimson(
                  size: 11,
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
