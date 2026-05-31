import 'dart:math' as math;
import 'dart:ui';

/// Disposition géométrique des tuiles lettres.
///
/// **Familles de patterns** (sélection aléatoire par session via
/// [pickPattern]) :
///
/// _Réguliers curés_ — formes nettes, symétriques :
/// | Pattern    | Counts compatibles | Variante de         |
/// |------------|--------------------|---------------------|
/// | circle     | universel          | Wordscapes          |
/// | hexagon    | 7 exactement       | NYT Spelling Bee    |
/// | diamond    | 5 exactement       | Codenames           |
/// | zigzag     | 6-8                | Custom              |
/// | twoRows    | 6-7                | Custom (3+3 / 4+3)  |
/// | triangle   | 6, 10              | Empilement pyramide |
/// | arc        | >= 4               | Arc-en-ciel         |
/// | vShape     | >= 5               | Chevron / V         |
/// | grid       | >= 8               | Grille rectangulaire|
/// | star       | 10                 | Étoile 5 branches   |
/// | cross      | 5, 9               | Croix `+`           |
/// | xShape     | 5, 9               | Sautoir `X`         |
/// | caret      | >= 5               | Accent `^`          |
/// | lShape     | >= 5               | Équerre `L`         |
/// | wave       | >= 5               | Sinusoïde           |
/// | spiral     | >= 5               | Phyllotaxie (or)    |
///
/// _Irréguliers procéduraux_ — différents à chaque partie (dépendent du
/// `seed`), jamais deux dispositions identiques :
/// | Pattern    | Counts compatibles | Principe            |
/// |------------|--------------------|---------------------|
/// | scatter    | >= 4               | Éparpillement type  |
/// |            |                    | Poisson + relaxation|
/// | jittered   | >= 4               | Cercle bruité borné |
/// | clusters   | >= 6               | Amas / îlots        |
///
/// La plupart des formes curées non symétriques sont en plus retournées
/// aléatoirement (flip H/V seedé, cf. [_orientable]) pour doubler la variété.
///
/// Pour chaque count, plusieurs patterns sont éligibles
/// ([compatiblePatterns]) — le tirage est uniforme. Le shuffle des LETTRES
/// dans le pattern reste indépendant (Fisher-Yates dans
/// `GameController._shuffleIndices`).
///
/// **Jouabilité stricte garantie** — quel que soit le pattern :
/// - _Anti-chevauchement_ : les patterns procéduraux (et au besoin les
///   curés bornés par un petit viewport) passent par `_relaxOverlaps`, qui
///   écarte toute paire de tuiles trop proche. Un pattern déjà bien espacé
///   n'est pas déformé (la relaxation s'arrête dès la première passe sans
///   collision).
/// - _Anti-piège_ : pour les patterns procéduraux, `_detectTraps` repère
///   automatiquement une tuile posée « sur la ligne » entre deux autres et
///   l'inscrit dans `smallHitIndices` (hit-radius réduit à 40 %), évitant
///   les captures parasites quand le doigt traverse en diagonale. Les
///   patterns curés à tuile centrale (hexagon, diamond) gardent leur
///   `smallHitIndices = {0}` explicite.
enum GridPattern {
  circle,
  hexagon,
  diamond,
  zigzag,
  twoRows,
  triangle,
  arc,
  vShape,
  grid,
  star,
  cross,
  xShape,
  caret,
  lShape,
  wave,
  spiral,
  scatter,
  jittered,
  clusters,
}

class GridLayout {
  const GridLayout({
    required this.centers,
    required this.size,
    this.smallHitIndices = const <int>{},
  });

  /// Centres des tuiles, dans le repère local du widget.
  final List<Offset> centers;

  /// Taille canvas requise pour englober toutes les tuiles + padding.
  final Size size;

  /// Indices à hit-test réduit (40 % du rayon visuel au lieu de 50 %).
  final Set<int> smallHitIndices;
}

