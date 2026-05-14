import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Variante visuelle du bouton.
enum AppButtonVariant {
  /// CTA principal : fond [AppColors.orJour], texte sombre, shadow doré.
  /// h:56 r:12 — usage : Gravir, Suivant, Prochaine montagne.
  primary,

  /// CTA secondaire : outlined or, fond transparent.
  /// h:52 r:10 — usage : Annuler, Continuer, actions non-engageantes.
  secondary,

  /// Action discrète : transparent + texte secondaire.
  /// h:44 r:8 — usage : Retour, Skip, liens textuels.
  ghost,

  /// Action destructive ou de fort warning : `errorSoft` + border `error`.
  /// h:52 r:10 — usage : Quitter la partie, supprimer un ami.
  danger,
}

/// Bouton unifié Kilimandjaro — design system 2026.
///
/// **4 variants** : primary / secondary / ghost / danger.
///
/// **4 états systémiques** :
/// - `idle` — état normal
/// - `pressed` — `Transform.scale(0.96)` 100 ms easeOut + haptique
///   `selectionClick` au tap-down
/// - `disabled` — `Opacity(0.38)` et `onPressed: null`, no tap, no haptic
/// - `loading` — label remplacé par `CircularProgressIndicator` 20×20pt
///
/// Le widget gère seul son `AnimationController` (single ticker). Toutes
/// les couleurs viennent de la palette 2026 sémantique ([AppColors.orJour],
/// [AppColors.error], etc.), toutes les tailles de la grille 8pt.
class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.iconAsset,
    this.loading = false,
    this.fullWidth = false,
    super.key,
  });

  /// Texte affiché dans le bouton.
  final String label;

  /// Callback de tap. `null` désactive le bouton (état disabled).
  final VoidCallback? onPressed;

  /// Variante visuelle, défaut [AppButtonVariant.primary].
  final AppButtonVariant variant;

  /// Icône Material optionnelle placée avant le label.
  final IconData? icon;

  /// Asset PNG optionnel placé avant le label (alternative à [icon]).
  final String? iconAsset;

  /// Si vrai, remplace le label par un spinner et désactive l'interaction.
  final bool loading;

  /// Si vrai, le bouton occupe toute la largeur disponible.
  final bool fullWidth;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value: 1,
      lowerBound: 0.96,
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _onTapDown(TapDownDetails _) {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
    _scale.animateTo(0.96, curve: Curves.easeOut);
  }

  void _onTapUp(TapUpDetails _) {
    _scale.animateTo(1, curve: Curves.easeOut);
  }

  void _onTapCancel() {
    _scale.animateTo(1, curve: Curves.easeOut);
  }

  _ButtonStyle _styleFor(AppButtonVariant v) {
    switch (v) {
      case AppButtonVariant.primary:
        return _ButtonStyle(
          bg: AppColors.orJour,
          fg: AppColors.surface,
          height: 56,
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shadow: [
            BoxShadow(
              color: AppColors.orJour.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          textStyle: AppTypography.headingMd,
        );
      case AppButtonVariant.secondary:
        return _ButtonStyle(
          bg: Colors.transparent,
          fg: AppColors.orJour,
          border: AppColors.orJour,
          borderWidth: 1.5,
          height: 52,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 4),
          textStyle: AppTypography.headingSm,
        );
      case AppButtonVariant.ghost:
        return _ButtonStyle(
          bg: Colors.transparent,
          fg: AppColors.texteSecondaire,
          height: 44,
          radius: 8,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          textStyle: AppTypography.headingSm,
        );
      case AppButtonVariant.danger:
        return _ButtonStyle(
          bg: AppColors.errorSoft,
          fg: AppColors.error,
          border: AppColors.error,
          borderWidth: 1,
          height: 52,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 4),
          textStyle: AppTypography.headingSm,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _styleFor(widget.variant);
    final isDisabled = widget.onPressed == null && !widget.loading;

    final body = Container(
      height: s.height,
      width: widget.fullWidth ? double.infinity : null,
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(s.radius),
        border: s.border == null
            ? null
            : Border.all(color: s.border!, width: s.borderWidth ?? 1),
        boxShadow: s.shadow,
      ),
      alignment: Alignment.center,
      child: widget.loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(s.fg),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: widget.fullWidth
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: s.fg, size: 20),
                  AppSpacing.hGapSm,
                ],
                if (widget.iconAsset != null) ...[
                  Image.asset(widget.iconAsset!, width: 24, height: 24),
                  AppSpacing.hGapSm,
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    style: s.textStyle.copyWith(color: s.fg),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );

    final wrapped = AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: body,
    );

    return Opacity(
      opacity: isDisabled ? 0.38 : 1,
      child: GestureDetector(
        onTap: _enabled ? widget.onPressed : null,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        behavior: HitTestBehavior.opaque,
        child: wrapped,
      ),
    );
  }
}

/// Bundle de propriétés visuelles pour un variant donné.
class _ButtonStyle {
  const _ButtonStyle({
    required this.bg,
    required this.fg,
    required this.height,
    required this.radius,
    required this.padding,
    required this.textStyle,
    this.border,
    this.borderWidth,
    this.shadow,
  });

  final Color bg;
  final Color fg;
  final double height;
  final double radius;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final Color? border;
  final double? borderWidth;
  final List<BoxShadow>? shadow;
}
