import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:flutter/material.dart';

/// Explication culturelle d'une devinette : mot-réponse en gras (optionnel)
/// suivi de l'explication, sur un seul paragraphe. Partagé par la bannière
/// de victoire et l'écran de victoire pour les niveaux multi-mots (rafale,
/// duo) où chaque mot du niveau mérite son explication.
class DevinetteExplanation extends StatelessWidget {
  const DevinetteExplanation({
    required this.devinette,
    this.showAnswer = true,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final Devinette devinette;

  /// Préfixe l'explication du mot-réponse en gras.
  final bool showAnswer;

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final body = AppTypography.bodyMd.copyWith(
      color: AppColors.textePrimaire,
      height: 1.45,
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          if (showAnswer)
            TextSpan(
              text: '${devinette.answer.toUpperCase()} — ',
              style: body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.orSoleil,
              ),
            ),
          TextSpan(text: devinette.explanation),
        ],
      ),
      style: body,
      textAlign: textAlign,
    );
  }
}
