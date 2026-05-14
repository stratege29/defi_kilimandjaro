import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Navigation bottom (cf. maquette §Composants p.2 et p.4).
///
/// 3 onglets sticky en bas · fond noir 60% · onglet actif souligné par une
/// **pill animée** (`AnimatedPositioned` 350 ms `easeOutCubic`, Wave Mobile
/// Money pattern). La pill glisse d'un onglet à l'autre quand `current`
/// change, ce qui donne immédiatement un feeling 2026.
enum NavTab { defi, sommets, profil }

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    required this.current,
    required this.onTabSelected,
    super.key,
  });

  final NavTab current;
  final ValueChanged<NavTab> onTabSelected;

  static const double _barHeight = 64;
  static const double _pillMarginH = 12;
  static const double _pillMarginV = 6;

  @override
  Widget build(BuildContext context) {
    final currentIdx = NavTab.values.indexOf(current);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(color: AppColors.orJour.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / NavTab.values.length;
              return Stack(
                children: [
                  // Pill indicator — glisse d'un onglet à l'autre.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    left: currentIdx * tabWidth + _pillMarginH,
                    top: _pillMarginV,
                    bottom: _pillMarginV,
                    width: tabWidth - 2 * _pillMarginH,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.orJour.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          (_barHeight - 2 * _pillMarginV) / 2,
                        ),
                        border: Border.all(
                          color: AppColors.orJour.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                  // Row d'onglets — au-dessus de la pill.
                  Row(
                    children: [
                      _NavItem(
                        assetPath: AppAssets.iconNavPlay,
                        label: 'Défi',
                        active: current == NavTab.defi,
                        onTap: () => onTabSelected(NavTab.defi),
                      ),
                      _NavItem(
                        assetPath: AppAssets.iconNavMap,
                        label: 'Sommets',
                        active: current == NavTab.sommets,
                        onTap: () => onTabSelected(NavTab.sommets),
                      ),
                      _NavItem(
                        assetPath: AppAssets.iconNavProfile,
                        label: 'Profil',
                        active: current == NavTab.profil,
                        onTap: () => onTabSelected(NavTab.profil),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.assetPath,
  }) : assert(
         icon != null || assetPath != null,
         'Provide either Material icon or PNG asset path',
       );

  final IconData? icon;
  final String? assetPath;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.orJour : AppColors.texteTertiaire;

    final iconWidget = assetPath != null
        ? AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: active ? 1 : 0.55,
            child: Image.asset(assetPath!, width: 28, height: 28),
          )
        : Icon(icon, color: color, size: 24);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // Pas de splash visible — la pill animée fait déjà le feedback.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWidget,
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: AppTypography.bebas(size: 12, color: color),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
