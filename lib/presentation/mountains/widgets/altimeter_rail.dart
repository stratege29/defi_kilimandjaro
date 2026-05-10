import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Altimètre vertical affiché en overlay sur le bord droit de l'écran.
///
/// Affiche des graduations de 0 m à 5 895 m sur une échelle logarithmique
/// pour éviter que les petits sommets se collent tous en bas.
///
/// [currentAltitude] : altitude du sommet actuellement affiché (interpolée
/// pendant le scroll PageView).
///
/// [bestAltitude] : altitude du meilleur sommet conquis par le joueur —
/// affiché comme une ligne "record" dorée.
class AltimeterRail extends StatelessWidget {
  const AltimeterRail({
    required this.currentAltitude,
    required this.bestAltitude,
    super.key,
  });

  final double currentAltitude;
  final int bestAltitude;

  static const int _maxAlt = 5895;

  /// Position normalisée logarithmique (0 = bas, 1 = haut).
  static double logPos(double altitude) {
    if (altitude <= 0) return 0;
    return math.log(altitude + 1) / math.log(_maxAlt + 1);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: CustomPaint(
        painter: _AltimeterPainter(
          currentNorm: logPos(currentAltitude),
          bestNorm: logPos(bestAltitude.toDouble()),
          currentAltitude: currentAltitude.round(),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AltimeterPainter extends CustomPainter {
  const _AltimeterPainter({
    required this.currentNorm,
    required this.bestNorm,
    required this.currentAltitude,
  });

  final double currentNorm;
  final double bestNorm;
  final int currentAltitude;

  static const List<int> _ticks = [0, 1000, 2000, 3000, 4000, 5895];
  static const double _railX = 8;
  static const double _railWidth = 4;

  double _normY(double norm, double h) => h * (1 - norm);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final railRect = Rect.fromLTWH(_railX, 0, _railWidth, h);

    // Rail de fond
    final bgPaint = Paint()
      ..color = AppColors.ivoire.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(railRect, const Radius.circular(2)),
      bgPaint,
    );

    // Remplissage du rail sous le curseur (progression altitude)
    final fillH = h * currentNorm;
    if (fillH > 0) {
      final fillPaint = Paint()
        ..color = AppColors.orSoleil.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      final fillRect = Rect.fromLTWH(
        _railX,
        h - fillH,
        _railWidth,
        fillH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
        fillPaint,
      );
    }

    // Graduations
    final tickPaint = Paint()
      ..color = AppColors.ivoire.withValues(alpha: 0.40)
      ..strokeWidth = 1;

    final labelStyle = AppTypography.bebas(
      size: 8,
      color: AppColors.ivoire.withValues(alpha: 0.55),
      letterSpacing: 0,
    );

    for (final alt in _ticks) {
      final norm = AltimeterRail.logPos(alt.toDouble());
      final y = _normY(norm, h);
      canvas.drawLine(
        Offset(_railX + _railWidth, y),
        Offset(_railX + _railWidth + 5, y),
        tickPaint,
      );

      // Label
      final label = alt == 5895 ? '5.9k' : '${alt ~/ 1000}k';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_railX + _railWidth + 7, y - tp.height / 2));
    }

    // Ligne "record" du joueur
    if (bestNorm > 0.01) {
      final bestY = _normY(bestNorm, h);
      final recordPaint = Paint()
        ..color = AppColors.orSoleil.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, bestY),
        Offset(_railX + _railWidth + 16, bestY),
        recordPaint,
      );
    }

    // Curseur "tu es ici"
    _drawCursor(canvas, h);
  }

  void _drawCursor(Canvas canvas, double h) {
    final cursorY = _normY(currentNorm, h);

    final cursorPaint = Paint()
      ..color = AppColors.orSoleil
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(_railX - 3, cursorY)
      ..lineTo(_railX + _railWidth + 5, cursorY - 6)
      ..lineTo(_railX + _railWidth + 5, cursorY + 6)
      ..close();
    canvas
      ..drawPath(path, cursorPaint)
      ..drawCircle(
        Offset(_railX + _railWidth / 2, cursorY),
        5,
        cursorPaint,
      );
  }

  @override
  bool shouldRepaint(_AltimeterPainter old) =>
      old.currentNorm != currentNorm ||
      old.bestNorm != bestNorm ||
      old.currentAltitude != currentAltitude;
}