/// Patterns éligibles pour [count] lettres.
///
/// Toujours inclus : `circle` (universel). Les patterns procéduraux
/// (`scatter`, `jittered`) et l'arc rejoignent la liste dès 4 lettres ;
/// les autres selon leur compatibilité de count.
List<GridPattern> compatiblePatterns(int count) {
  final list = <GridPattern>[GridPattern.circle];
  if (count >= 4) {
    list
      ..add(GridPattern.scatter)
      ..add(GridPattern.jittered)
      ..add(GridPattern.arc);
  }
  if (count >= 5) {
    list
      ..add(GridPattern.vShape)
      ..add(GridPattern.caret)
      ..add(GridPattern.lShape)
      ..add(GridPattern.wave)
      ..add(GridPattern.spiral);
  }
  if (count == 5) list.add(GridPattern.diamond);
  if (count == 5 || count == 9) list.add(GridPattern.cross);
  if (count == 5 || count == 9) list.add(GridPattern.xShape);
  if (count == 6 || count == 7) list.add(GridPattern.twoRows);
  if (count >= 6 && count <= 8) list.add(GridPattern.zigzag);
  if (count >= 6) list.add(GridPattern.clusters);
  if (count == 6 || count == 10) list.add(GridPattern.triangle);
  if (count == 7) list.add(GridPattern.hexagon);
  if (count >= 8) list.add(GridPattern.grid);
  if (count == 10) list.add(GridPattern.star);
  return list;
}

/// Tire un pattern uniformément parmi les candidats compatibles avec [count].
/// À appeler UNE SEULE FOIS par partie (cf. `_CircularGridState.initState`).
GridPattern pickPattern(int count, math.Random rng) {
  final candidates = compatiblePatterns(count);
  return candidates[rng.nextInt(candidates.length)];
}

/// Calcule positions et taille canvas pour [count] tuiles dans la pattern
/// donnée. [available] est la `Size` du viewport parent (width + height),
/// utilisé pour borner les patterns qui débordent. [seed] rend les patterns
/// procéduraux (`scatter`, `jittered`) déterministes : `computeLayout` est
/// rappelé à chaque build, un seed stable évite que les tuiles « sautent ».
GridLayout computeLayout({
  required GridPattern pattern,
  required int count,
  required double tileSize,
  Size available = Size.infinite,
  int seed = 0,
  double padding = 12,
}) {
  final raw = switch (pattern) {
    GridPattern.circle => _circleLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.hexagon => _hexagonLayout(
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.diamond => _diamondLayout(
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.zigzag => _zigzagLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.twoRows => _twoRowsLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.triangle => _triangleLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.arc => _arcLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.vShape => _vShapeLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.grid => _gridLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.star => _starLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.cross => _crossLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.xShape => _xShapeLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.caret => _caretLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.lShape => _lShapeLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.wave => _waveLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.spiral => _spiralLayout(
        count: count,
        tileSize: tileSize,
        padding: padding,
      ),
    GridPattern.scatter => _scatterLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
        seed: seed,
      ),
    GridPattern.jittered => _jitteredLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
        seed: seed,
      ),
    GridPattern.clusters => _clustersLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
        seed: seed,
      ),
  };
  // Orientation aléatoire (flip H/V) pour les formes dont le sens n'est pas
  // sémantique : double encore la variété perçue, sans casser la jouabilité
  // (un flip préserve les distances).
  final oriented = _orientable.contains(pattern)
      ? _orient(raw, seed, tileSize, padding)
      : raw;
  // Garantie « tout visible » : aucune forme ne dépasse le viewport.
  return _ensureFits(oriented, available, tileSize, padding);
}

/// Patterns dont l'orientation (haut/bas, gauche/droite) n'est pas porteuse
/// de sens : on peut les retourner aléatoirement pour varier le rendu.
const Set<GridPattern> _orientable = <GridPattern>{
  GridPattern.triangle,
  GridPattern.arc,
  GridPattern.vShape,
  GridPattern.caret,
  GridPattern.lShape,
  GridPattern.wave,
  GridPattern.zigzag,
  GridPattern.twoRows,
  GridPattern.grid,
  GridPattern.cross,
  GridPattern.xShape,
};

/// Retourne (flip H et/ou V, seedé) un layout autour du centre de sa bbox,
/// puis le recadre. Préserve les distances → jouabilité intacte.
GridLayout _orient(
  GridLayout layout,
  int seed,
  double tileSize,
  double padding,
) {
  if (layout.centers.isEmpty) return layout;
  final rng = math.Random(seed ^ 0x5bd1e995);
  final flipH = rng.nextBool();
  final flipV = rng.nextBool();
  if (!flipH && !flipV) return layout;

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in layout.centers) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2;
  final flipped = <Offset>[
    for (final p in layout.centers)
      Offset(
        flipH ? 2 * cx - p.dx : p.dx,
        flipV ? 2 * cy - p.dy : p.dy,
      ),
  ];
  return _packCanvas(flipped, tileSize, padding, layout.smallHitIndices);
}

