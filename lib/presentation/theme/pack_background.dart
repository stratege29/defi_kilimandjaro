import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:defi_kilimandjaro/presentation/theme/pack_motif_painter.dart';
import 'package:flutter/material.dart';

/// Fond d'écran teinté par le skin d'un pack.
///
/// Peint un dégradé vertical [PackTheme.background] → [PackTheme.backgroundEnd]
/// puis, le cas échéant, un **motif culturel** ([PackTheme.motif]) en tuilage
/// très léger par-dessus. Pour le thème par défaut (couleurs égales,
/// `motif == none`), le rendu est un aplat strictement identique au look
/// « Vert Nuit » historique.
///
/// Le motif est GPU-safe (cf. [PackMotifPainter]) et ne capte pas le touch.
class PackBackground extends StatelessWidget {
  const PackBackground({required this.theme, required this.child, super.key});

  final PackTheme theme;
  final Widget child;

  /// Opacité du motif sur le fond — assez basse pour rester sous le contenu
  /// sans gêner la lisibilité.
  static const double _motifAlpha = 0.05;

  @override
  Widget build(BuildContext context) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[theme.background, theme.backgroundEnd],
        ),
      ),
    );

    if (theme.motif == PackMotif.none) {
      return Stack(fit: StackFit.expand, children: <Widget>[gradient, child]);
    }

    final motifColor = (theme.motifColor ?? theme.accent).withValues(
      alpha: _motifAlpha,
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        gradient,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: PackMotifPainter(
                  motif: theme.motif,
                  color: motifColor,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
