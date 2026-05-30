import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/widgets/flag_roundel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Altimètre vertical affiché en overlay sur le bord droit de l'écran.
///
/// Affiche des graduations de 0 m à 5 895 m sur une échelle logarithmique
/// pour éviter que les petits sommets se collent tous en bas.
///
/// Devient un **scrubber interactif** : un vertical drag sur le rail saute
/// directement à la montagne la plus proche de l'altitude survolée, et un
/// label flottant suit le doigt pour annoncer le sommet ciblé.
///
/// [currentAltitude] : altitude du sommet actuellement affiché (interpolée
/// pendant le scroll PageView).
///
/// [bestAltitude] : altitude du meilleur sommet conquis par le joueur —
/// affiché comme une ligne "record" dorée.
///
/// [mountains] : liste ordonnée (du plus bas au plus haut) — sert au mapping
/// position Y → index de page.
///
/// [onSeekToIndex] : invoqué pendant le drag (chaque update) et au release.
/// Le parent décide s'il fait un jump instant ou animé.
class AltimeterRail extends StatefulWidget {
  const AltimeterRail({
    required this.currentAltitude,
    required this.bestAltitude,
    required this.mountains,
    required this.onSeekToIndex,
    super.key,
  });

  final double currentAltitude;
  final int bestAltitude;
  final List<Mountain> mountains;
  final ValueChanged<int> onSeekToIndex;

  static const int _maxAlt = 5895;

  /// Position normalisée logarithmique (0 = bas, 1 = haut).
  static double logPos(double altitude) {
    if (altitude <= 0) return 0;
    return math.log(altitude + 1) / math.log(_maxAlt + 1);
  }

  /// Inverse de [logPos] : norm ∈ [0,1] → altitude en mètres.
  static double altitudeFromNorm(double norm) {
    final clamped = norm.clamp(0.0, 1.0);
    return math.exp(clamped * math.log(_maxAlt + 1)) - 1;
  }

  @override
  State<AltimeterRail> createState() => _AltimeterRailState();
}

class _AltimeterRailState extends State<AltimeterRail> {
  static const double _railColumnWidth = 42;
  // Largeur totale du widget : on étend à gauche pour héberger le label
  // flottant sans déborder hors du Stack parent (qui pourrait clipper).
  static const double _totalWidth = 180;

  // État du drag : null si pas de drag en cours.
  double? _dragY;
  int? _hoverIndex;

  /// Index du sommet le plus proche d'une altitude donnée.
  int _nearestIndex(double altitude) {
    if (widget.mountains.isEmpty) return 0;
    var bestIdx = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < widget.mountains.length; i++) {
      final delta = (widget.mountains[i].altitude - altitude).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _handleSeek(double localY, double height) {
    final norm = (1 - localY / height).clamp(0.0, 1.0);
    final alt = AltimeterRail.altitudeFromNorm(norm);
    final idx = _nearestIndex(alt);
    setState(() {
      _dragY = localY.clamp(0.0, height);
      _hoverIndex = idx;
    });
    widget.onSeekToIndex(idx);
  }

  void _endDrag() {
    if (_dragY != null) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _dragY = null;
      _hoverIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _totalWidth,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Painter du rail (graduations, fill, curseur, ligne record).
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _railColumnWidth,
                child: CustomPaint(
                  painter: _AltimeterPainter(
                    currentNorm: AltimeterRail.logPos(widget.currentAltitude),
                    bestNorm:
                        AltimeterRail.logPos(widget.bestAltitude.toDouble()),
                    currentAltitude: widget.currentAltitude.round(),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),

              // 2. Zone tactile sur le rail (+ petite marge à gauche pour
              // faciliter le toucher au pouce). On garde une zone étroite
              // pour ne pas voler les taps sur les CTA centraux.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _railColumnWidth + 16,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) =>
                      _handleSeek(d.localPosition.dy, h),
                  onVerticalDragUpdate: (d) =>
                      _handleSeek(d.localPosition.dy, h),
                  onVerticalDragEnd: (_) => _endDrag(),
                  onVerticalDragCancel: _endDrag,
                  // Tap simple : sauter directement à cette altitude.
                  onTapDown: (d) => _handleSeek(d.localPosition.dy, h),
                  onTapUp: (_) => _endDrag(),
                  onTapCancel: _endDrag,
                  child: const SizedBox.expand(),
                ),
              ),

              // 3. Label flottant pendant le drag — nom de la montagne
              //    survolée + altitude. Positionné à gauche du rail pour
              //    rester visible sous le doigt.
              if (_dragY != null && _hoverIndex != null)
                Positioned(
                  right: _railColumnWidth + 12,
                  top: (_dragY! - 18).clamp(0.0, h - 36),
                  child: _HoverLabel(
                    mountain: widget.mountains[_hoverIndex!],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Bulle flottante qui suit le doigt pendant le drag de l'altimètre.
class _HoverLabel extends StatelessWidget {
  const _HoverLabel({required this.mountain});

  final Mountain mountain;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.orSoleil.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlagRoundel(countryCode: mountain.countryCode, size: 18),
            const SizedBox(width: 6),
            Text(
              mountain.name.toUpperCase(),
              style: AppTypography.bebas(size: 13, letterSpacing: 1.5),
            ),
            const SizedBox(width: 8),
            Text(
              '${mountain.altitude} m',
              style: AppTypography.bebas(
                size: 12,
                color: AppColors.orSoleil,
              ),
            ),
          ],
        ),
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
      final fillRect = Rect.fromLTWH(_railX, h - fillH, _railWidth, fillH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
        fillPaint,
      );
    }

    // Graduations
    final tickPaint = Paint()
      ..color = AppColors.texteDisabled
      ..strokeWidth = 1;

    final labelStyle = AppTypography.bebas(
      size: 8,
      color: AppColors.texteTertiaire,
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
      ..drawCircle(Offset(_railX + _railWidth / 2, cursorY), 5, cursorPaint);
  }

  @override
  bool shouldRepaint(_AltimeterPainter old) =>
      old.currentNorm != currentNorm ||
      old.bestNorm != bestNorm ||
      old.currentAltitude != currentAltitude;
}
