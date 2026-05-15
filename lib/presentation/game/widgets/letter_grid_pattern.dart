import 'dart:math' as math;
import 'dart:ui';

/// Disposition géométrique des tuiles lettres.
///
/// Une seule forme : **cercle propre** (rayon adaptatif). Les variantes
/// précédentes (arc / oval / square) ont été supprimées car elles brisaient
/// la lisibilité — un Word Connect world-class garde un seul arrangement
/// reconnaissable (cf. Wordscapes, Word Cookies, Spelling Bee).
///
/// L'**ordre des lettres autour du cercle reste aléatoire** : c'est le
/// shuffle Fisher-Yates du `GameController._shuffleIndices(count)` au
/// démarrage de chaque partie qui le garantit. Ce qui était "figé et
/// prévisible" auparavant, c'était la FORME (déterminée par hash de
/// `devinette.id`). La forme est maintenant constante (cercle), seul
/// l'ordre des lettres dedans varie d'une session à l'autre.
class GridLayout {
  const GridLayout({required this.centers, required this.size});

  /// Centres des tuiles, dans le repère local du widget.
  final List<Offset> centers;

  /// Taille canvas requise pour englober toutes les tuiles + padding.
  final Size size;
}

/// Calcule positions et taille canvas pour un cercle de [count] tuiles.
///
/// [radius] est imposé par l'appelant (en pratique : ajusté au viewport via
/// `LayoutBuilder` pour éviter les overflow). [tileSize] est le diamètre
/// d'une tuile, [padding] la marge canvas extérieure.
GridLayout computeCircleLayout({
  required int count,
  required double radius,
  required double tileSize,
  double padding = 16,
}) {
  if (count == 0) {
    final empty = tileSize + padding * 2;
    return GridLayout(centers: const <Offset>[], size: Size.square(empty));
  }
  final canvas = (radius + tileSize / 2 + padding) * 2;
  final c = canvas / 2;
  final centers = <Offset>[
    for (var i = 0; i < count; i++)
      Offset(
        c + radius * math.cos(-math.pi / 2 + 2 * math.pi * i / count),
        c + radius * math.sin(-math.pi / 2 + 2 * math.pi * i / count),
      ),
  ];
  return GridLayout(centers: centers, size: Size.square(canvas));
}
