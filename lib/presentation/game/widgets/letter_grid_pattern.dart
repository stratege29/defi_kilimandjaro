import 'dart:math' as math;
import 'dart:ui';

/// Disposition géométrique des tuiles lettres.
///
/// **Phase 1** : deux formes possibles selon le nombre de lettres.
/// - [GridPattern.circle] : universel, 4-10 lettres. Wordscapes-style.
/// - [GridPattern.hexagon] : 7 lettres exactement (1 au centre + 6 sur
///   l'anneau). Inspiré du NYT Spelling Bee, ancre visuelle forte.
///
/// **Variété** : pour `count == 7`, [pickPattern] tire au sort 50/50
/// entre circle et hexagon à chaque session (cf. `_CircularGridState`).
/// Pour les autres comptes, circle uniquement.
///
/// L'**ordre des lettres** dans chaque pattern reste aléatoire via le
/// Fisher-Yates de `GameController._shuffleIndices`.
enum GridPattern { circle, hexagon }

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

  /// Indices des tuiles dont la zone de hit-test est volontairement réduite
  /// (40 % du rayon visuel au lieu de 50 %). Utilisé pour les tuiles
  /// internes — typiquement le centre de l'hexagone — où un swipe direct
  /// d'une tuile à l'opposée risquerait de capturer la tuile centrale
  /// alors que ce n'est pas l'intention du joueur.
  final Set<int> smallHitIndices;
}

/// Sélectionne une pattern compatible avec [count] lettres.
///
/// Phase 1 : hexagon disponible uniquement pour count == 7 (1 centre +
/// 6 anneau). 50 % de chance par session, sinon fallback circle. Cette
/// décision est prise UNE SEULE FOIS dans `initState` du grid, puis
/// stable pour toute la durée de la partie.
GridPattern pickPattern(int count, math.Random rng) {
  if (count == 7 && rng.nextBool()) return GridPattern.hexagon;
  return GridPattern.circle;
}

/// Calcule positions et taille canvas pour [count] tuiles dans la
/// pattern donnée. [radiusFit] est le rayon maximum imposé par le
/// viewport (calculé par l'appelant via `LayoutBuilder`).
GridLayout computeLayout({
  required GridPattern pattern,
  required int count,
  required double radiusFit,
  required double tileSize,
  double padding = 12,
}) {
  switch (pattern) {
    case GridPattern.circle:
      return _circleLayout(
        count: count,
        radiusFit: radiusFit,
        tileSize: tileSize,
        padding: padding,
      );
    case GridPattern.hexagon:
      return _hexagonLayout(
        radiusFit: radiusFit,
        tileSize: tileSize,
        padding: padding,
      );
  }
}

GridLayout _circleLayout({
  required int count,
  required double radiusFit,
  required double tileSize,
  required double padding,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  // Rayon idéal pour espacer les tuiles d'au moins 1.6× leur diamètre
  // le long de l'arc → confort visuel et tactile.
  const minRadius = 70.0;
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
  required double radiusFit,
  required double tileSize,
  required double padding,
}) {
  // ringRadius = distance centre canvas → centre de chaque tuile de l'anneau.
  // À ringRadius = tileSize, les tuiles de l'anneau sont jointives (chord
  // = ringRadius car angle entre adjacentes = 60°). À 1.4×, on a 24pt de
  // gap visuel — propre et tactile.
  const idealRing = 84.0; // 60 × 1.4
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
    smallHitIndices: const <int>{0}, // hit-test réduit sur le centre
  );
}
