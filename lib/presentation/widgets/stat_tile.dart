import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Tuile statistique — grande valeur Fraunces + libellé court en capitales.
///
/// Brique des grilles de stats (Profil 2×2, hub Défi, écran de fin). La
/// valeur prend la couleur d'accent fournie (défaut : or), le libellé reste
/// en texte tertiaire.
///
/// Usage : `StatTile(value: '24', label: 'Victoires', accent: AppColors.success)`.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.value,
    required this.label,
    this.accent = AppColors.orJour,
    super.key,
  });

  /// Valeur affichée (chiffre, score, altitude…).
  final String value;

  /// Libellé court (affiché en capitales).
  final String label;

  /// Couleur d'accent de la valeur. Défaut : or.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md - 2,
        vertical: AppSpacing.md - 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.displaySm.copyWith(
              fontSize: 24,
              color: accent,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          Text(
            label.toUpperCase(),
            style: AppTypography.labelXs.copyWith(
              color: AppColors.texteTertiaire,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
