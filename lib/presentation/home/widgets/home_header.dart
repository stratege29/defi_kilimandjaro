import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/daily_streak_service.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Header épuré du Hub d'Accueil (maquette Vert Nuit).
///
/// Deux pastilles seulement : série quotidienne à gauche · solde de cauris
/// à droite (tap → recharge). Fond `surface` + séparation hairline discrète
/// pour poser une 1ʳᵉ strate de profondeur sans surcharge.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final streakAsync = ref.watch(dailyStreakProvider);
    final streak = streakAsync.value ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Row(
        children: [
          _StreakChip(days: streak),
          const Spacer(),
          _HeaderChip(
            iconWidget: const CaurisIcon(size: 16),
            value: '${progress.cauris}',
            trailingPlus: true,
            onTap: () => context.push(AppRoutes.shop),
          ),
        ],
      ),
    );
  }
}

/// Chip série : flamme pulsée animée + nombre. Couleur dérivée du palier.
class _StreakChip extends StatefulWidget {
  const _StreakChip({required this.days});
  final int days;

  @override
  State<_StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends State<_StreakChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final accent = days >= 7
        ? AppColors.orSoleil
        : days >= 3
            ? AppColors.orChaud
            : AppColors.bois;
    final active = days > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.08).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Image.asset(
              active ? AppAssets.iconStreak : AppAssets.iconStreakBroken,
              width: 16,
              height: 16,
            ),
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

/// Chip header générique avec icône (emoji ou widget) + valeur.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.value,
    this.iconWidget,
    this.trailingPlus = false,
    this.onTap,
  });

  final Widget? iconWidget;
  final String value;
  final bool trailingPlus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceContainer.withValues(alpha: 0.70),
            AppColors.surfaceContainer.withValues(alpha: 0.40),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconWidget != null) iconWidget!,
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
