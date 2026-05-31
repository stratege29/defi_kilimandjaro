import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Bouton secondaire « filet pointillé » de la maquette (`.double`).
///
/// Rectangle pleine largeur, fond transparent, bordure **dashed** (or par
/// défaut, ou hairline pour les variantes neutres comme « Révéler » /
/// « Revanche »). Sert de filet anti-blocage / action optionnelle sous le CTA
/// primaire, sans lui voler la vedette.
class DashedButton extends StatelessWidget {
  const DashedButton({
    required this.label,
    required this.onTap,
    this.borderColor = AppColors.orJour,
    this.textColor = AppColors.orJour,
    this.leading,
    this.trailing,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;

  /// Couleur du filet pointillé (or par défaut, hairline pour le neutre).
  final Color borderColor;

  /// Couleur du libellé.
  final Color textColor;

  /// Icône / pastille optionnelle avant le libellé.
  final Widget? leading;

  /// Icône / pastille optionnelle après le libellé (ex. coin cauris, ▶).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: borderColor.withValues(alpha: onTap == null ? 0.3 : 0.5),
            radius: 12,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textColor.withValues(alpha: onTap == null ? 0.5 : 1),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
