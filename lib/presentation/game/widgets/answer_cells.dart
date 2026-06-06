import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Rangée de cellules dorées 42×42 px affichant le mot en cours de formation.
///
/// Chaque cellule : fond doré si remplie, bord doré si vide.
///
/// **Indice** : chaque indice révèle une lettre correcte à une position
/// **au hasard** ([revealedPositions]). Tant que le joueur ne l'a pas encore
/// formée, la case affiche cette lettre en aperçu « fantôme » (doré
/// translucide). La case fraîchement révélée joue un **pop + flip 3D** doré.
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
    this.fillFromEnd = false,
    this.revealedPositions = const <int>{},
    super.key,
  });

  final String answer;

  /// Lettres formées jusqu'à présent (longueur <= answer.length).
  final String formedLetters;

  /// Passe à true lors d'une validation correcte pour déclencher le flip.
  final bool isValidated;

  /// Modifier `reverse` (« mot à l'envers ») actif : la première lettre
  /// sélectionnée s'affiche dans la **dernière** case, la deuxième dans
  /// l'avant-dernière, etc. Les cases se remplissent donc de droite à
  /// gauche. Validation et indices restent gérés par le controller
  /// (`expectedAnswer` déjà inversé) — seul l'affichage change ici.
  final bool fillFromEnd;

  /// Positions (dans [answer], donc déjà en espace `expectedAnswer`)
  /// révélées par l'indice. La case correspondante affiche la lettre
  /// correcte en aperçu fantôme tant que le joueur ne l'a pas formée.
  final Set<int> revealedPositions;

  @override
  State<AnswerCells> createState() => _AnswerCellsState();
}

class _AnswerCellsState extends State<AnswerCells>
    with TickerProviderStateMixin {
  /// Délai par cellule, en fraction du temps total. 6 cellules = 6×100 ms
  /// (`_kStaggerStep` × `_kFlipDuration`) + 400 ms de flip = ~1000 ms total.
  static const double _kStaggerStep = 0.10;

  /// Durée d'une seule rotation 0→π, en fraction du temps total.
  static const double _kCellFlipFraction = 0.40;

  /// Durée totale de la séquence pour `answer.length` cellules.
  static const Duration _kSequenceDuration = Duration(milliseconds: 1000);

  /// Durée du pop + flip d'une lettre placée par l'indice.
  static const Duration _kHintRevealDuration = Duration(milliseconds: 520);

  late final AnimationController _flipCtrl;
  late final AnimationController _hintCtrl;

  /// Position (espace `answer`) de la dernière case révélée à animer. `null`
  /// tant qu'aucun indice n'a été placé dans la session courante du widget.
  int? _animHintPos;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: _kSequenceDuration);
    _hintCtrl = AnimationController(vsync: this, duration: _kHintRevealDuration);
  }

  @override
  void didUpdateWidget(AnswerCells oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isValidated && !oldWidget.isValidated) {
      _flipCtrl.forward(from: 0);
    }
    // Nouvelle position révélée par l'indice → pop + flip sur cette case.
    final newlyRevealed =
        widget.revealedPositions.difference(oldWidget.revealedPositions);
    if (newlyRevealed.isNotEmpty && !widget.isValidated) {
      _animHintPos = newlyRevealed.first;
      _hintCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _hintCtrl.dispose();
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
    // Calcul d'une taille adaptative pour ne pas overflow sur mots longs
    // (DJEMBEFOLA = 10 lettres en mode duel hard). Le defaut 42×42 + 6px
    // margin fait 480px pour 10 cellules, dépasse la largeur iPhone (~393px).
    return LayoutBuilder(
      builder: (context, constraints) {
        const defaultCell = 42.0;
        const horizontalMargin = 6.0;
        final maxWidth = constraints.maxWidth;
        final wantedWidth =
            widget.answer.length * (defaultCell + horizontalMargin);
        final cellSize = wantedWidth <= maxWidth
            ? defaultCell
            : (maxWidth / widget.answer.length - horizontalMargin)
                  .clamp(24.0, defaultCell);

        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_flipCtrl, _hintCtrl]),
          builder: (_, __) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(widget.answer.length, (i) {
                final n = widget.answer.length;
                // Position dans la séquence de saisie représentée par la
                // cellule physique `i`. En mode `fillFromEnd`, la cellule la
                // plus à droite (i == n-1) porte la 1re lettre saisie.
                final seqPos = widget.fillFromEnd ? n - 1 - i : i;

                // Victoire : flip staggéré de toutes les cases.
                if (widget.isValidated) {
                  return _FlipCell(
                    letter: widget.answer[seqPos].toUpperCase(),
                    filled: true,
                    flipProgress: _cellProgress(i, _flipCtrl.value),
                    size: cellSize,
                  );
                }

                final hasPlayerLetter = seqPos < widget.formedLetters.length;
                final isHint = !hasPlayerLetter &&
                    widget.revealedPositions.contains(seqPos);
                final kind = hasPlayerLetter
                    ? _CellKind.filled
                    : (isHint ? _CellKind.hint : _CellKind.empty);
                final letter = hasPlayerLetter
                    ? widget.formedLetters[seqPos]
                    : (isHint ? widget.answer[seqPos] : '');
                // La case révélée la plus récente joue le pop + flip tant que
                // son controller tourne ; les autres restent statiques.
                final animating =
                    seqPos == _animHintPos && _hintCtrl.isAnimating;

                return _PlayCell(
                  letter: letter.toUpperCase(),
                  kind: kind,
                  animating: animating,
                  revealProgress: _hintCtrl.value,
                  size: cellSize,
                );
              }),
            );
          },
        );
      },
    );
  }
}

