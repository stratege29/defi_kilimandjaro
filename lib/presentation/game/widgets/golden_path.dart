import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// CustomPainter dessinant le chemin doré entre les tuiles sélectionnées.
///
/// - Trait continu reliant les centres des tuiles dans l'ordre de sélection.
/// - Si [fingerPosition] est non-null, prolonge le dernier segment jusqu'au doigt.
/// - Double couche : trait semi-transparent + halo flou pour l'effet lumineux.
class GoldenPath extends StatelessWidget {
  const GoldenPath({
    required this.centers,
    required this.fingerPosition,
    super.key,
  });

  /// Centres (en coordonnées locales) des tuiles sélectionnées, dans l'ordre.
  final List<Offset> centers;

  /// Position courante du doigt lors du drag (null si finger levé).
  final Offset? fingerPosition;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GoldenPathPainter(
          centers: centers,
          fingerPosition: fingerPosition,
        ),
      ),
    );
  }
}

class _GoldenPathPainter extends CustomPainter {
  _GoldenPathPainter({required this.centers, required this.fingerPosition});

  final List<Offset> centers;
  final Offset? fingerPosition;

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.isEmpty) return;

    final points = <Offset>[...centers];
    if (fingerPosition != null && centers.isNotEmpty) {
      points.add(fingerPosition!);
    }

    if (points.length < 2) return;

    // Halo (glow) layer.
    final glowPaint = Paint()
      ..color = AppColors.orSoleil.withValues(alpha: 0.3)
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Main line layer.
    final linePaint = Paint()
      ..color = AppColors.cheminDore
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = _buildPath(points);

    canvas
      ..drawPath(path, glowPaint)
      ..drawPath(path, linePaint);
  }

  /// Trace les segments en **Catmull-Rom spline** (cubic bezier dérivé).
  ///
  /// Chaque segment Pᵢ→Pᵢ₊₁ utilise comme points de contrôle :
  ///   CP1 = Pᵢ + (Pᵢ₊₁ − Pᵢ₋₁) × tension / 6
  ///   CP2 = Pᵢ₊₁ − (Pᵢ₊₂ − Pᵢ) × tension / 6
  ///
  /// Pour les extrémités (pas de Pᵢ₋₁ ou Pᵢ₊₂), on duplique le point lui-même
  /// → la tangente est nulle aux bouts, le trait part droit du premier centre.
  /// `tension = 1.2` donne une courbe organique sans s'écarter trop loin
  /// des points (à 1.0 = standard, < 1.0 plus rigide, > 1.5 ondulé).
  Path _buildPath(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    if (pts.length == 1) return path;
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }

    const tension = 1.2;
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];

      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) * tension / 6,
        p1.dy + (p2.dy - p0.dy) * tension / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) * tension / 6,
        p2.dy - (p3.dy - p1.dy) * tension / 6,
      );

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_GoldenPathPainter oldDelegate) {
    if (oldDelegate.fingerPosition != fingerPosition) return true;
    if (oldDelegate.centers.length != centers.length) return true;
    for (var i = 0; i < centers.length; i++) {
      if (oldDelegate.centers[i] != centers[i]) return true;
    }
    return false;
  }
}
