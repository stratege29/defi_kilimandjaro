import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Rangée de cellules dorées 42×42 px affichant le mot en cours de formation.
///
/// Chaque cellule : fond doré si remplie, bord doré si vide.
/// Flash vert 600 ms lors de la validation correcte.
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

  /// Passe à true lors d'une validation correcte pour déclencher le flash vert.
  final bool isValidated;

  @override
  State<AnswerCells> createState() => _AnswerCellsState();
}

class _AnswerCellsState extends State<AnswerCells>
    with SingleTickerProviderStateMixin {
  static const Duration _kFlashDuration = Duration(milliseconds: 600);

  late final AnimationController _flashCtrl;
  late final Animation<Color?> _flashAnim;

  @override
  void initState() {
    super.initState();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: _kFlashDuration,
    );
    _flashAnim = ColorTween(
      begin: AppColors.orSoleil,
      end: AppColors.vertClair,
    ).animate(CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(AnswerCells oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isValidated && !oldWidget.isValidated) {
      _flashCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flashAnim,
      builder: (_, __) {
        final cellColor = _flashCtrl.isAnimating
            ? (_flashAnim.value ?? AppColors.orSoleil)
            : AppColors.orSoleil;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(widget.answer.length, (i) {
            final hasLetter = i < widget.formedLetters.length;
            final letter = hasLetter ? widget.formedLetters[i] : '';
            return _Cell(
              letter: letter,
              filled: hasLetter,
              fillColor: cellColor,
            );
          }),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.letter,
    required this.filled,
    required this.fillColor,
  });

  final String letter;
  final bool filled;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: filled ? fillColor : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.orSoleil,
          width: 2,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: AppColors.orSoleil.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          letter,
          style: AppTypography.bebas(
            size: 22,
            color: AppColors.vertForet,
          ),
        ),
      ),
    );
  }
}
