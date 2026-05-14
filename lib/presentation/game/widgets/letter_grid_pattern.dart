import 'dart:math' as math;
import 'dart:ui';

/// Forme géométrique sur laquelle disposer les tuiles lettres.
///
/// Toutes les variantes garantissent que les tuiles sont sur un contour convexe
/// (cercle, ovale, arc, périmètre carré) — aucune tuile n'est piégée à
/// l'intérieur, ce qui évite les sélections parasites lors d'un drag entre
/// deux lettres non adjacentes.
enum GridPattern { circle, arc, oval, square }

class GridLayout {
  const GridLayout({required this.centers, required this.size});

  /// Centres des tuiles, dans le repère local du widget.
  final List<Offset> centers;

  /// Taille canvas requise pour englober toutes les tuiles + padding.
  final Size size;
}

/// Patterns compatibles avec un nombre de lettres donné.
List<GridPattern> compatiblePatterns(int count) {
  return <GridPattern>[
    GridPattern.circle,
    GridPattern.arc,
    GridPattern.oval,
    if (count >= 4) GridPattern.square,
  ];
}

/// Sélection déterministe d'un pattern à partir d'une [seed] (id devinette
/// en solo, mot réponse en duel — partagé serveur).
GridPattern selectPattern(String seed, int count) {
  final patterns = compatiblePatterns(count);
  final hash = seed.hashCode.abs();
  return patterns[hash % patterns.length];
}

/// Calcule positions et taille canvas pour [pattern] avec [count] tuiles.
///
/// [tileSize] est le diamètre d'une tuile, [minRadius]/[radiusPerTile]
/// reproduisent la formule rayon = base + n × facteur du cercle d'origine.
GridLayout computeLayout({
  required GridPattern pattern,
  required int count,
  required double tileSize,
  double minRadius = 80,
  double radiusPerTile = 10,
  double padding = 16,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  final r = minRadius + count * radiusPerTile;
  switch (pattern) {
    case GridPattern.circle:
      return _circle(count, r, tileSize, padding);
    case GridPattern.arc:
      return _arc(count, r, tileSize, padding);
    case GridPattern.oval:
      return _oval(count, r, tileSize, padding);
    case GridPattern.square:
      return _square(count, r, tileSize, padding);
  }
}

GridLayout _circle(int n, double r, double t, double pad) {
  final size = (r + t / 2 + pad) * 2;
  final c = size / 2;
  final centers = <Offset>[
    for (var i = 0; i < n; i++)
      _onCircle(c, c, r, -math.pi / 2 + 2 * math.pi * i / n),
  ];
  return GridLayout(centers: centers, size: Size.square(size));
}

GridLayout _arc(int n, double r, double t, double pad) {
  // Demi-cercle haut (de gauche à droite) — évoque le pont d'une kora.
  final width = (r + t / 2 + pad) * 2;
  final height = r + t + pad * 2;
  final cx = width / 2;
  final cy = height - (t / 2 + pad);
  final centers = <Offset>[];
  if (n == 1) {
    centers.add(Offset(cx, cy - r));
  } else {
    for (var i = 0; i < n; i++) {
      final angle = -math.pi + math.pi * i / (n - 1);
      centers.add(_onCircle(cx, cy, r, angle));
    }
  }
  return GridLayout(centers: centers, size: Size(width, height));
}

GridLayout _oval(int n, double r, double t, double pad) {
  final rx = r * 1.25;
  final ry = r * 0.8;
  final width = (rx + t / 2 + pad) * 2;
  final height = (ry + t / 2 + pad) * 2;
  final cx = width / 2;
  final cy = height / 2;
  final centers = <Offset>[
    for (var i = 0; i < n; i++)
      Offset(
        cx + rx * math.cos(-math.pi / 2 + 2 * math.pi * i / n),
        cy + ry * math.sin(-math.pi / 2 + 2 * math.pi * i / n),
      ),
  ];
  return GridLayout(centers: centers, size: Size(width, height));
}

GridLayout _square(int n, double r, double t, double pad) {
  final side = 2 * r;
  final size = side + t + 2 * pad;
  final c = size / 2;
  final half = side / 2;
  final perim = 4 * side;
  final centers = <Offset>[];
  for (var i = 0; i < n; i++) {
    final d = perim * i / n;
    final Offset local;
    if (d < side) {
      local = Offset(-half + d, -half);
    } else if (d < 2 * side) {
      local = Offset(half, -half + (d - side));
    } else if (d < 3 * side) {
      local = Offset(half - (d - 2 * side), half);
    } else {
      local = Offset(-half, half - (d - 3 * side));
    }
    centers.add(Offset(c + local.dx, c + local.dy));
  }
  return GridLayout(centers: centers, size: Size.square(size));
}

Offset _onCircle(double cx, double cy, double r, double angle) {
  return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
}
