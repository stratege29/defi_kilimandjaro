import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain_shape.dart';
import 'package:flutter/material.dart';

/// CustomPainter qui dessine la silhouette d'un sommet selon son [MountainShape].
///
/// Le paramètre [seed] (altitude en mètres) introduit de légères variations
/// aléatoires reproductibles — même montagne = même dessin à chaque frame.
///
/// [locked] → silhouette gris brumeux.
/// [completed] → drapeau planté au sommet.
/// [progress] (0.0–1.0) → remplissage partiel de couleur pour signifier
/// l'avancement du joueur.
class MountainSilhouettePainter extends CustomPainter {
  const MountainSilhouettePainter({
    required this.shape,
    required this.seed,
    required this.locked,
    required this.completed,
    required this.primaryColor,
    required this.snowColor,
    this.progress = 0,
    this.hasPulse = false,
    this.pulseValue = 0,
  });

  final MountainShape shape;
  final int seed;
  final bool locked;
  final bool completed;
  final Color primaryColor;
  final Color snowColor;
  final double progress;
  final bool hasPulse;
  final double pulseValue;

  // Variation pseudo-aléatoire reproductible à partir du seed.
  double _v(int index) {
    final r = math.Random((seed * 31 + index * 17).abs());
    return r.nextDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillColor = locked ? AppColors.silhouetteVerrouillee : primaryColor;

    if (hasPulse && !locked) {
      _drawPulse(canvas, size, pulseValue);
    }

    switch (shape) {
      case MountainShape.cone:
        _drawCone(canvas, w, h, fillColor);
      case MountainShape.plateau:
        _drawPlateau(canvas, w, h, fillColor);
      case MountainShape.crest:
        _drawCrest(canvas, w, h, fillColor);
      case MountainShape.dome:
        _drawDome(canvas, w, h, fillColor);
      case MountainShape.dent:
        _drawDent(canvas, w, h, fillColor);
      case MountainShape.mesa:
        _drawMesa(canvas, w, h, fillColor);
    }

    if (completed && !locked) {
      _drawFlag(canvas, w, h);
    }
  }

