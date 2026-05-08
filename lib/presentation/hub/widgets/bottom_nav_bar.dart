import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Navigation bottom (cf. maquette §Composants p.2 et p.4).
///
/// 3 onglets sticky en bas · fond noir 60% · onglet actif en or.
enum NavTab { jouer, afrique, profil }

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    required this.current,
    required this.onTabSelected,
    super.key,
  });

  final NavTab current;
  final ValueChanged<NavTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(
            color: AppColors.orSoleil.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              assetPath: AppAssets.iconNavPlay,
              label: 'Jouer',
              active: current == NavTab.jouer,
              onTap: () => onTabSelected(NavTab.jouer),
            ),
            _NavItem(
              assetPath: AppAssets.iconNavMap,
              label: 'Afrique',
              active: current == NavTab.afrique,
              onTap: () => onTabSelected(NavTab.afrique),
            ),
            _NavItem(
              assetPath: AppAssets.iconNavProfile,
              label: 'Profil',
              active: current == NavTab.profil,
              onTap: () => onTabSelected(NavTab.profil),
            ),
          ],
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
    final color = active
        ? AppColors.orSoleil
        : AppColors.ivoire.withValues(alpha: 0.5);

    final iconWidget = assetPath != null
        ? Opacity(
            opacity: active ? 1 : 0.55,
            child: Image.asset(assetPath!, width: 28, height: 28),
          )
        : Icon(icon, color: color, size: 24);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTypography.bebas(size: 12, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
