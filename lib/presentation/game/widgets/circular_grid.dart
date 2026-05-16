import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/golden_path.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/letter_grid_pattern.dart';
import 'package:flutter/material.dart';

/// Grille circulaire de tuiles lettres avec détection de drag.
///
/// **Disposition** : cercle unique, rayon **adaptatif au viewport parent**
/// via `LayoutBuilder` — plus jamais d'overflow horizontal ni de tuile
/// clippée en bas d'écran. Les variantes géométriques (arc/oval/square)
/// supprimées : un Word Connect world-class garde un arrangement
/// reconnaissable et constant.
///
/// **Aléa préservé** : l'ordre des lettres autour du cercle est shufflé
/// au démarrage de chaque partie (`GameController._shuffleIndices`,
/// Fisher-Yates). Deux sessions de la même devinette → cercles avec
/// lettres dans un ordre différent.
///
/// **Hit-test** : `Listener` raw pour la précision pendant le drag.
/// **Chemin doré** : dessiné par [GoldenPath] en overlay.
class CircularGrid extends StatefulWidget {
  const CircularGrid({
    required this.letters,
    required this.selectedIndices,
    required this.hintTileIndices,
    required this.phase,
    required this.onTileEntered,
    required this.onDragEnd,
    this.seed,
    super.key,
  });

  /// Lettres dans l'ordre shufflé.
  final List<String> letters;

  /// Indices des tuiles sélectionnées.
  final List<int> selectedIndices;

  /// Indices des tuiles à mettre en surbrillance « indice » — calculés
  /// par `GameState.hintTileIndices` pour pointer la prochaine lettre
  /// de la réponse (et non une tuile aléatoire de la grille).
  final List<int> hintTileIndices;

  /// Phase du jeu.
  final Object phase;

  /// Conservé pour compat (anciennement seed de sélection de pattern).
  /// Désormais ignoré — le cercle est la seule forme.
  final String? seed;

  /// Appelé quand le doigt entre sur une nouvelle tuile (index dans la grille).
  final void Function(int index) onTileEntered;

  /// Appelé quand le doigt est levé.
  final VoidCallback onDragEnd;

  @override
  State<CircularGrid> createState() => _CircularGridState();
}

class _CircularGridState extends State<CircularGrid> {
  /// Diamètre d'une tuile — 60pt (au-dessus du 48pt minimum tactile Material,
  /// confort pouce optimal pour ascending swipe gesture).
  static const double _tileSize = 60;

  /// Pattern choisi pour CETTE session — stable durant toute la partie.
  /// Phase 1 : circle universel, hexagon 50/50 si count == 7.
  late final GridPattern _pattern;

  /// Centres des tuiles en coordonnées locales (mis à jour à chaque layout).
  final List<Offset> _tileCenters = <Offset>[];

  /// Indices dont le hit-test est volontairement réduit (typiquement la
  /// tuile centrale de l'hexagone, pour éviter les captures parasites
  /// quand le doigt glisse d'une tuile à l'opposée).
  Set<int> _smallHitIndices = const <int>{};

  /// Position courante du doigt pendant le drag.
  Offset? _fingerPosition;

  /// Dernière tuile touchée par le hit-test, pour ne notifier
  /// `onTileEntered` qu'aux transitions et éviter le toggle en boucle.
  int? _lastHitIdx;

  /// Tracé brut du doigt depuis le début de la sélection.
  ///
  /// Contient à la fois les positions enregistrées pendant le drag et les
  /// centres des tuiles « snappés » à chaque ajout de lettre. Permet au
  /// `GoldenPath` de dessiner exactement le chemin pris par l'utilisateur
  /// (y compris s'il passe à l'extérieur du cercle des lettres pour relier
  /// deux tuiles).
  final List<Offset> _trail = <Offset>[];

  /// Pour chaque lettre actuellement sélectionnée (dans l'ordre), l'index
  /// dans `_trail` du point « snap » correspondant. Permet de tronquer
  /// proprement le tracé quand la sélection rétrécit (re-tap, slide-back).
  final List<int> _letterTrailIndices = <int>[];

  @override
  void initState() {
    super.initState();
    _pattern = pickPattern(widget.letters.length, math.Random());
  }

  @override
  void didUpdateWidget(CircularGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTrailWithSelection(oldWidget.selectedIndices.length);
  }

  /// Aligne `_trail` / `_letterTrailIndices` sur l'état courant de la
  /// sélection. Appelé après chaque changement de `selectedIndices`.
  void _syncTrailWithSelection(int oldLen) {
    final newLen = widget.selectedIndices.length;
    if (newLen == oldLen) return;
    if (newLen == 0) {
      _trail.clear();
      _letterTrailIndices.clear();
      return;
    }
    if (newLen > oldLen) {
      for (var i = oldLen; i < newLen; i++) {
        final tileIdx = widget.selectedIndices[i];
        if (tileIdx >= _tileCenters.length) continue;
        _trail.add(_tileCenters[tileIdx]);
        _letterTrailIndices.add(_trail.length - 1);
      }
      return;
    }
    // newLen < oldLen : sélection rétrécie → on coupe le tracé après la
    // nouvelle dernière lettre pour repartir proprement de son centre.
    final keepUntil = _letterTrailIndices[newLen - 1] + 1;
    if (keepUntil < _trail.length) {
      _trail.removeRange(keepUntil, _trail.length);
    }
    _letterTrailIndices.removeRange(newLen, _letterTrailIndices.length);
  }

