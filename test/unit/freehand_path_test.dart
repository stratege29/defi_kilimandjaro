import 'package:defi_kilimandjaro/core/geometry/freehand_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests de [FreehandPath.isSelfIntersecting] — base du bonus « À main levée ».
void main() {
  group('FreehandPath.isSelfIntersecting — cas non croisés', () {
    test('liste vide / trop courte → false', () {
      expect(FreehandPath.isSelfIntersecting(const <Offset>[]), isFalse);
      expect(
        FreehandPath.isSelfIntersecting(const <Offset>[Offset.zero]),
        isFalse,
      );
      expect(
        FreehandPath.isSelfIntersecting(
          const <Offset>[Offset.zero, Offset(10, 0)],
        ),
        isFalse,
      );
    });

    test('ligne droite (3 points alignés) → false', () {
      expect(
        FreehandPath.isSelfIntersecting(
          const <Offset>[Offset.zero, Offset(10, 0), Offset(20, 0)],
        ),
        isFalse,
      );
    });

    test('chemin simple en L (4 points) → false', () {
      expect(
        FreehandPath.isSelfIntersecting(
          const <Offset>[
            Offset.zero,
            Offset(40, 0),
            Offset(40, 40),
            Offset(80, 40),
          ],
        ),
        isFalse,
      );
    });

    test('courbe convexe ample (demi-cercle discrétisé) → false', () {
      const pts = <Offset>[
        Offset.zero,
        Offset(20, 30),
        Offset(50, 40),
        Offset(80, 30),
        Offset(100, 0),
      ];
      expect(FreehandPath.isSelfIntersecting(pts), isFalse);
    });

    test('petit dépassement de tuile puis correction → false', () {
      // Cas réel capturé sur device : le doigt part de la 1re lettre, dépasse
      // de ~24px, puis revient pour repartir vers le reste du mot. Ce cusp de
      // correction ne doit PAS annuler le bonus (absorbé par la tolérance).
      const pts = <Offset>[
        Offset(73, 46),
        Offset(93.8, 57.5), // dépassement
        Offset(84.8, 52.9), // retour…
        Offset(77.8, 48.2),
        Offset(69.8, 42.9),
        Offset(60.8, 37.5),
        Offset(46.5, 31.2),
        Offset(25.8, 26.9),
      ];
      expect(FreehandPath.isSelfIntersecting(pts), isFalse);
    });

    test('jitter sous la tolérance sur une ligne droite → false', () {
      // Micro-tremblement < 6px : doit être absorbé par la simplification.
      const pts = <Offset>[
        Offset.zero,
        Offset(20, 1),
        Offset(40, -1),
        Offset(60, 1),
        Offset(80, 0),
        Offset(100, -1),
      ];
      expect(FreehandPath.isSelfIntersecting(pts), isFalse);
    });
  });

  group('FreehandPath.isSelfIntersecting — cas croisés', () {
    test('figure en 8 (croisement franc au centre) → true', () {
      const pts = <Offset>[
        Offset.zero,
        Offset(40, 40),
        Offset(40, 0),
        Offset(0, 40),
      ];
      expect(FreehandPath.isSelfIntersecting(pts), isTrue);
    });

    test('boucle fermée qui repasse sur le trait → true', () {
      // Part, fait une boucle, et recroise le premier segment.
      const pts = <Offset>[
        Offset.zero,
        Offset(100, 0),
        Offset(100, 40),
        Offset(50, 40),
        Offset(50, -20),
      ];
      expect(FreehandPath.isSelfIntersecting(pts), isTrue);
    });

    test('retour-en-arrière (slide-back) qui retrace le segment → true', () {
      // A→B→C puis retour vers B passe sur le segment B→C (colinéaire).
      const pts = <Offset>[
        Offset.zero,
        Offset(40, 0),
        Offset(80, 0),
        Offset(80, 30),
        Offset(40, 30),
        Offset(60, 0), // recroise le segment A→C
      ];
      expect(FreehandPath.isSelfIntersecting(pts), isTrue);
    });
  });
}
