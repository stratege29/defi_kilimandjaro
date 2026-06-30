import 'dart:ui';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Navigation bottom (cf. maquette §Composants p.2 et p.4).
///
/// Barre flottante façon maquette Vert Nuit : conteneur arrondi avec une
/// **bordure hairline tout autour**, posé au-dessus de la safe area. L'onglet
/// actif n'a **pas de bordure** — il est signalé par un squircle doré discret
/// derrière l'icône (fond `orJour` @ 14 %) + icône/label en or. Les inactifs
/// restent sobres (texte tertiaire).
/// Onglets de la barre : Accueil · Défi · Sommets · Packs · Profil. L'onglet
/// `defi` ouvre la page Défi (`DuelHubView`). Le CTA sticky GRIMPER de l'accueil
/// reste un raccourci de jeu (solo/tournoi/ami + matchmaking direct), mais ne
/// duplique plus la page Défi.
enum NavTab { accueil, defi, sommets, packs, profil }

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    required this.current,
    required this.onTabSelected,
    super.key,
  });

  final NavTab current;
  final ValueChanged<NavTab> onTabSelected;

  static const double _barHeight = 72;
  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    // Frosted glass : BackdropFilter blur 18 sur le contenu sous la nav,
    // puis tint vertForet @ 65 % par-dessus pour préserver l'identité
    // colorimétrique et garantir le contraste des labels.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: _barHeight,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  _NavItem(
                    // Placeholder Material : pas encore de PNG dédié
                    // dans assets/images/icons/. Voir `iconNavPlay`
                    // pour le style cible à reproduire.
                    icon: Icons.home_rounded,
                    label: 'Accueil',
                    active: current == NavTab.accueil,
                    onTap: () => onTabSelected(NavTab.accueil),
                  ),
                  _NavItem(
                    icon: Icons.bolt,
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
                    // Placeholder Material : pas encore de PNG dédié dans
                    // assets/images/icons/ (cf. `iconNavPlay` pour le style cible).
                    icon: Icons.style_rounded,
                    label: 'Packs',
                    active: current == NavTab.packs,
                    onTap: () => onTabSelected(NavTab.packs),
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
          // Pas de splash visible — le squircle doré fait déjà le feedback.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Squircle doré derrière l'icône active — sans bordure.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 48,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.orJour.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: iconWidget,
                ),
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