double _radiusFitFromAvailable(Size a, double tileSize, double padding) {
  final smaller = math.min(a.width, a.height);
  return (smaller - tileSize - 2 * padding) / 2;
}

// ---------------------------------------------------------------------------
// Helpers partagés (jouabilité stricte)
// ---------------------------------------------------------------------------

/// Distance d'un point [p] au segment [a]-[b], mais `infinity` si la
/// projection tombe près d'une extrémité (`t` hors de 0.12..0.88) : on ne
/// veut détecter qu'une tuile réellement « entre » deux autres, pas une
/// tuile alignée mais située au-delà d'un bout.
double _distToSegment(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final lenSq = abx * abx + aby * aby;
  if (lenSq < 1e-6) return (p - a).distance;
  final t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / lenSq;
  if (t <= 0.12 || t >= 0.88) return double.infinity;
  final projX = a.dx + t * abx;
  final projY = a.dy + t * aby;
  final dx = p.dx - projX;
  final dy = p.dy - projY;
  return math.sqrt(dx * dx + dy * dy);
}

/// Indices des tuiles « pièges » : une tuile dont le centre passe à moins
/// de `tileSize * 0.55` de la ligne entre deux autres tuiles. Un swipe
/// direct entre ces deux-là frôlerait la tuile intermédiaire — on réduit
/// son hit-radius via `smallHitIndices`.
Set<int> _detectTraps(List<Offset> pts, double tileSize) {
  final band = tileSize * 0.55;
  final traps = <int>{};
  for (var k = 0; k < pts.length; k++) {
    var flagged = false;
    for (var i = 0; i < pts.length && !flagged; i++) {
      if (i == k) continue;
      for (var j = i + 1; j < pts.length; j++) {
        if (j == k) continue;
        if (_distToSegment(pts[k], pts[i], pts[j]) < band) {
          traps.add(k);
          flagged = true;
          break;
        }
      }
    }
  }
  return traps;
}

/// Écarte in-place toute paire de tuiles plus proches que [minDist] par
/// relaxation itérative (chaque collision pousse les deux centres de moitié
/// de l'écart manquant). S'arrête dès qu'une passe ne bouge plus rien : un
/// pattern déjà bien espacé n'est donc pas déformé.
void _relaxOverlaps(List<Offset> pts, double minDist) {
  const iters = 40;
  final rng = math.Random(7);
  for (var pass = 0; pass < iters; pass++) {
    var moved = false;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        var dx = pts[j].dx - pts[i].dx;
        var dy = pts[j].dy - pts[i].dy;
        var d = math.sqrt(dx * dx + dy * dy);
        if (d < 1e-3) {
          final a = rng.nextDouble() * 2 * math.pi;
          dx = math.cos(a);
          dy = math.sin(a);
          d = 1;
        }
        if (d < minDist) {
          final push = (minDist - d) / 2 + 0.5;
          final ux = dx / d;
          final uy = dy / d;
          pts[i] = Offset(pts[i].dx - ux * push, pts[i].dy - uy * push);
          pts[j] = Offset(pts[j].dx + ux * push, pts[j].dy + uy * push);
          moved = true;
        }
      }
    }
    if (!moved) break;
  }
}

/// Recadre les points dans un canvas positif avec marge [padding] autour des
/// tuiles, et renvoie le `GridLayout` (taille = bbox + tuile + marges).
GridLayout _packCanvas(
  List<Offset> pts,
  double tileSize,
  double padding,
  Set<int> traps,
) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in pts) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  final ox = padding + tileSize / 2 - minX;
  final oy = padding + tileSize / 2 - minY;
  final shifted = <Offset>[
    for (final p in pts) Offset(p.dx + ox, p.dy + oy),
  ];
  final w = (maxX - minX) + tileSize + 2 * padding;
  final h = (maxY - minY) + tileSize + 2 * padding;
  return GridLayout(
    centers: shifted,
    size: Size(w, h),
    smallHitIndices: traps,
  );
}

