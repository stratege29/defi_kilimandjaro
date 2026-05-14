import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/golden_path.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/letter_grid_pattern.dart';
import 'package:flutter/material.dart';

/// Grille de tuiles lettres avec détection de drag.
///
/// Le pattern géométrique (cercle / arc / ovale / carré) est sélectionné
/// déterministiquement à partir de [seed] via [selectPattern]. Le drag
/// utilise un [Listener] raw pour la précision du hit-test. Le chemin doré
/// est dessiné par [GoldenPath] en overlay.
class CircularGrid extends StatefulWidget {
  const CircularGrid({
    required this.letters,
    required this.selectedIndices,
    required this.hintRevealedCount,
    required this.answer,
    required this.phase,
    required this.seed,
    required this.onTileEntered,
    required this.onDragEnd,
    super.key,
  });

  /// Lettres dans l'ordre shufflé.
  final List<String> letters;

  /// Indices des tuiles sélectionnées.
  final List<int> selectedIndices;

  /// Nombre de lettres révélées par l'indice.
  final int hintRevealedCount;

  /// Mot réponse (pour colorer les tuiles indice).
  final String answer;

  /// Phase du jeu.
  final Object phase;

  /// Graine de sélection du pattern — `devinette.id` en solo, `answer` en duel
  /// (partagé serveur, donc identique pour les deux joueurs).
  final String seed;

  /// Appelé quand le doigt entre sur une nouvelle tuile (index dans la grille).
  final void Function(int index) onTileEntered;

  /// Appelé quand le doigt est levé.
  final VoidCallback onDragEnd;

  @override
  State<CircularGrid> createState() => _CircularGridState();
}

class _CircularGridState extends State<CircularGrid> {
  static const double _tileSize = 56;

  /// Centres des tuiles en coordonnées locales (calculés dans build).
  final List<Offset> _tileCenters = <Offset>[];

  /// Position courante du doigt pendant le drag.
  Offset? _fingerPosition;

  int? _hitTest(Offset localPos) {
    const hitRadius = _tileSize / 2;
    for (var i = 0; i < _tileCenters.length; i++) {
      final dist = (_tileCenters[i] - localPos).distance;
      if (dist <= hitRadius) return i;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    final idx = _hitTest(event.localPosition);
    if (idx != null) {
      widget.onTileEntered(idx);
    }
    setState(() => _fingerPosition = event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final idx = _hitTest(event.localPosition);
    if (idx != null) {
      widget.onTileEntered(idx);
    }
    setState(() => _fingerPosition = event.localPosition);
  }

  void _onPointerUp(PointerUpEvent event) {
    widget.onDragEnd();
    setState(() => _fingerPosition = null);
  }

  // Centers of selected tiles for the golden path.
  List<Offset> get _selectedCenters => widget.selectedIndices
      .where((i) => i < _tileCenters.length)
      .map((i) => _tileCenters[i])
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final count = widget.letters.length;
    final pattern = selectPattern(widget.seed, count);
    final layout = computeLayout(
      pattern: pattern,
      count: count,
      tileSize: _tileSize,
    );

    _tileCenters
      ..clear()
      ..addAll(layout.centers);

    return SizedBox(
      width: layout.size.width,
      height: layout.size.height,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GoldenPath(
                centers: _selectedCenters,
                fingerPosition: _fingerPosition,
              ),
            ),
            ...List<Widget>.generate(count, (i) {
              final center = layout.centers[i];
              final isSelected = widget.selectedIndices.contains(i);
              final isHint = i < widget.hintRevealedCount;
              return Positioned(
                left: center.dx - _tileSize / 2,
                top: center.dy - _tileSize / 2,
                width: _tileSize,
                height: _tileSize,
                child: _Tile(
                  letter: widget.letters[i],
                  isSelected: isSelected,
                  isHint: isHint,
                  selectionOrder: isSelected
                      ? widget.selectedIndices.indexOf(i) + 1
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Tuile lettre individuelle.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.letter,
    required this.isSelected,
    required this.isHint,
    this.selectionOrder,
  });

  final String letter;
  final bool isSelected;
  final bool isHint;
  final int? selectionOrder;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color textColor;
    final Color borderColor;

    if (isSelected) {
      bg = AppColors.orSoleil;
      textColor = AppColors.vertForet;
      borderColor = AppColors.orChaud;
    } else if (isHint) {
      bg = AppColors.vertClair.withValues(alpha: 0.8);
      textColor = AppColors.ivoire;
      borderColor = AppColors.vertClair;
    } else {
      bg = AppColors.bois;
      textColor = AppColors.ivoire;
      borderColor = AppColors.boisFonce;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: <BoxShadow>[
          // Bottom shadow.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: const Offset(0, 3),
            blurRadius: 6,
          ),
          // Top highlight reflect.
          BoxShadow(
            color: Colors.white.withValues(alpha: isSelected ? 0.4 : 0.15),
            offset: const Offset(0, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          letter,
          style: AppTypography.bebas(
            size: 24,
            color: textColor,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
