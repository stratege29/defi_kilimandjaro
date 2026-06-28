import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/golden_path.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/letter_grid_pattern.dart';
import 'package:flutter/material.dart';

/// Grille de tuiles lettres avec détection de drag.
///
/// **Disposition** : une forme tirée par session parmi
/// `compatiblePatterns(count)` — réguliers curés (cercle, hexagone, diamant,
/// zigzag, deux-rangées, triangle, arc, V, grille, étoile) et procéduraux
/// irréguliers (`scatter`, `jittered`). Tous **adaptatifs au viewport** via
/// `LayoutBuilder` et garantis jouables (anti-chevauchement + anti-piège, cf.
/// `letter_grid_pattern.dart`). Voir [GridPattern].
///
/// **Aléa préservé sur 2 axes** : la FORME change d'une partie à l'autre
/// (`pickPattern`), et l'ORDRE des lettres dans la forme est shufflé
/// indépendamment (`GameController._shuffleIndices`, Fisher-Yates). Les
/// patterns procéduraux dépendent en plus d'un `_layoutSeed` stable par
/// session.
///
/// **Hit-test** : `Listener` raw pour la précision pendant le drag.
/// **Chemin doré** : dessiné par [GoldenPath] en overlay.
class CircularGrid extends StatefulWidget {
  const CircularGrid({
    required this.letters,
    required this.selectedIndices,
    required this.phase,
    required this.onTileEntered,
    required this.onDragEnd,
    this.theme = PackThemes.defaultTheme,
    this.shuffledIndices = const <int>[],
    this.seed,
    this.hiddenIndices = const <int>{},
    super.key,
  });

  /// Skin de pack appliqué aux tuiles et au chemin. Défaut = « Vert Nuit ».
  final PackTheme theme;

  /// Lettres dans l'ordre shufflé.
  final List<String> letters;

  /// Permutation des indices du pool original. `shuffledIndices[gridIdx]`
  /// donne l'index dans le pool sous-jacent (identité stable d'une lettre).
  /// Sert de clé (`ValueKey`) pour que Flutter trace les tuiles d'un build
  /// à l'autre et anime leurs déplacements via `AnimatedPositioned` quand
  /// wind / earthquake / shuffle permutent les positions.
  ///
  /// Par défaut vide pour rétro-compat avec les call-sites synthétiques
  /// (tests) qui n'ont pas besoin d'animation de swap.
  final List<int> shuffledIndices;

  /// Indices des tuiles sélectionnées.
  final List<int> selectedIndices;