/// Termine un layout : relaxe les chevauchements, (optionnellement) détecte
/// les pièges, puis recadre. La détection de pièges est invariante par
/// translation, on peut donc l'appliquer avant le recadrage.
GridLayout _finalize(
  List<Offset> pts,
  double tileSize,
  double padding, {
  double minDist = 0,
  bool detectTraps = false,
  Set<int> traps = const <int>{},
}) {
  final md = minDist <= 0 ? tileSize * 1.04 : minDist;
  _relaxOverlaps(pts, md);
  final all = <int>{
    ...traps,
    if (detectTraps) ..._detectTraps(pts, tileSize),
  };
  return _packCanvas(pts, tileSize, padding, all);
}

/// Garantit que le layout TIENT dans [available] (« tout visible, jamais
/// coupé »). Si le canvas naturel dépasse, on met l'arrangement à l'échelle
/// autour de son centre jusqu'à rentrer — la taille des tuiles reste fixe,
/// seul l'espacement se resserre. No-op si [available] est infini (viewport
/// non borné) ou si le layout rentre déjà.
GridLayout _ensureFits(
  GridLayout layout,
  Size available,
  double tileSize,
  double padding,
) {
  if (layout.centers.isEmpty) return layout;
  final aw = available.width;
  final ah = available.height;
  if (!aw.isFinite || !ah.isFinite) return layout;
  if (layout.size.width <= aw && layout.size.height <= ah) return layout;

  final maxSpreadW = aw - tileSize - 2 * padding;
  final maxSpreadH = ah - tileSize - 2 * padding;
  if (maxSpreadW <= 1 || maxSpreadH <= 1) return layout; // écran trop exigu

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in layout.centers) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  final spreadW = maxX - minX;
  final spreadH = maxY - minY;
  var scale = 1.0;
  if (spreadW > maxSpreadW) scale = math.min(scale, maxSpreadW / spreadW);
  if (spreadH > maxSpreadH) scale = math.min(scale, maxSpreadH / spreadH);
  if (scale >= 0.999) return layout;

  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2;
  final scaled = <Offset>[
    for (final p in layout.centers)
      Offset(cx + (p.dx - cx) * scale, cy + (p.dy - cy) * scale),
  ];
  return _packCanvas(scaled, tileSize, padding, layout.smallHitIndices);
}

// ---------------------------------------------------------------------------
// Patterns réguliers curés
// ---------------------------------------------------------------------------

GridLayout _circleLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  const minRadius = 70.0;
  final radiusFit = _radiusFitFromAvailable(available, tileSize, padding);
  final idealRadius = count * tileSize * 1.6 / (2 * math.pi);
  final r = idealRadius.clamp(minRadius, math.max(minRadius, radiusFit));

  final canvas = (r + tileSize / 2 + padding) * 2;
  final c = canvas / 2;
  final centers = <Offset>[
    for (var i = 0; i < count; i++)
      Offset(
        c + r * math.cos(-math.pi / 2 + 2 * math.pi * i / count),
        c + r * math.sin(-math.pi / 2 + 2 * math.pi * i / count),
      ),
  ];
  return GridLayout(centers: centers, size: Size.square(canvas));
}

GridLayout _hexagonLayout({
  required Size available,
  required double tileSize,
  required double padding,
}) {
  const idealRing = 84.0; // 60 × 1.4
  final radiusFit = _radiusFitFromAvailable(available, tileSize, padding);
  final r = idealRing.clamp(tileSize, math.max(tileSize, radiusFit));

  final canvas = (r + tileSize / 2 + padding) * 2;
  final c = canvas / 2;
  final centers = <Offset>[
    Offset(c, c), // index 0 : tuile centrale
    for (var i = 0; i < 6; i++)
      Offset(
        c + r * math.cos(-math.pi / 2 + 2 * math.pi * i / 6),
        c + r * math.sin(-math.pi / 2 + 2 * math.pi * i / 6),
      ),
  ];
  return GridLayout(
    centers: centers,
    size: Size.square(canvas),
    smallHitIndices: const <int>{0},
  );
}