  void _drawPulse(Canvas canvas, Size size, double value) {
    final cx = size.width / 2;
    final cy = size.height * 0.35;
    final radius = (size.width * 0.45) * (0.9 + value * 0.3);
    final opacity = (1 - value) * 0.35;

    final paint = Paint()
      ..color = AppColors.haloCourant.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), radius, paint);
  }

  Paint _mountainPaint(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  // ---- Archétypes ----

  /// Cône volcanique classique avec légère asymétrie.
  void _drawCone(Canvas canvas, double w, double h, Color color) {
    final asymmetry = (_v(0) - 0.5) * 0.15;
    final peakX = w * (0.5 + asymmetry);
    final peakY = h * (0.08 + _v(1) * 0.06);
    final leftX = w * (-0.05 + _v(2) * 0.06);
    final rightX = w * (1.05 - _v(3) * 0.06);

    final path = Path()
      ..moveTo(leftX, h)
      ..lineTo(peakX - w * 0.03, peakY + h * 0.18)
      ..lineTo(peakX, peakY)
      ..lineTo(peakX + w * 0.03, peakY + h * 0.18)
      ..lineTo(rightX, h)
      ..close();

    canvas.drawPath(path, _mountainPaint(color));

    // Calotte neigeuse
    if (!locked) {
      final snowPath = Path()
        ..moveTo(peakX, peakY)
        ..lineTo(peakX - w * 0.09, peakY + h * 0.12)
        ..lineTo(peakX + w * 0.08, peakY + h * 0.12)
        ..close();
      canvas.drawPath(snowPath, _mountainPaint(snowColor.withValues(alpha: 0.85)));
    }
  }

  /// Sommet tabulaire — plateau plat caractéristique du Kilimandjaro.
  void _drawPlateau(Canvas canvas, double w, double h, Color color) {
    final plateauWidth = 0.38 + _v(0) * 0.12;
    final plateauLeft = (1 - plateauWidth) / 2 * w;
    final plateauRight = plateauLeft + plateauWidth * w;
    final plateauY = h * (0.10 + _v(1) * 0.05);
    final shoulderDropL = h * (0.14 + _v(2) * 0.06);
    final shoulderDropR = h * (0.14 + _v(3) * 0.06);

    final path = Path()
      ..moveTo(w * (-0.04), h)
      ..lineTo(w * 0.12, plateauY + shoulderDropL)
      ..lineTo(plateauLeft, plateauY)
      ..lineTo(plateauRight, plateauY)
      ..lineTo(w * 0.88, plateauY + shoulderDropR)
      ..lineTo(w * 1.04, h)
      ..close();

    canvas.drawPath(path, _mountainPaint(color));

    // Calotte neigeuse plate
    if (!locked) {
      final snowPath = Path()
        ..moveTo(plateauLeft + w * 0.02, plateauY)
        ..lineTo(plateauRight - w * 0.02, plateauY)
        ..lineTo(plateauRight - w * 0.02, plateauY + h * 0.03)
        ..lineTo(plateauLeft + w * 0.02, plateauY + h * 0.03)
        ..close();
      canvas.drawPath(
        snowPath,
        _mountainPaint(snowColor.withValues(alpha: 0.9)),
      );
    }
  }

  /// Crête dentelée — multiple pics irréguliers.
  void _drawCrest(Canvas canvas, double w, double h, Color color) {
    final numPeaks = 3 + (seed % 2);
    final baseY = h;
    final path = Path()..moveTo(0, baseY);

    final peaks = <double>[];
    for (var i = 0; i < numPeaks; i++) {
      peaks.add(h * (0.08 + _v(i) * 0.14));
    }
    final mainPeakIndex = numPeaks ~/ 2;

    for (var i = 0; i < numPeaks; i++) {
      final x = w * (i + 0.5) / numPeaks;
      final py = peaks[i] * (i == mainPeakIndex ? 0.75 : 1.0);
      final prevX = i == 0 ? 0.0 : w * (i - 0.5) / numPeaks;
      final midX = (prevX + x) / 2;
      path
        ..lineTo(midX, h * (0.35 + _v(i + 10) * 0.15))
        ..lineTo(x, py);
    }
    path
      ..lineTo(w, baseY)
      ..close();

    canvas.drawPath(path, _mountainPaint(color));

    if (!locked) {
      final mainX = w * (mainPeakIndex + 0.5) / numPeaks;
      final mainY = peaks[mainPeakIndex] * 0.75;
      final snowPath = Path()
        ..moveTo(mainX, mainY)
        ..lineTo(mainX - w * 0.07, mainY + h * 0.10)
        ..lineTo(mainX + w * 0.06, mainY + h * 0.10)
        ..close();
      canvas.drawPath(
        snowPath,
        _mountainPaint(snowColor.withValues(alpha: 0.8)),
      );
    }
  }

  /// Dôme arrondi — silhouette en arc de cercle doux.
  void _drawDome(Canvas canvas, double w, double h, Color color) {
    final cx = w * (0.5 + (_v(0) - 0.5) * 0.12);
    final peakY = h * (0.10 + _v(1) * 0.07);
    final rx = w * (0.55 + _v(2) * 0.08);
    final ry = (h - peakY) * 0.85;

    final path = Path()
      ..moveTo(0, h)
      ..lineTo(cx - rx * 0.85, h)
      ..addArc(
        Rect.fromCenter(
          center: Offset(cx, peakY + ry),
          width: rx * 2,
          height: ry * 2,
        ),
        math.pi,
        math.pi,
      )
      ..lineTo(w, h)
      ..close();

    canvas.drawPath(path, _mountainPaint(color));

    if (!locked) {
      final snowPath = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(cx, peakY + h * 0.04),
            width: rx * 0.38,
            height: h * 0.10,
          ),
        );
      canvas.drawPath(
        snowPath,
        _mountainPaint(snowColor.withValues(alpha: 0.75)),
      );
    }
  }

  /// Aiguille/dent — pic très effilé, quasi vertical.
  void _drawDent(Canvas canvas, double w, double h, Color color) {
    final peakX = w * (0.5 + (_v(0) - 0.5) * 0.1);
    final peakY = h * (0.04 + _v(1) * 0.04);
    final baseWidthL = w * (0.48 + _v(2) * 0.06);
    final baseWidthR = w * (0.48 + _v(3) * 0.06);

    final path = Path()
      ..moveTo(peakX - baseWidthL, h)
      ..lineTo(peakX - w * 0.04, peakY + h * 0.22)
      ..lineTo(peakX - w * 0.015, peakY + h * 0.08)
      ..lineTo(peakX, peakY)
      ..lineTo(peakX + w * 0.015, peakY + h * 0.08)
      ..lineTo(peakX + w * 0.04, peakY + h * 0.22)
      ..lineTo(peakX + baseWidthR, h)
      ..close();

    canvas.drawPath(path, _mountainPaint(color));

    if (!locked) {
      final snowPath = Path()
        ..moveTo(peakX, peakY)
        ..lineTo(peakX - w * 0.04, peakY + h * 0.09)
        ..lineTo(peakX + w * 0.04, peakY + h * 0.09)
        ..close();
      canvas.drawPath(
        snowPath,
        _mountainPaint(snowColor.withValues(alpha: 0.9)),
      );
    }
  }

  /// Mesa / plateau bas et large — trapèze court.
  void _drawMesa(Canvas canvas, double w, double h, Color color) {
    final tableWidth = 0.42 + _v(0) * 0.16;
    final tableLeft = (1 - tableWidth) / 2 * w;
    final tableRight = tableLeft + tableWidth * w;
    final tableY = h * (0.30 + _v(1) * 0.12);
    final slopeAngleL = h * (0.08 + _v(2) * 0.05);
    final slopeAngleR = h * (0.08 + _v(3) * 0.05);

    final path = Path()
      ..moveTo(0, h)
      ..lineTo(tableLeft - slopeAngleL, tableY)
      ..lineTo(tableLeft, tableY)
      ..lineTo(tableRight, tableY)
      ..lineTo(tableRight + slopeAngleR, tableY)
      ..lineTo(w, h)
      ..close();

    canvas.drawPath(path, _mountainPaint(color));

    // Pas de neige pour les mesas (altitude trop basse).
  }

  // ---- Drapeau planté au sommet ----

  void _drawFlag(Canvas canvas, double w, double h) {
    final peakX = _peakXFor(w);
    final peakY = _peakYFor(h);

    const poleColor = AppColors.orSoleil;
    final polePaint = Paint()
      ..color = poleColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Mât
    canvas.drawLine(
      Offset(peakX, peakY - h * 0.01),
      Offset(peakX, peakY - h * 0.12),
      polePaint,
    );

    // Fanion triangulaire
    final flagPaint = Paint()
      ..color = AppColors.orSoleil
      ..style = PaintingStyle.fill;
    final flagPath = Path()
      ..moveTo(peakX, peakY - h * 0.12)
      ..lineTo(peakX + w * 0.10, peakY - h * 0.085)
      ..lineTo(peakX, peakY - h * 0.055)
      ..close();
    canvas.drawPath(flagPath, flagPaint);
  }

  double _peakXFor(double w) {
    switch (shape) {
      case MountainShape.cone:
        return w * (0.5 + (_v(0) - 0.5) * 0.15);
      case MountainShape.plateau:
        return w * 0.5;
      case MountainShape.crest:
        final numPeaks = 3 + (seed % 2);
        return w * ((numPeaks ~/ 2 + 0.5) / numPeaks);
      case MountainShape.dome:
        return w * (0.5 + (_v(0) - 0.5) * 0.12);
      case MountainShape.dent:
        return w * (0.5 + (_v(0) - 0.5) * 0.1);
      case MountainShape.mesa:
        return w * 0.5;
    }
  }

  double _peakYFor(double h) {
    switch (shape) {
      case MountainShape.cone:
        return h * (0.08 + _v(1) * 0.06);
      case MountainShape.plateau:
        return h * (0.10 + _v(1) * 0.05);
      case MountainShape.crest:
        return h * (0.08 + _v(0) * 0.14) * 0.75;
      case MountainShape.dome:
        return h * (0.10 + _v(1) * 0.07);
      case MountainShape.dent:
        return h * (0.04 + _v(1) * 0.04);
      case MountainShape.mesa:
        return h * (0.30 + _v(1) * 0.12);
    }
  }

  @override
  bool shouldRepaint(MountainSilhouettePainter old) =>
      old.shape != shape ||
      old.seed != seed ||
      old.locked != locked ||
      old.completed != completed ||
      old.primaryColor != primaryColor ||
      old.progress != progress ||
      old.hasPulse != hasPulse ||
      old.pulseValue != pulseValue;
}