  /// Indices des tuiles masquées par le modifier `fog`. Rendues avec
  /// opacité 0 et ignorées par le hit-test. Tournent toutes les 5 s
  /// côté `GameController`.
  final Set<int> hiddenIndices;

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

class _CircularGridState extends State<CircularGrid>
    with SingleTickerProviderStateMixin {
  /// Diamètre d'une tuile — 68pt (au-dessus du 48pt minimum tactile Material).
  /// Bumpé de 60 → 68 après refonte gameplay : la suppression du chip
  /// "regarder une pub" pleine-largeur libère ~36pt verticaux que la grille
  /// (Expanded) absorbe, ce qui permet d'agrandir les tuiles de ~13 % sans
  /// risque d'overflow sur les configurations à 5–7 lettres.
  static const double _tileSize = 68;

  /// Pattern choisi pour CETTE session — stable durant toute la partie.
  /// Tiré uniformément parmi `compatiblePatterns(count)` (cercle + variantes
  /// curées + procédurales).
  late final GridPattern _pattern;

  /// Seed stable de CETTE session pour les patterns procéduraux (`scatter`,
  /// `jittered`). `computeLayout` étant rappelé à chaque build, un seed fixe
  /// garantit des positions identiques d'un build à l'autre (sinon les tuiles
  /// « sauteraient » à chaque frame).
  late final int _layoutSeed;

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

  /// Controller de shake déclenché chaque fois que `shuffledIndices`
  /// change (wind / earthquake / shuffle). Translate la grille entière
  /// sur l'axe X en oscillation rapide pour donner un feedback visuel
  /// "ça vient de bouger" au-delà du glissement des tuiles concernées.
  /// Sert aussi de driver pour l'animation du trail doré qui suit les
  /// lettres pendant leur glissement (synchro avec AnimatedPositioned).
  late final AnimationController _shakeCtrl;

  /// Snapshot des points snap du trail JUSTE AVANT un swap. Utilisé
  /// pour interpoler entre l'ancienne position du trail et la nouvelle
  /// pendant l'animation `_shakeCtrl`. Vide hors animation.
  List<Offset> _oldSnapPoints = const <Offset>[];

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _pattern = pickPattern(widget.letters.length, rng);
    _layoutSeed = rng.nextInt(1 << 31);
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CircularGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTrailWithSelection(oldWidget.selectedIndices.length);
    // Détecte un changement de permutation pour déclencher le shake.
    // On compare entry-par-entry — listEquals serait plus lourd ; ici la
    // taille reste constante donc une boucle suffit.
    final newPerm = widget.shuffledIndices;
    final oldPerm = oldWidget.shuffledIndices;
    if (newPerm.length == oldPerm.length && newPerm.isNotEmpty) {
      var changed = false;
      for (var i = 0; i < newPerm.length; i++) {
        if (newPerm[i] != oldPerm[i]) {
          changed = true;
          break;
        }
      }
      if (changed) {
        // Capture l'ancien trail AVANT le rebuild pour pouvoir interpoler
        // pendant l'animation et donner l'illusion que le trait glisse
        // avec les lettres (synchro avec AnimatedPositioned).
        _oldSnapPoints = List<Offset>.from(_trail);
        _shakeCtrl
          ..reset()
          ..forward();
        // La re-synchro effective des snap points se fait dans build()
        // une fois _tileCenters mis à jour par le layout. Tenter de
        // rebuild ici lit des centres potentiellement obsolètes.
      }
    }
  }

  /// Points actuels du trail à afficher, en tenant compte de l'animation
  /// de swap en cours. Pendant `_shakeCtrl.isAnimating` ET si on a un
  /// snapshot de la même taille, on lerp ancien→nouveau via la même
  /// courbe que `AnimatedPositioned` (easeInOutCubic, durée 450 ms) —
  /// le trait glisse donc en synchro avec les tuiles. Hors animation,
  /// on rend `_trail` tel quel.
  List<Offset> get _animatedTrail {
    if (!_shakeCtrl.isAnimating ||
        _oldSnapPoints.length != _trail.length ||
        _trail.isEmpty) {
      return _trail;
    }
    final t = Curves.easeInOutCubic.transform(_shakeCtrl.value);
    return List<Offset>.generate(_trail.length, (i) {
      return Offset.lerp(_oldSnapPoints[i], _trail[i], t) ?? _trail[i];
    });
  }

  /// Synchronise IN-PLACE les snap points de `_trail` avec les centres
  /// actuels des tuiles sélectionnées. Appelé à chaque `build()` après
  /// la mise à jour de `_tileCenters` pour garantir que le golden path
  /// reste collé aux lettres, même si :
  /// - un swap (wind / earthquake / shuffle) vient de bouger les lettres
  /// - le layout change (resize, rotation)
  /// - une lettre sélectionnée bouge entre 2 frames
  ///
  /// Préserve les éventuels points free-form (queue du drag) entre les
  /// snaps — seul les snap points sont écrasés.
  void _syncTrailSnapPointsToTileCenters() {
    if (widget.selectedIndices.length != _letterTrailIndices.length) return;
    for (var k = 0; k < widget.selectedIndices.length; k++) {
      final gridIdx = widget.selectedIndices[k];
      final snapTrailIdx = _letterTrailIndices[k];
      if (snapTrailIdx >= _trail.length || gridIdx >= _tileCenters.length) {
        continue;
      }
      _trail[snapTrailIdx] = _tileCenters[gridIdx];
    }
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
      // Une tuile masquée par le fog ne capte pas le touch — le doigt
      // passe « à travers » comme si la case n'existait pas.
      if (widget.hiddenIndices.contains(i)) continue;
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
        final isLastSelected =
            widget.selectedIndices.isNotEmpty &&
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
          seed: _layoutSeed,
        );