/// Diamant : 1 tuile centrale + 4 cardinaux (N, E, S, W).
///
/// La tuile centrale est en index 0 → `smallHitIndices = {0}` (mêmes
/// considérations anti-piège que l'hexagone : swipe N→S ou E→W passe
/// par le centre, on évite la capture parasite).
GridLayout _diamondLayout({
  required Size available,
  required double tileSize,
  required double padding,
}) {
  const idealArm = 90.0; // distance centre → cardinaux. Gap visuel ~30pt.
  final radiusFit = _radiusFitFromAvailable(available, tileSize, padding);
  final r = idealArm.clamp(tileSize, math.max(tileSize, radiusFit));

  final canvas = (r + tileSize / 2 + padding) * 2;
  final c = canvas / 2;
  final centers = <Offset>[
    Offset(c, c), // 0 : centre
    Offset(c, c - r), // 1 : nord
    Offset(c + r, c), // 2 : est
    Offset(c, c + r), // 3 : sud
    Offset(c - r, c), // 4 : ouest
  ];
  return GridLayout(
    centers: centers,
    size: Size.square(canvas),
    smallHitIndices: const <int>{0},
  );
}

/// Zigzag : 2 colonnes décalées verticalement, alternance gauche/droite.
///
/// Pour 6 lettres :
///     [0]
///         [1]
///     [2]
///         [3]
///     [4]
///         [5]
///
/// Pas de tuile piégée : les colonnes gauche et droite ont des x différents,
/// donc un swipe vertical sur une colonne ne traverse jamais l'autre.
GridLayout _zigzagLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
}) {
  const hSpread = 100.0; // distance horizontale entre les 2 colonnes
  final desiredVStep = tileSize * 0.92; // 55pt — légèrement chevauchant
  // Borner vStep à la hauteur disponible.
  final maxVStep = (count <= 1)
      ? desiredVStep
      : (available.height - tileSize - 2 * padding) / (count - 1);
  final vStep = math.min(desiredVStep, math.max(tileSize * 0.7, maxVStep));

  final canvasW = hSpread + tileSize + 2 * padding;
  final canvasH = (count - 1) * vStep + tileSize + 2 * padding;
  final xLeft = padding + tileSize / 2;
  final xRight = xLeft + hSpread;
  final yTop = padding + tileSize / 2;
  final centers = <Offset>[
    for (var i = 0; i < count; i++)
      Offset(i.isEven ? xLeft : xRight, yTop + i * vStep),
  ];
  return GridLayout(centers: centers, size: Size(canvasW, canvasH));
}

/// Deux rangées horizontales.
///
/// - 6 lettres : 3 + 3 (top row 3, bottom row 3)
/// - 7 lettres : 4 + 3 (top row 4 — la rangée supérieure prend l'extra)
GridLayout _twoRowsLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
}) {
  final topCount = (count / 2).ceil(); // 3 pour 6, 4 pour 7
  final bottomCount = count - topCount;

  const hStep = 76.0; // 60 + 16 gap → confortable
  const vGap = 76.0; // 60 + 16 vertical entre rangées

  final topWidth = (topCount - 1) * hStep + tileSize;
  final bottomWidth = (bottomCount - 1) * hStep + tileSize;
  final widest = math.max(topWidth, bottomWidth);

  final canvasW = widest + 2 * padding;
  final canvasH = tileSize + vGap + tileSize + 2 * padding;
  final cx = canvasW / 2;
  final yTop = padding + tileSize / 2;
  final yBottom = yTop + vGap;

  final centers = <Offset>[
    // Rangée du haut
    for (var i = 0; i < topCount; i++)
      Offset(cx - topWidth / 2 + tileSize / 2 + i * hStep, yTop),
    // Rangée du bas
    for (var i = 0; i < bottomCount; i++)
      Offset(cx - bottomWidth / 2 + tileSize / 2 + i * hStep, yBottom),
  ];

  return GridLayout(centers: centers, size: Size(canvasW, canvasH));
}

/// Triangle (empilement pyramidal) : rangées de 1, 2, 3, (4)… tuiles.
/// Parfait pour les nombres triangulaires (6 = 1+2+3, 10 = 1+2+3+4).
GridLayout _triangleLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final rows = <int>[];
  var placed = 0;
  var rowSize = 1;
  while (placed < count) {
    final n = math.min(rowSize, count - placed);
    rows.add(n);
    placed += n;
    rowSize++;
  }
  final hStep = tileSize * 1.2;
  final vStep = tileSize * 1.08;
  final pts = <Offset>[];
  for (var r = 0; r < rows.length; r++) {
    final n = rows[r];
    final rowW = (n - 1) * hStep;
    for (var c = 0; c < n; c++) {
      pts.add(Offset(-rowW / 2 + c * hStep, r * vStep));
    }
  }
  return _finalize(pts, tileSize, padding);
}

