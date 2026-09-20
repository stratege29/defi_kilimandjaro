import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Lignes de bonus affichées sous la récompense de victoire, partagées par
/// `VictoryBanner` (niveau ordinaire) et `VictoryView` (boss / daily / fin de
/// montagne) :
/// - « Série ×N · cauris ×1,5 » quand le multiplicateur de série a joué ;
/// - « Sans faute +10 » quand aucun mot erroné n'a été formé ;
/// - « À main levée : +M inclus » (bonus de tracé propre).
///
/// Tous les montants sont **déjà inclus** dans le solde — purement
/// informatif. Rend `SizedBox.shrink` si rien n'est applicable.
class RewardBonusLines extends StatelessWidget {
  const RewardBonusLines({
    this.comboStreak = 0,
    this.comboMultiplier = 1.0,
    this.perfectBonus = 0,
    this.freehandBonus = 0,
    this.alignment = WrapAlignment.center,
    super.key,
  });

  final int comboStreak;
  final double comboMultiplier;
  final int perfectBonus;
  final int freehandBonus;
  final WrapAlignment alignment;

  /// Formatage français du multiplicateur : `1.5` → « 1,5 », `2.0` → « 2 ».
  static String formatMultiplier(double m) {
    final s = m.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return s.replaceFirst('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[
      if (comboMultiplier > 1)
        _BonusLine(
          icon: Icons.local_fire_department_rounded,
          color: AppColors.kola,
          label: 'Série ×$comboStreak · cauris ×${formatMultiplier(comboMultiplier)}',
        ),
      if (perfectBonus > 0)
        _BonusLine(
          icon: Icons.verified_rounded,
          color: AppColors.orJour,
          label: 'Sans faute +$perfectBonus',
        ),
      if (freehandBonus > 0)
        _BonusLine(
          icon: Icons.gesture_rounded,
          color: AppColors.success,
          label: 'result.victory.freehand_bonus'.tr(
            namedArgs: <String, String>{'cauris': '$freehandBonus'},
          ),
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: alignment,
      spacing: 14,
      runSpacing: 6,
      children: lines,
    );
  }
}

class _BonusLine extends StatelessWidget {
  const _BonusLine({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.labelSm.copyWith(
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
