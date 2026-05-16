import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// CustomPainter dessinant le chemin doré que l'utilisateur trace avec son
/// doigt entre les lettres sélectionnées.
///
/// Contrairement à une version naïve qui ne relie que les centres des
/// tuiles, [points] contient le **tracé brut** du doigt (positions
/// enregistrées pendant le drag) entrecoupé des centres des tuiles
/// « snappés » à chaque ajout. La ligne suit donc fidèlement le chemin
/// pris par l'utilisateur — y compris s'il sort du cercle des lettres
/// pour relier deux tuiles non adjacentes.
///
/// Si [fingerPosition] est non-null, la ligne est prolongée en live
/// jusqu'au doigt courant.
///
/// Double couche : trait plein doré + halo flou pour l'effet lumineux.
class GoldenPath extends StatelessWidget {
  const GoldenPath({
    required this.points,
    required this.fingerPosition,
    super.key,
  });

  /// Tracé brut en coordonnées locales (incluant snaps sur centres).
  final List<Offset> points;

  /// Position courante du doigt lors du drag (null si finger levé).
  final Offset? fingerPosition;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GoldenPathPainter(
          points: points,
          fingerPosition: fingerPosition,
        ),
      ),
    );
  }
}

class _GoldenPathPainter extends CustomPainter {
  _GoldenPathPainter({required this.points, required this.fingerPosition})
      : _pointsLength = points.length;

  final List<Offset> points;
  final Offset? fingerPosition;

  /// Snapshot de la longueur au moment de la construction. Indispensable
  /// car `points` est une liste **mutée en place** côté grille (append à
  /// chaque pointer move, clear sur `clearSelection`). Sans ce snapshot,
  /// `shouldRepaint` comparerait deux références identiques pointant sur
  /// la même liste post-mutation → `oldDelegate.points.length` retournerait
  /// déjà la nouvelle longueur, et la ligne ne se redessinerait jamais.
  final int _pointsLength;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final pts = <Offset>[...points];
    if (fingerPosition != null) {
      pts.add(fingerPosition!);
    }

    if (pts.length < 2) return;

    final simplified = _simplify(pts, tolerance: 2);

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

    final path = _buildPath(simplified);

    canvas
      ..drawPath(path, glowPaint)
      ..drawPath(path, linePaint);
  }

  /// Réduit la densité de points en supprimant ceux trop proches du
  /// précédent (sous [tolerance] px). Évite que la spline n'oscille
  /// inutilement sur de très petits déplacements (jitter du doigt).
  List<Offset> _simplify(List<Offset> input, {required double tolerance}) {
    if (input.length <= 2) return input;
    final tol2 = tolerance * tolerance;
    final out = <Offset>[input.first];
    for (var i = 1; i < input.length - 1; i++) {
      final last = out.last;
      final dx = input[i].dx - last.dx;
      final dy = input[i].dy - last.dy;
      if (dx * dx + dy * dy >= tol2) {
        out.add(input[i]);
      }
    }
    out.add(input.last);
    return out;
  }

  /// Trace les segments en **Catmull-Rom spline** (cubic bezier dérivé).
  ///
  /// Tension volontairement basse (0.5) car les points proviennent
  /// majoritairement du tracé brut du doigt : on veut un suivi fidèle
  /// sans overshoot, alors qu'avec uniquement des centres on aurait pu
  /// pousser à 1.0+ pour plus de cambrure.
  Path _buildPath(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    if (pts.length == 1) return path;
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }

    const tension = 0.5;
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
    // On compare les longueurs **capturées à la construction** (pas
    // `points.length` qui lit la liste mutée et donnerait la même valeur
    // des deux côtés).
    return oldDelegate._pointsLength != _pointsLength;
  }
}
