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
  _GoldenPathPainter({
    required this.centers,
    required this.fingerPosition,
  });

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

  Path _buildPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
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