/// Arc-en-ciel : tuiles réparties sur un arc convexe (~207°) ouvert vers
/// le bas. Le rayon a un plancher (`minR`) qui garantit une corde
/// >= tileSize entre voisins même sur petit écran.
GridLayout _arcLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
}) {
  if (count <= 1) {
    return _finalize(<Offset>[Offset.zero], tileSize, padding);
  }
  const span = math.pi * 1.15;
  final fit = _radiusFitFromAvailable(available, tileSize, padding);
  final step = span / (count - 1);
  final minR = tileSize * 1.1 / (2 * math.sin(step / 2));
  final ideal = (count - 1) * tileSize * 1.18 / span;
  final r = ideal.clamp(minR, math.max(minR, fit));
  const start = -math.pi / 2 - span / 2;
  final pts = <Offset>[
    for (var i = 0; i < count; i++)
      Offset(
        r * math.cos(start + i * step),
        r * math.sin(start + i * step),
      ),
  ];
  return _finalize(pts, tileSize, padding);
}

/// Chevron / V : deux bras montant en diagonale depuis un sommet bas
/// (sans tuile au sommet — le V reste ouvert). Le bras gauche prend la
/// tuile en plus pour les counts impairs.
GridLayout _vShapeLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final leftN = (count / 2).ceil();
  final rightN = count - leftN;
  final stepX = tileSize * 0.8;
  final stepY = tileSize * 0.95;
  final pts = <Offset>[];
  for (var i = 0; i < leftN; i++) {
    final k = leftN - i;
    pts.add(Offset(-k * stepX, -k * stepY));
  }
  for (var i = 0; i < rightN; i++) {
    final k = i + 1;
    pts.add(Offset(k * stepX, -k * stepY));
  }
  return _finalize(pts, tileSize, padding);
}

/// Grille rectangulaire : `ceil(sqrt(count))` colonnes, rangées remplies de
/// gauche à droite (dernière rangée éventuellement partielle, centrée).
GridLayout _gridLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final cols = math.sqrt(count.toDouble()).ceil();
  final hStep = tileSize * 1.2;
  final vStep = tileSize * 1.2;
  final pts = <Offset>[];
  var placed = 0;
  var row = 0;
  while (placed < count) {
    final n = math.min(cols, count - placed);
    final rowW = (n - 1) * hStep;
    for (var c = 0; c < n; c++) {
      pts.add(Offset(-rowW / 2 + c * hStep, row * vStep));
      placed++;
    }
    row++;
  }
  return _finalize(pts, tileSize, padding);
}

/// Étoile à 5 branches : pointes externes et internes alternées sur deux
/// rayons. Pensée pour 10 tuiles (5 + 5). `_finalize` relaxe le serrage
/// résiduel si le viewport bride le rayon externe.
GridLayout _starLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
}) {
  final fit = _radiusFitFromAvailable(available, tileSize, padding);
  final outer = 120.0.clamp(tileSize, math.max(tileSize, fit));
  final inner = outer * 0.62;
  final pts = <Offset>[];
  for (var i = 0; i < count; i++) {
    final rad = i.isEven ? outer : inner;
    final ang = -math.pi / 2 + math.pi * i / 5;
    pts.add(Offset(rad * math.cos(ang), rad * math.sin(ang)));
  }
  return _finalize(pts, tileSize, padding, minDist: tileSize * 1.06);
}

/// Croix (plus `+`) : tuile centrale + 4 bras orthogonaux de longueur égale.
/// Pensée pour 5 (1+4) et 9 (1+8). La tuile centrale (index 0) est sur les
/// lignes N↔S et E↔O → hit-radius réduit (`traps = {0}`).
GridLayout _crossLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final arm = (count - 1) ~/ 4; // tuiles par bras
  final step = tileSize * 1.12;
  final pts = <Offset>[Offset.zero];
  for (var k = 1; k <= arm; k++) {
    pts
      ..add(Offset(0, -k * step))
      ..add(Offset(0, k * step))
      ..add(Offset(-k * step, 0))
      ..add(Offset(k * step, 0));
  }
  while (pts.length < count) {
    pts.add(Offset((pts.length - count) * step, (count + 1) * step));
  }
  return _finalize(
    pts,
    tileSize,
    padding,
    minDist: tileSize * 1.1,
    traps: const <int>{0},
  );
}

