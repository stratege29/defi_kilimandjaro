import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Niveau d'élévation d'une [AppCard].
enum AppCardElevation {
  /// Niveau 0 — surface plate, listes, stat boxes.
  /// bg: [AppColors.surfaceVariant], r:12, border discret, pas d'ombre.
  flat,

  /// Niveau 1 — carte interactive, RiddleCard, DuelButton.
  /// bg: [AppColors.surfaceContainer], r:14, border or @50%, shadow modeste.
  raised,

  /// Niveau 2 — overlay plein écran, VictoryView, ConquestView.
  /// bg: [AppColors.surfaceContainer], r:20, border or pleine, double shadow.
  modal,
}

/// Carte unifiée Kilimandjaro — design system 2026.
///
/// Système à **3 niveaux d'élévation** explicites ([AppCardElevation]).
/// Chaque niveau a son rayon, son fond opaque (pas d'alpha), son border
/// et son ombre. Pour les overlays modaux, le `BackdropFilter` du barrier
/// doit être appliqué côté `showDialog` (pas dans la card).
///
/// Si [onTap] est fourni, toute la card devient tappable (avec opacity
/// ripple via `InkWell`).
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.elevation = AppCardElevation.flat,
    this.padding,
    this.onTap,
    this.borderColor,
    super.key,
  });

  /// Contenu de la card.
  final Widget child;

  /// Niveau d'élévation, défaut [AppCardElevation.flat].
  final AppCardElevation elevation;

  /// Padding interne. Défaut : `AppSpacing.cardAll` (16pt).
  final EdgeInsets? padding;

  /// Callback de tap. Si fourni, la card devient cliquable avec ripple.
  final VoidCallback? onTap;

  /// Override de la couleur de bordure. Défaut : selon [elevation].
  final Color? borderColor;

  _Decoration _decoration() {
    switch (elevation) {
      case AppCardElevation.flat:
        return _Decoration(
          bg: AppColors.surfaceVariant,
          radius: 16,
          border: borderColor ?? AppColors.texteDisabled.withValues(alpha: 0.35),
          borderWidth: 1,
          shadow: null,
        );
      case AppCardElevation.raised:
        return _Decoration(
          bg: AppColors.surfaceContainer,
          radius: 16,
          border: borderColor ?? AppColors.orJour.withValues(alpha: 0.25),
          borderWidth: 1.2,
          shadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case AppCardElevation.modal:
        return _Decoration(
          bg: AppColors.surfaceContainer.withValues(alpha: 0.90),
          radius: 24,
          border: borderColor ?? AppColors.orJour.withValues(alpha: 0.45),
          borderWidth: 1.5,
          shadow: [
            BoxShadow(
              color: AppColors.orJour.withValues(alpha: 0.12),
              blurRadius: 32,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _decoration();
    final radius = BorderRadius.circular(d.radius);

    final body = Container(
      padding: padding ?? AppSpacing.cardAll,
      decoration: BoxDecoration(
        color: d.bg,
        borderRadius: radius,
        border: Border.all(color: d.border, width: d.borderWidth),
        boxShadow: d.shadow,
      ),
      child: child,
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.orJour.withValues(alpha: 0.15),
        highlightColor: AppColors.orJour.withValues(alpha: 0.08),
        child: body,
      ),
    );
  }
}

class _Decoration {
  const _Decoration({
    required this.bg,
    required this.radius,
    required this.border,
    required this.borderWidth,
    required this.shadow,
  });

  final Color bg;
  final double radius;
  final Color border;
  final double borderWidth;
  final List<BoxShadow>? shadow;
}