        _tileCenters
          ..clear()
          ..addAll(layout.centers);
        _smallHitIndices = layout.smallHitIndices;
        // Garantit que les snap points du golden path sont collés aux
        // tuiles sélectionnées à chaque build, indépendamment du timing
        // de `didUpdateWidget` (qui voit potentiellement un `_tileCenters`
        // périmé entre 2 frames).
        _syncTrailSnapPointsToTileCenters();

        return SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: AnimatedBuilder(
            animation: _shakeCtrl,
            builder: (context, child) {
              // 3 oscillations sur la durée du controller (450 ms), amplitude
              // 8 px, fade-out linéaire pour que le shake s'atténue.
              final t = _shakeCtrl.value;
              final amplitude = 8.0 * (1.0 - t);
              final offsetX = math.sin(t * math.pi * 6) * amplitude;
              return Transform.translate(
                offset: Offset(offsetX, 0),
                child: child,
              );
            },
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    // AnimatedBuilder INTERNE écoutant `_shakeCtrl` :
                    // garantit que `_animatedTrail` est ré-évalué à
                    // chaque frame de l'animation. Sans ça, le getter
                    // est lu une seule fois dans le `child:` du
                    // AnimatedBuilder externe (qui n'est construit
                    // qu'une fois — c'est précisément l'optim du
                    // `child:` Flutter) et le trail reste figé.
                    child: AnimatedBuilder(
                      animation: _shakeCtrl,
                      builder: (context, _) {
                        return GoldenPath(
                          points: _animatedTrail,
                          fingerPosition: _fingerPosition,
                          color: widget.theme.path,
                        );
                      },
                    ),
                  ),
                  ...List<Widget>.generate(count, (i) {
                    final center = layout.centers[i];
                    final isSelected = widget.selectedIndices.contains(i);
                    final isHidden = widget.hiddenIndices.contains(i);
                    // Clé stable : si shuffledIndices est fourni, on prend
                    // l'index du pool sous-jacent (identité de la lettre,
                    // stable à travers les permutations). Sinon fallback
                    // sur l'index grille (comportement legacy sans anim).
                    final stableKey = widget.shuffledIndices.length == count
                        ? ValueKey<int>(widget.shuffledIndices[i])
                        : ValueKey<int>(-(i + 1));
                    return AnimatedPositioned(
                      key: stableKey,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeInOutCubic,
                      left: center.dx - _tileSize / 2,
                      top: center.dy - _tileSize / 2,
                      width: _tileSize,
                      height: _tileSize,
                      child: AnimatedOpacity(
                        // Fog : fade-out à 0 quand la tuile est masquée,
                        // re-fade-in quand elle ré-apparaît.
                        duration: const Duration(milliseconds: 400),
                        opacity: isHidden ? 0.0 : 1.0,
                        child: _Tile(
                          letter: widget.letters[i],
                          isSelected: isSelected,
                          theme: widget.theme,
                          selectionOrder: isSelected
                              ? widget.selectedIndices.indexOf(i) + 1
                              : null,
                        ),
                      ),
                    );
                  }),
                ],
              ),
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
    required this.theme,
    this.selectionOrder,
  });

  final String letter;
  final bool isSelected;
  final PackTheme theme;
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
    // Tuile « sculptée » : carré aux coins doux, dégradé bronze (or à la
    // sélection), lèvre 3D en bas + ombre ambiante, lettre foncée crisp.
    final theme = widget.theme;
    final List<Color> gradient;
    final Color edge;
    final Color textColor;
    final selected = widget.isSelected;

    if (selected) {
      gradient = <Color>[
        Color.lerp(theme.tileSelected, AppColors.textePrimaire, 0.22)!,
        theme.tileSelected,
      ];
      edge = theme.tileSelectedEdge;
      textColor = theme.tileText;
    } else {
      gradient = <Color>[
        Color.lerp(theme.tile, AppColors.textePrimaire, 0.16)!,
        theme.tile,
      ];
      edge = theme.tileEdge;
      textColor = theme.tileText;
    }

    // ShapeDecoration (et non BoxDecoration) pour que la lèvre 3D, l'ombre
    // ambiante et le halo suivent la forme du skin — y compris hexagone /
    // losange. Les ombres restent GPU-safe (blur sans MaskFilter).
    final tile = DecoratedBox(
      decoration: ShapeDecoration(
        shape: _tileShapeBorder(theme.tileShape),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradient,
        ),
        shadows: <BoxShadow>[
          // Lèvre sculptée (extrusion 3D bas).
          BoxShadow(color: edge, offset: const Offset(0, 4)),
          // Ombre ambiante portée.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            offset: const Offset(0, 8),
            blurRadius: 12,
          ),
          // Halo lumineux à la sélection (teinté par le skin).
          if (selected)
            BoxShadow(
              color: theme.tileSelected.withValues(alpha: 0.5),
              blurRadius: 22,
            ),
        ],
      ),
      child: Center(
        child: Text(
          widget.letter,
          style: AppTypography.bebas(
            size: 28,
            color: textColor,
            letterSpacing: 0,
            weight: FontWeight.w800,
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

/// Forme de la tuile selon le skin du pack.
///
/// `sculpted` / `rounded` = rectangles à coins plus ou moins doux ;
/// `hex` / `diamond` = polygones réguliers inscrits.
ShapeBorder _tileShapeBorder(TileShape shape) {
  switch (shape) {
    case TileShape.sculpted:
      return BorderRadius.circular(AppSpacing.radiusMd).toRoundedRectBorder();
    case TileShape.rounded:
      return BorderRadius.circular(28).toRoundedRectBorder();
    case TileShape.hex:
      // Hexagone à sommet plat (rotation 30°).
      return const _PolygonBorder(sides: 6, rotation: math.pi / 6);
    case TileShape.diamond:
      return const _PolygonBorder(sides: 4);
  }
}

extension on BorderRadius {
  RoundedRectangleBorder toRoundedRectBorder() =>
      RoundedRectangleBorder(borderRadius: this);
}

/// [OutlinedBorder] traçant un polygone régulier inscrit dans la boîte.
///
/// Utilisé pour les tuiles `hex` / `diamond`. `paintInterior` permet à
/// [ShapeDecoration] de remplir le polygone avec le dégradé (et non sa boîte
/// englobante), et `getOuterPath` fait suivre les ombres à la forme.
class _PolygonBorder extends OutlinedBorder {
  const _PolygonBorder({required this.sides, this.rotation = 0});

  /// Nombre de côtés (≥ 3).
  final int sides;

  /// Rotation de départ (radians) — oriente le polygone.
  final double rotation;

  Path _polygon(Rect rect) {
    final center = rect.center;
    final radius = math.min(rect.width, rect.height) / 2;
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = rotation + i * 2 * math.pi / sides;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _polygon(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _polygon(rect);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) {
    canvas.drawPath(_polygon(rect), paint);
  }

  @override
  bool get preferPaintInterior => true;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  _PolygonBorder copyWith({BorderSide? side}) => this;

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) =>
      other is _PolygonBorder &&
      other.sides == sides &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(sides, rotation);
}