/// Sautoir (`X`) : tuile centrale + 4 bras en diagonale. Pensée pour 5 et 9.
/// Centre piégé (sur les deux diagonales) → `traps = {0}`.
GridLayout _xShapeLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final arm = (count - 1) ~/ 4;
  final step = tileSize * 0.82;
  final pts = <Offset>[Offset.zero];
  for (var k = 1; k <= arm; k++) {
    pts
      ..add(Offset(-k * step, -k * step))
      ..add(Offset(k * step, -k * step))
      ..add(Offset(-k * step, k * step))
      ..add(Offset(k * step, k * step));
  }
  while (pts.length < count) {
    pts.add(Offset((pts.length - count) * step, (arm + 2) * step));
  }
  return _finalize(
    pts,
    tileSize,
    padding,
    minDist: tileSize * 1.1,
    traps: const <int>{0},
  );
}

/// Accent circonflexe (`^`) : sommet en haut (index 0), deux bras qui
/// descendent. Le bras gauche prend la tuile en plus pour les counts impairs.
GridLayout _caretLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final leftN = (count - 1 + 1) ~/ 2; // hors sommet, arrondi haut à gauche
  final rightN = count - 1 - leftN;
  final stepX = tileSize * 0.8;
  final stepY = tileSize * 0.95;
  final pts = <Offset>[Offset.zero]; // sommet
  for (var k = 1; k <= leftN; k++) {
    pts.add(Offset(-k * stepX, k * stepY));
  }
  for (var k = 1; k <= rightN; k++) {
    pts.add(Offset(k * stepX, k * stepY));
  }
  return _finalize(pts, tileSize, padding);
}

/// Équerre (`L`) : un bras vertical montant + un bras horizontal partant du
/// coin vers la droite. Le coin (index 0) est partagé par les deux bras.
GridLayout _lShapeLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final upN = (count + 1) ~/ 2; // coin compris
  final rightN = count - upN;
  final step = tileSize * 1.12;
  final pts = <Offset>[
    for (var k = 0; k < upN; k++) Offset(0, -k * step),
  ];
  for (var k = 1; k <= rightN; k++) {
    pts.add(Offset(k * step, 0));
  }
  return _finalize(pts, tileSize, padding);
}

/// Vague (sinusoïde horizontale) : tuiles le long d'une sinus, ~1.5 période.
/// Les `x` croissent strictement → pas de tuile piégée entre voisins.
GridLayout _waveLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  final hStep = tileSize * 1.12;
  final amp = tileSize * 0.75;
  final pts = <Offset>[
    for (var i = 0; i < count; i++)
      Offset(
        i * hStep,
        amp * math.sin(i / (count - 1) * math.pi * 3),
      ),
  ];
  return _finalize(pts, tileSize, padding);
}

/// Spirale phyllotaxique (angle d'or) : tuiles posées en escargot, espacement
/// quasi uniforme façon graine de tournesol. Pièges auto-détectés.
GridLayout _spiralLayout({
  required int count,
  required double tileSize,
  required double padding,
}) {
  const golden = 2.39996323; // angle d'or en radians
  final c = tileSize * 1.12;
  final pts = <Offset>[
    for (var i = 0; i < count; i++)
      Offset(
        c * math.sqrt(i + 0.5) * math.cos(i * golden),
        c * math.sqrt(i + 0.5) * math.sin(i * golden),
      ),
  ];
  return _finalize(
    pts,
    tileSize,
    padding,
    minDist: tileSize * 1.08,
    detectTraps: true,
  );
}

// ---------------------------------------------------------------------------
// Patterns irréguliers procéduraux (dépendent du seed)
// ---------------------------------------------------------------------------

