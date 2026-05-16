import 'dart:math' as math;
import 'dart:ui';

/// Disposition géométrique des tuiles lettres.
///
/// **Patterns disponibles** (sélection aléatoire par session via [pickPattern]) :
///
/// | Pattern    | Counts compatibles | Variante de         |
/// |------------|--------------------|---------------------|
/// | circle     | 4-10 (universel)   | Wordscapes          |
/// | hexagon    | 7 exactement       | NYT Spelling Bee    |
/// | diamond    | 5 exactement       | Codenames           |
/// | zigzag     | 6-8                | Custom              |
/// | twoRows    | 6-7                | Custom (3+3 / 4+3)  |
///
/// Pour chaque count, plusieurs patterns peuvent être éligibles — le tirage
/// est uniforme entre les candidats. Le shuffle des LETTRES dans le pattern
/// reste indépendant (Fisher-Yates dans `GameController._shuffleIndices`).
///
/// **Anti-trap** : les patterns avec tuile interne (hexagon, diamond) ont
/// `smallHitIndices = {0}` — la tuile centrale a un hit-radius réduit à
/// 40 % pour éviter les sélections parasites quand le doigt traverse
/// d'une extrémité à l'opposée.
enum GridPattern { circle, hexagon, diamond, zigzag, twoRows }

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
/// Toujours inclus : `circle` (universel). Les autres patterns rejoignent
/// la liste selon leur compatibilité de count.
List<GridPattern> _candidatesFor(int count) {
  final list = <GridPattern>[GridPattern.circle];
  if (count == 5) list.add(GridPattern.diamond);
  if (count == 6 || count == 7) list.add(GridPattern.twoRows);
  if (count >= 6 && count <= 8) list.add(GridPattern.zigzag);
  if (count == 7) list.add(GridPattern.hexagon);
  return list;
}

/// Tire un pattern uniformément parmi les candidats compatibles avec [count].
/// À appeler UNE SEULE FOIS par partie (cf. `_CircularGridState.initState`).
GridPattern pickPattern(int count, math.Random rng) {
  final candidates = _candidatesFor(count);
  return candidates[rng.nextInt(candidates.length)];
}

/// Calcule positions et taille canvas pour [count] tuiles dans la pattern
/// donnée. [available] est la `Size` du viewport parent (width + height),
/// utilisé pour borner les patterns qui débordent.
GridLayout computeLayout({
  required GridPattern pattern,
  required int count,
  required Size available,
  required double tileSize,
  double padding = 12,
}) {
  switch (pattern) {
    case GridPattern.circle:
      return _circleLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      );
    case GridPattern.hexagon:
      return _hexagonLayout(
        available: available,
        tileSize: tileSize,
        padding: padding,
      );
    case GridPattern.diamond:
      return _diamondLayout(
        available: available,
        tileSize: tileSize,
        padding: padding,
      );
    case GridPattern.zigzag:
      return _zigzagLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      );
    case GridPattern.twoRows:
      return _twoRowsLayout(
        count: count,
        available: available,
        tileSize: tileSize,
        padding: padding,
      );
  }
}

double _radiusFitFromAvailable(Size a, double tileSize, double padding) {
  final smaller = math.min(a.width, a.height);
  return (smaller - tileSize - 2 * padding) / 2;
}

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
/// considérations anti-trap que l'hexagone : swipe N→S ou E→W passe
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