/// Styles possibles d'une case pendant le jeu (hors animation de victoire).
enum _CellKind { empty, filled, hint }

/// Case affichée pendant le jeu : vide, remplie par le joueur, ou aperçu
/// d'indice. Quand [animating], joue le pop + flip de placement (face avant
/// vide → face arrière aperçu doré).
class _PlayCell extends StatelessWidget {
  const _PlayCell({
    required this.letter,
    required this.kind,
    required this.animating,
    required this.revealProgress,
    required this.size,
  });

  final String letter;
  final _CellKind kind;

  /// Quand `false`, rendu statique selon [kind]. Quand `true`, joue le
  /// pop + flip piloté par [revealProgress] (face vide → aperçu doré).
  final bool animating;
  final double revealProgress;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!animating) {
      return _faceForKind(kind, letter, size);
    }

    final p = revealProgress.clamp(0.0, 1.0);
    final angle = p * math.pi;
    final showingBack = p >= 0.5;
    final scale = _popScale(p);

    final content = showingBack
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: _faceForKind(_CellKind.hint, letter, size),
          )
        : _faceForKind(_CellKind.empty, '', size);

    return Transform.scale(
      scale: scale,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001) // perspective (1/distance)
          ..rotateY(angle),
        child: content,
      ),
    );
  }

  /// Pop avec léger dépassement : 0.6 → 1.12 (à 60 %) → 1.0.
  static double _popScale(double p) {
    const peak = 1.12;
    if (p < 0.6) {
      final t = Curves.easeOut.transform(p / 0.6);
      return 0.6 + (peak - 0.6) * t;
    }
    final t = Curves.easeOut.transform((p - 0.6) / 0.4);
    return peak + (1.0 - peak) * t;
  }
}

/// Construit la face d'une case selon son [kind].
Widget _faceForKind(_CellKind kind, String letter, double size) {
  switch (kind) {
    case _CellKind.filled:
      return _CellFace(
        letter: letter,
        bg: AppColors.orJour,
        borderColor: AppColors.orJour,
        textColor: AppColors.surface,
        shadowColor: AppColors.orJour,
        size: size,
      );
    case _CellKind.hint:
      // Aperçu fantôme : doré translucide, lettre dorée — se distingue d'une
      // case réellement remplie par le joueur (or plein, lettre sombre).
      return _CellFace(
        letter: letter,
        bg: AppColors.orJour.withValues(alpha: 0.16),
        borderColor: AppColors.orJour.withValues(alpha: 0.7),
        textColor: AppColors.orJour,
        size: size,
      );
    case _CellKind.empty:
      return _CellFace(
        letter: letter,
        bg: AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderColor: AppColors.orJour.withValues(alpha: 0.35),
        textColor: AppColors.textePrimaire,
        size: size,
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
    this.size = 42,
  });

  final String letter;
  final bool filled;
  final double flipProgress;
  final double size;

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
              size: size,
            ),
          )
        : _CellFace(
            letter: letter,
            bg: filled ? AppColors.orJour : AppColors.surfaceVariant.withValues(alpha: 0.6),
            borderColor: filled ? AppColors.orJour : AppColors.orJour.withValues(alpha: 0.35),
            textColor: filled ? AppColors.surface : AppColors.textePrimaire,
            shadowColor: filled ? AppColors.orJour : null,
            size: size,
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
    this.size = 42,
  });

  final String letter;
  final Color bg;
  final Color borderColor;
  final Color textColor;
  final Color? shadowColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Font size proportionnelle a la taille de cellule (22 pour 42 = ~52%).
    final fontSize = (size * 0.52).clamp(14.0, 22.0);
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
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
          style: AppTypography.bebas(size: fontSize, color: textColor),
        ),
      ),
    );
  }
}