/// Éparpillement organique : tirage type Poisson (dart-throwing avec rejet
/// si trop proche), complété par relaxation. Le rayon de la région suit
/// `sqrt(count)` et reste borné par le viewport. Pièges auto-détectés.
GridLayout _scatterLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
  required int seed,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  final rng = math.Random(seed);
  final minDist = tileSize * 1.14;
  final fit = _radiusFitFromAvailable(available, tileSize, padding);
  final wantR = math.sqrt(count.toDouble()) * minDist * 0.7;
  final regionR = wantR.clamp(minDist, math.max(minDist, fit));
  final pts = <Offset>[];
  final maxAttempts = count * 400;
  var attempts = 0;
  while (pts.length < count && attempts < maxAttempts) {
    attempts++;
    final a = rng.nextDouble() * 2 * math.pi;
    final rad = regionR * math.sqrt(rng.nextDouble());
    final p = Offset(rad * math.cos(a), rad * math.sin(a));
    var ok = true;
    for (final q in pts) {
      if ((q - p).distance < minDist) {
        ok = false;
        break;
      }
    }
    if (ok) pts.add(p);
  }
  // Filet de sécurité si le rejet n'a pas pu placer tout le monde : on
  // ajoute au hasard, la relaxation de `_finalize` écartera ensuite.
  while (pts.length < count) {
    final a = rng.nextDouble() * 2 * math.pi;
    final rad = regionR * math.sqrt(rng.nextDouble());
    pts.add(Offset(rad * math.cos(a), rad * math.sin(a)));
  }
  return _finalize(
    pts,
    tileSize,
    padding,
    minDist: minDist,
    detectTraps: true,
  );
}

/// Cercle bruité : positions de base sur un cercle, perturbées par un jitter
/// borné (±0.5 tuile). Le curseur de jitter fait varier le rendu de
/// presque-régulier à franchement irrégulier. Anti-chevauchement + pièges
/// via `_finalize`.
GridLayout _jitteredLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
  required int seed,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  final rng = math.Random(seed);
  const minRadius = 70.0;
  final fit = _radiusFitFromAvailable(available, tileSize, padding);
  final ideal = count * tileSize * 1.7 / (2 * math.pi);
  final r = ideal.clamp(minRadius, math.max(minRadius, fit));
  final minDist = tileSize * 1.08;
  // Amplitude de jitter elle-même bruitée par session : certaines parties
  // sont presque-régulières, d'autres franchement chaotiques.
  final jit = tileSize * (0.5 + rng.nextDouble() * 0.45);
  final pts = <Offset>[];
  for (var i = 0; i < count; i++) {
    final ang = -math.pi / 2 + 2 * math.pi * i / count;
    final jx = (rng.nextDouble() - 0.5) * 2 * jit;
    final jy = (rng.nextDouble() - 0.5) * 2 * jit;
    pts.add(Offset(r * math.cos(ang) + jx, r * math.sin(ang) + jy));
  }
  return _finalize(
    pts,
    tileSize,
    padding,
    minDist: minDist,
    detectTraps: true,
  );
}

/// Grappes : 2-3 amas de tuiles, chaque amas posé autour d'un centre tiré au
/// hasard, les tuiles éparpillées en local. Donne un rendu « îlots » très
/// différent du scatter homogène. Anti-chevauchement + pièges via `_finalize`.
GridLayout _clustersLayout({
  required int count,
  required Size available,
  required double tileSize,
  required double padding,
  required int seed,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  final rng = math.Random(seed);
  final minDist = tileSize * 1.16;
  final nClusters = count >= 8 ? 3 : 2;
  final fit = _radiusFitFromAvailable(available, tileSize, padding);
  final spread = (math.sqrt(count.toDouble()) * minDist * 0.75)
      .clamp(minDist, math.max(minDist, fit));
  final clusterR = tileSize * 1.05;

  // Centres d'amas répartis sur un cercle, pour qu'ils ne se superposent pas.
  final hubs = <Offset>[
    for (var i = 0; i < nClusters; i++)
      Offset(
        spread * math.cos(2 * math.pi * i / nClusters + rng.nextDouble()),
        spread * math.sin(2 * math.pi * i / nClusters + rng.nextDouble()),
      ),
  ];
  final pts = <Offset>[];
  for (var i = 0; i < count; i++) {
    final hub = hubs[i % nClusters];
    final a = rng.nextDouble() * 2 * math.pi;
    final rad = clusterR * math.sqrt(rng.nextDouble());
    pts.add(Offset(hub.dx + rad * math.cos(a), hub.dy + rad * math.sin(a)));
  }
  return _finalize(
    pts,
    tileSize,
    padding,
    minDist: minDist,
    detectTraps: true,
  );
}
