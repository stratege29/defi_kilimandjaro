import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/home/home_view.dart'
    show launchNextLevel;
import 'package:defi_kilimandjaro/presentation/home/providers/current_mountain_provider.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/quickmatch_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Barre sticky d'actions principales : GRIMPER (primaire avec shimmer
/// animé) + DÉFIER (secondaire outline).
///
/// Pondération flex selon profil joueur :
/// - Nouveau joueur (0 niveau) : GRIMPER 100 %.
/// - ELO < 1100 et sommet en cours : 70/30.
/// - Tous sommets gravis : DÉFIER 70/30 (GRIMPER → liste sommets).
/// - Par défaut : 50/50.
class StickyCtaBar extends ConsumerWidget {
  const StickyCtaBar({super.key});

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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.orSoleil.withValues(alpha: 0.30),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (grimperFlex > 0)
            Expanded(
              flex: grimperFlex,
              child: _PrimaryCtaButton(
                icon: Icons.terrain,
                label: 'GRIMPER',
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
              child: _SecondaryCtaButton(
                icon: Icons.bolt,
                label: 'DÉFIER',
                onTap: () => showQuickmatchOverlay(context),
              ),
            ),
        ],
      ),
    );
  }
}

/// CTA primaire : fond plein orSoleil, texte foncé vertForet, shimmer
/// doré qui traverse en diagonale toutes les 3.5s (effet premium type
/// jeu mobile AAA).
class _PrimaryCtaButton extends StatefulWidget {
  const _PrimaryCtaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PrimaryCtaButton> createState() => _PrimaryCtaButtonState();
}

class _PrimaryCtaButtonState extends State<_PrimaryCtaButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.orSoleil.withValues(alpha: 0.42),
                blurRadius: 22,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AnimatedBuilder(
              animation: _shimmer,
              builder: (_, __) {
                // Shimmer : gradient diagonal qui traverse de gauche à droite.
                final t = _shimmer.value;
                return DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.orSoleil,
                        AppColors.orChaud,
                        AppColors.orSoleil,
                      ],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Shimmer translucide diagonal qui glisse.
                      Positioned.fill(
                        child: ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment(-1.5 + t * 3, -1),
                              end: Alignment(-0.5 + t * 3, 1),
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.32),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.5, 1],
                            ).createShader(rect);
                          },
                          child: Container(color: AppColors.orSoleil),
                        ),
                      ),
                      // Contenu (icon + label) au-dessus du shimmer.
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.icon,
                              color: AppColors.vertForet,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.label,
                                  style: AppTypography.bebas(
                                    size: 20,
                                    color: AppColors.vertForet,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// CTA secondaire : outline vertClair, fond quasi-transparent.
class _SecondaryCtaButton extends StatelessWidget {
  const _SecondaryCtaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
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
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.vertClair.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.vertClair, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.vertClair, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: AppTypography.bebas(
                      size: 18,
                      color: AppColors.vertClair,
                      letterSpacing: 2,
                    ),
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
