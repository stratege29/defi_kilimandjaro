import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Rangée de cellules dorées 42×42 px affichant le mot en cours de formation.
///
/// Chaque cellule : fond doré si remplie, bord doré si vide.
///
/// **Validation correcte** : flip 3D staggéré (Wordle pattern) — chaque
/// cellule pivote 180° sur l'axe Y avec un délai de 100 ms par index. La
/// face arrière révèle la couleur de succès (`AppColors.success`).
/// C'est le micro-moment le plus mémorable du jeu de mots mobile en 2024-25.
class AnswerCells extends StatefulWidget {
  const AnswerCells({
    required this.answer,
    required this.formedLetters,
    required this.isValidated,
    super.key,
  });

  final String answer;

  /// Lettres formées jusqu'à présent (longueur <= answer.length).
  final String formedLetters;

  /// Passe à true lors d'une validation correcte pour déclencher le flip.
  final bool isValidated;

  @override
  State<AnswerCells> createState() => _AnswerCellsState();
}

class _AnswerCellsState extends State<AnswerCells>
    with SingleTickerProviderStateMixin {
  /// Délai par cellule, en fraction du temps total. 6 cellules = 6×100 ms
  /// (`_kStaggerStep` × `_kFlipDuration`) + 400 ms de flip = ~1000 ms total.
  static const double _kStaggerStep = 0.10;

  /// Durée d'une seule rotation 0→π, en fraction du temps total.
  static const double _kCellFlipFraction = 0.40;

  /// Durée totale de la séquence pour `answer.length` cellules.
  static const Duration _kSequenceDuration = Duration(milliseconds: 1000);

  late final AnimationController _flipCtrl;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: _kSequenceDuration);
  }

  @override
  void didUpdateWidget(AnswerCells oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isValidated && !oldWidget.isValidated) {
      _flipCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  /// Progress 0→1 pour la cellule à l'index `i`, en tenant compte du stagger.
  double _cellProgress(int i, double t) {
    final start = i * _kStaggerStep;
    final end = (start + _kCellFlipFraction).clamp(0.0, 1.0);
    if (t <= start) return 0;
    if (t >= end) return 1;
    final raw = (t - start) / (end - start);
    return Curves.easeInOut.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipCtrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(widget.answer.length, (i) {
            final hasLetter = i < widget.formedLetters.length;
            final letter = hasLetter ? widget.formedLetters[i] : '';
            // Une fois validé, on affiche la lettre cible (la bonne réponse).
            final displayLetter = widget.isValidated
                ? widget.answer[i].toUpperCase()
                : letter;
            return _FlipCell(
              letter: displayLetter,
              filled: hasLetter || widget.isValidated,
              flipProgress: _cellProgress(i, _flipCtrl.value),
            );
          }),
        );
      },
    );
  }
}

/// Cellule individuelle avec rotation 3D Y-axis.
///
/// `flipProgress` 0 → 0.5 : face avant visible (rotation 0 → 90°).
/// `flipProgress` 0.5 → 1 : face arrière visible avec couleur success
/// (rotation 90° → 180°, contenu contre-pivoté pour ne pas apparaître mirroré).
class _FlipCell extends StatelessWidget {
  const _FlipCell({
    required this.letter,
    required this.filled,
    required this.flipProgress,
  });

  final String letter;
  final bool filled;
  final double flipProgress;

  @override
  Widget build(BuildContext context) {
    final angle = flipProgress * math.pi;
    final showingBack = flipProgress >= 0.5;

    final cellContent = showingBack
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: _CellFace(
              letter: letter,
              bg: AppColors.success,
              borderColor: AppColors.success,
              textColor: AppColors.textePrimaire,
              shadowColor: AppColors.success,
            ),
          )
        : _CellFace(
            letter: letter,
            bg: filled ? AppColors.orSoleil : Colors.transparent,
            borderColor: AppColors.orSoleil,
            textColor: AppColors.vertForet,
            shadowColor: filled ? AppColors.orSoleil : null,
          );

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001) // perspective (1/distance)
        ..rotateY(angle),
      child: cellContent,
    );
  }
}

class _CellFace extends StatelessWidget {
  const _CellFace({
    required this.letter,
    required this.bg,
    required this.borderColor,
    required this.textColor,
    this.shadowColor,
  });

  final String letter;
  final Color bg;
  final Color borderColor;
  final Color textColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: shadowColor == null
            ? null
            : [
                BoxShadow(
                  color: shadowColor!.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ],
      ),
      child: Center(
        child: Text(
          letter,
          style: AppTypography.bebas(size: 22, color: textColor),
        ),
      ),
    );
  }
}
