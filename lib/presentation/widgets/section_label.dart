import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// En-tête de section — libellé court en capitales + filet hairline.
///
/// Remplace les multiples patterns ad-hoc « titre + ligne dorée » des écrans
/// Profil / Boutique / Défi. Le filet s'étend sur l'espace restant.
///
/// Usage : `SectionLabel('Derniers duels')`, `SectionLabel('Montagnes gravies')`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {this.trailing, super.key});

  /// Texte de la section (affiché en capitales).
  final String label;

  /// Widget optionnel aligné à droite après le filet (ex. lien « Voir tout »).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelSm.copyWith(
            color: AppColors.texteSecondaire,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(child: Divider(color: AppColors.hairline, height: 1)),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}