  int? _hitTest(Offset localPos) {
    const fullRadius = _tileSize / 2;
    const smallRadius = _tileSize * 0.40;
    for (var i = 0; i < _tileCenters.length; i++) {
      final dist = (_tileCenters[i] - localPos).distance;
      final r = _smallHitIndices.contains(i) ? smallRadius : fullRadius;
      if (dist <= r) return i;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    final idx = _hitTest(event.localPosition);
    if (idx != null) {
      _lastHitIdx = idx;
      // Tap discret : on délègue toujours (ajoute si nouvelle, retire/tronque
      // si déjà sélectionnée — intentionnel et explicite côté utilisateur).
      widget.onTileEntered(idx);
    }
    setState(() => _fingerPosition = event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Enregistre la position du doigt dans le tracé tant qu'au moins une
    // lettre est sélectionnée (sinon on traînerait des points orphelins).
    if (widget.selectedIndices.isNotEmpty) {
      _trail.add(event.localPosition);
    }
    final idx = _hitTest(event.localPosition);
    if (idx != _lastHitIdx) {
      _lastHitIdx = idx;
      if (idx != null) {
        // Anti-wobble : pendant un drag, on ignore la ré-entrée sur la
        // DERNIÈRE lettre sélectionnée (sinon un léger tremblement du
        // doigt la ferait clignoter). Le retrait reste possible via un
        // tap discret (pointer down) ou un slide-back sur une lettre
        // antérieure du chemin.
        final isLastSelected = widget.selectedIndices.isNotEmpty &&
            widget.selectedIndices.last == idx;
        if (!isLastSelected) {
          widget.onTileEntered(idx);
        }
      }
    }
    setState(() => _fingerPosition = event.localPosition);
  }

  void _onPointerUp(PointerUpEvent event) {
    widget.onDragEnd();
    _lastHitIdx = null;
    // Si la course a été interrompue entre deux lettres (doigt levé à
    // mi-chemin), on retaille le tracé jusqu'au centre de la dernière
    // lettre validée. Sans ça, une « queue » orpheline reste affichée
    // entre la dernière tuile et l'endroit où le doigt s'est levé.
    if (_letterTrailIndices.isNotEmpty) {
      final keepUntil = _letterTrailIndices.last + 1;
      if (keepUntil < _trail.length) {
        _trail.removeRange(keepUntil, _trail.length);
      }
    } else {
      _trail.clear();
    }
    setState(() => _fingerPosition = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = widget.letters.length;
        final available = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity,
        );
        final layout = computeLayout(
          pattern: _pattern,
          count: count,
          available: available,
          tileSize: _tileSize,
        );

        _tileCenters
          ..clear()
          ..addAll(layout.centers);
        _smallHitIndices = layout.smallHitIndices;

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
                    points: _trail,
                    fingerPosition: _fingerPosition,
                  ),
                ),
                ...List<Widget>.generate(count, (i) {
                  final center = layout.centers[i];
                  final isSelected = widget.selectedIndices.contains(i);
                  final isHint = widget.hintTileIndices.contains(i);
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
      },
    );
  }
}

/// Tuile lettre individuelle (60pt).
///
/// **Micro-scale à la sélection** : quand `isSelected` passe à `true`, la
/// tuile bondit de 0.88 → 1.0 sur 120 ms (`Curves.easeOutCirc`). Couplé à
/// la sélection-click haptic du `GameController`, ça crée le moment
/// satisfaisant "Duolingo-like" reconnu en swipe Word Connect.
class _Tile extends StatefulWidget {
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
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with SingleTickerProviderStateMixin {
  late final AnimationController _selectCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    // Controller en mode forward 0→1 sur 220ms. La Tween mappe sur
    // l'échelle visuelle 0.80 → 1.0 et la curve easeOutBack ajoute un
    // léger overshoot (~1.06 pic). Valeur initiale = 1 pour rester
    // stable à scale 1.0 au repos.
    _selectCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _scaleAnim = Tween<double>(
      begin: 0.80,
      end: 1,
    ).animate(CurvedAnimation(parent: _selectCtrl, curve: Curves.easeOutBack));
  }

  @override
  void didUpdateWidget(_Tile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isSelected && widget.isSelected) {
      // Première sélection : reset à 0 puis forward → tween 0.80 → 1.0
      // avec overshoot easeOutBack. Visible et satisfaisant.
      _selectCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _selectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color textColor;
    final Color borderColor;

    if (widget.isSelected) {
      bg = AppColors.orSoleil;
      textColor = AppColors.vertForet;
      borderColor = AppColors.orChaud;
    } else if (widget.isHint) {
      bg = AppColors.vertClair.withValues(alpha: 0.8);
      textColor = AppColors.ivoire;
      borderColor = AppColors.vertClair;
    } else {
      bg = AppColors.bois;
      textColor = AppColors.ivoire;
      borderColor = AppColors.boisFonce;
    }

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: const Offset(0, 3),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Colors.white.withValues(
              alpha: widget.isSelected ? 0.4 : 0.15,
            ),
            offset: const Offset(0, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.letter,
          style: AppTypography.bebas(
            size: 26,
            color: textColor,
            letterSpacing: 0,
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (_, child) =>
          Transform.scale(scale: _scaleAnim.value, child: child),
      child: tile,
    );
  }
}
