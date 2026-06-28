import 'dart:math' as math;

import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:flutter/material.dart';

/// Peint un motif culturel africain en tuilage léger sur le fond d'un écran.
///
/// **GPU-safe** : uniquement des `drawCircle`/`drawLine`/`drawPath` à trait fin —
/// **aucun** `MaskFilter.blur` ni `BackdropFilter` (cause de crash iOS 26, cf.
/// boot OOM). L'opacité est portée par [color] (déjà faible) pour rester sous le
/// contenu sans nuire à la lisibilité.
///
/// [PackMotif.none] ne peint rien : le fond reste l'aplat/dégradé historique.
class PackMotifPainter extends CustomPainter {
  const PackMotifPainter({required this.motif, required this.color});

  final PackMotif motif;
  final Color color;

  /// Pas de la trame (px). Constant pour un tuilage régulier et prévisible.
  static const double _cell = 56;

  @override
  void paint(Canvas canvas, Size size) {
    if (motif == PackMotif.none || color.a == 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    switch (motif) {
      case PackMotif.none:
        return;
      case PackMotif.adinkra:
        _paintAdinkra(canvas, size, paint);
      case PackMotif.kita:
        _paintKita(canvas, size, paint);
      case PackMotif.bogolan:
        _paintBogolan(canvas, size, paint);
      case PackMotif.kente:
        _paintKente(canvas, size, paint);
      case PackMotif.vagues:
        _paintVagues(canvas, size, paint);
    }
  }

  /// Adinkra : trame d'anneaux concentriques + petite croix centrale (clin
  /// d'œil aux symboles akan), un motif par cellule.
  void _paintAdinkra(Canvas canvas, Size size, Paint paint) {
    const r = _cell * 0.26;
    for (var y = _cell / 2; y < size.height + _cell; y += _cell) {
      for (var x = _cell / 2; x < size.width + _cell; x += _cell) {
        final c = Offset(x, y);
        canvas
          ..drawCircle(c, r, paint)
          ..drawCircle(c, r * 0.5, paint)
          ..drawLine(Offset(x - r * 0.4, y), Offset(x + r * 0.4, y), paint)
          ..drawLine(Offset(x, y - r * 0.4), Offset(x, y + r * 0.4), paint);
      }
    }
  }

  /// Kita / kente : double trame de fines diagonales croisées (tissage).
  void _paintKita(Canvas canvas, Size size, Paint paint) {
    const gap = _cell * 0.5;
    // Diagonales montantes puis descendantes → effet entrelacé.
    for (var d = -size.height; d < size.width; d += gap) {
      canvas
        ..drawLine(Offset(d, size.height), Offset(d + size.height, 0), paint)
        ..drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
    }
  }

  /// Bogolan : trame de petits chevrons/tirets (textile en terre, « mud cloth »).
  void _paintBogolan(Canvas canvas, Size size, Paint paint) {
    const s = _cell * 0.22;
    for (var y = _cell / 2; y < size.height + _cell; y += _cell) {
      for (var x = _cell / 2; x < size.width + _cell; x += _cell) {
        // Chevron ^.
        canvas
          ..drawLine(Offset(x - s, y + s), Offset(x, y - s), paint)
          ..drawLine(Offset(x, y - s), Offset(x + s, y + s), paint);
      }
    }
  }

  /// Kente : trame orthogonale fine (bandes horizontales + verticales).
  void _paintKente(Canvas canvas, Size size, Paint paint) {
    for (var x = 0.0; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  /// Vagues : rangées de sinusoïdes douces (lagune / mouvement).
  void _paintVagues(Canvas canvas, Size size, Paint paint) {
    const amp = _cell * 0.16;
    const rowGap = _cell * 0.75;
    for (var y = rowGap; y < size.height + rowGap; y += rowGap) {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 8) {
        path.lineTo(x, y + amp * math.sin(x / _cell * math.pi));
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(PackMotifPainter old) =>
      old.motif != motif || old.color != color;
}
