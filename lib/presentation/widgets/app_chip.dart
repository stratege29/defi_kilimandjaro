import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Forme géométrique d'un [AppChip].
enum AppChipShape {
  /// Rayon maximal (cercle aux extrémités). Pour monnaies, ELO, niveaux.
  /// px:12 py:5 r:100.
  pill,

  /// Faible rayon, tag rectangulaire. Pour mondes, zones, catégories.
  /// px:10 py:4 r:6.
  tag,

  /// Rayon moyen, fond solide marqué. Pour titres honorifiques actifs.
  /// px:10 py:4 r:8.
  badge,
}

/// Tonalité chromatique d'un [AppChip] — détermine le fond doux, la bordure
/// et la couleur du label.
enum AppChipTone { primary, secondary, success, warning, error, info }

/// Chip unifié Kilimandjaro — design system 2026.
///
/// Famille à **3 formes** × **6 tonalités**. Remplace les 6+ patterns ad-hoc
/// répertoriés dans l'audit (`_CaurisChip`, `_WorldBanner`, `_RewardedAdChip`,
/// `_AltitudeHeroChip`, etc.).
///
/// API :
/// - `AppChip(label: 'Trésor', shape: AppChipShape.pill, tone: AppChipTone.primary)`
/// - Avec leading icon : `AppChip(label: '120', leading: CaurisIcon(size: 14))`
/// - Tappable : passer `onTap` non nul.
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    this.shape = AppChipShape.pill,
    this.tone = AppChipTone.primary,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// Texte du chip.
  final String label;

  /// Forme géométrique, défaut [AppChipShape.pill].
  final AppChipShape shape;

  /// Tonalité chromatique, défaut [AppChipTone.primary] (or jour).
  final AppChipTone tone;

  /// Widget placé avant le label (icône, emoji, mini avatar).
  final Widget? leading;

  /// Widget placé après le label.
  final Widget? trailing;

  /// Callback de tap. Si non nul, le chip devient interactif.
  final VoidCallback? onTap;

  _ChipTone _toneColors() {
    switch (tone) {
      case AppChipTone.primary:
        return const _ChipTone(
          fg: AppColors.orJour,
          bg: AppColors.surfaceContainer,
          border: AppColors.orJour,
        );
      case AppChipTone.secondary:
        return const _ChipTone(
          fg: AppColors.texteSecondaire,
          bg: AppColors.surfaceVariant,
          border: AppColors.texteDisabled,
        );
      case AppChipTone.success:
        return const _ChipTone(
          fg: AppColors.success,
          bg: AppColors.successSoft,
          border: AppColors.success,
        );
      case AppChipTone.warning:
        return const _ChipTone(
          fg: AppColors.warning,
          bg: AppColors.warningSoft,
          border: AppColors.warning,
        );
      case AppChipTone.error:
        return const _ChipTone(
          fg: AppColors.error,
          bg: AppColors.errorSoft,
          border: AppColors.error,
        );
      case AppChipTone.info:
        return const _ChipTone(
          fg: AppColors.info,
          bg: AppColors.infoSoft,
          border: AppColors.info,
        );
    }
  }

  _ChipShapeSpec _shapeSpec() {
    switch (shape) {
      case AppChipShape.pill:
        return const _ChipShapeSpec(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          radius: 100,
          textStyle: null, // labelSm
          solidBg: false,
        );
      case AppChipShape.tag:
        return const _ChipShapeSpec(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          radius: 6,
          textStyle: null, // labelXs
          solidBg: false,
        );
      case AppChipShape.badge:
        return const _ChipShapeSpec(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          radius: 8,
          textStyle: null, // labelSm
          solidBg: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = _toneColors();
    final spec = _shapeSpec();
    final textStyle = shape == AppChipShape.tag
        ? AppTypography.labelXs.copyWith(color: tones.fg)
        : AppTypography.labelSm.copyWith(color: tones.fg);

    // Badge solid = fond = couleur fg (avec label en surface foncée).
    final bg = spec.solidBg ? tones.fg : tones.bg;
    final labelColor = spec.solidBg ? AppColors.surface : tones.fg;

    final body = Container(
      padding: spec.padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(spec.radius),
        border: spec.solidBg ? null : Border.all(color: tones.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, AppSpacing.hGapXs],
          Text(label, style: textStyle.copyWith(color: labelColor)),
          if (trailing != null) ...[AppSpacing.hGapXs, trailing!],
        ],
      ),
    );

    if (onTap == null) return body;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

class _ChipTone {
  const _ChipTone({required this.fg, required this.bg, required this.border});
  final Color fg;
  final Color bg;
  final Color border;
}

class _ChipShapeSpec {
  const _ChipShapeSpec({
    required this.padding,
    required this.radius,
    required this.textStyle,
    required this.solidBg,
  });

  final EdgeInsets padding;
  final double radius;
  final TextStyle? textStyle;
  final bool solidBg;
}
