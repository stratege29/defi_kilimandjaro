import 'dart:math' as math;
import 'dart:ui';

import 'package:defi_kilimandjaro/presentation/game/widgets/letter_grid_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Viewport généreux : on veut tester la GÉOMÉTRIE des patterns sans qu'ils
  // soient bridés par le viewport (le clamp est testé à part).
  const big = Size(2000, 2000);
  const tile = 56.0;

  group('compatiblePatterns', () {
    test('inclut toujours circle, jamais vide', () {
      for (var n = 3; n <= 10; n++) {
        expect(compatiblePatterns(n), contains(GridPattern.circle));
        expect(compatiblePatterns(n), isNotEmpty);
      }
    });

    test('patterns procéduraux à partir de 4 lettres seulement', () {
      expect(compatiblePatterns(3), isNot(contains(GridPattern.scatter)));
      expect(compatiblePatterns(3), isNot(contains(GridPattern.jittered)));
      expect(compatiblePatterns(4), contains(GridPattern.scatter));
      expect(compatiblePatterns(4), contains(GridPattern.jittered));
    });

    test('contraintes de count des patterns curés', () {
      expect(compatiblePatterns(7), contains(GridPattern.hexagon));
      expect(compatiblePatterns(6), isNot(contains(GridPattern.hexagon)));
      expect(compatiblePatterns(5), contains(GridPattern.diamond));
      expect(compatiblePatterns(10), contains(GridPattern.star));
      expect(compatiblePatterns(9), isNot(contains(GridPattern.star)));
      expect(compatiblePatterns(8), contains(GridPattern.grid));
    });
  });

  group('pickPattern', () {
    test('ne retourne que des patterns compatibles', () {
      for (var n = 4; n <= 10; n++) {
        final allowed = compatiblePatterns(n).toSet();
        for (var s = 0; s < 50; s++) {
          expect(allowed, contains(pickPattern(n, math.Random(s))));
        }
      }
    });
  });

  group('computeLayout — invariants jouabilité', () {
    test('produit exactement count centres', () {
      for (final p in GridPattern.values) {
        for (var n = 4; n <= 10; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final layout = computeLayout(
            pattern: p,
            count: n,
            tileSize: tile,
            available: big,
            seed: 42,
          );
          expect(layout.centers.length, n, reason: 'pattern=$p count=$n');
        }
      }
    });

    test('toutes les tuiles tiennent dans le canvas', () {
      for (final p in GridPattern.values) {
        for (var n = 4; n <= 10; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final layout = computeLayout(
            pattern: p,
            count: n,
            tileSize: tile,
            available: big,
            seed: 7,
          );
          for (final c in layout.centers) {
            expect(c.dx - tile / 2, greaterThanOrEqualTo(-0.01),
                reason: 'pattern=$p count=$n hors-gauche');
            expect(c.dy - tile / 2, greaterThanOrEqualTo(-0.01),
                reason: 'pattern=$p count=$n hors-haut');
            expect(c.dx + tile / 2, lessThanOrEqualTo(layout.size.width + 0.01),
                reason: 'pattern=$p count=$n hors-droite');
            expect(c.dy + tile / 2,
                lessThanOrEqualTo(layout.size.height + 0.01),
                reason: 'pattern=$p count=$n hors-bas');
          }
        }
      }
    });

    test('aucune paire de tuiles ne se chevauche (strict)', () {
      for (final p in GridPattern.values) {
        for (var n = 4; n <= 10; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          for (final seed in const <int>[1, 2, 99, 12345]) {
            final centers = computeLayout(
              pattern: p,
              count: n,
              tileSize: tile,
              available: big,
              seed: seed,
            ).centers;
            for (var i = 0; i < centers.length; i++) {
              for (var j = i + 1; j < centers.length; j++) {
                final d = (centers[i] - centers[j]).distance;
                expect(d, greaterThan(tile),
                    reason: 'pattern=$p count=$n seed=$seed i=$i j=$j');
              }
            }
          }
        }
      }
    });

    test('smallHitIndices reste dans les bornes', () {
      for (final p in GridPattern.values) {
        for (var n = 4; n <= 10; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final layout = computeLayout(
            pattern: p,
            count: n,
            tileSize: tile,
            available: big,
            seed: 3,
          );
          for (final idx in layout.smallHitIndices) {
            expect(idx, inInclusiveRange(0, n - 1),
                reason: 'pattern=$p count=$n idx=$idx');
          }
        }
      }
    });

    test('tout tient dans un viewport contraint (jamais coupé)', () {
      // Aire de jeu volontairement petite pour forcer le clamp des grandes
      // formes (triangle 10, grid, star, scatter…).
      const tight = Size(300, 380);
      for (final p in GridPattern.values) {
        for (var n = 4; n <= 10; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final layout = computeLayout(
            pattern: p,
            count: n,
            tileSize: tile,
            available: tight,
            seed: 9,
          );
          expect(layout.size.width, lessThanOrEqualTo(tight.width + 0.01),
              reason: 'pattern=$p count=$n déborde en largeur');
          expect(layout.size.height, lessThanOrEqualTo(tight.height + 0.01),
              reason: 'pattern=$p count=$n déborde en hauteur');
          for (final c in layout.centers) {
            expect(c.dx + tile / 2, lessThanOrEqualTo(tight.width + 0.01),
                reason: 'pattern=$p count=$n tuile hors-droite');
            expect(c.dy + tile / 2, lessThanOrEqualTo(tight.height + 0.01),
                reason: 'pattern=$p count=$n tuile hors-bas');
            expect(c.dx - tile / 2, greaterThanOrEqualTo(-0.01),
                reason: 'pattern=$p count=$n tuile hors-gauche');
            expect(c.dy - tile / 2, greaterThanOrEqualTo(-0.01),
                reason: 'pattern=$p count=$n tuile hors-haut');
          }
        }
      }
    });

    test('count 0 géré proprement', () {
      final layout = computeLayout(
        pattern: GridPattern.circle,
        count: 0,
        tileSize: tile,
      );
      expect(layout.centers, isEmpty);
      expect(layout.size.width, greaterThan(0));
    });
  });

  group('patterns procéduraux — déterminisme & variété', () {
    test('scatter est déterministe pour un même seed', () {
      final a = computeLayout(
        pattern: GridPattern.scatter,
        count: 7,
        tileSize: tile,
        available: big,
        seed: 555,
      ).centers;
      final b = computeLayout(
        pattern: GridPattern.scatter,
        count: 7,
        tileSize: tile,
        available: big,
        seed: 555,
      ).centers;
      expect(a, b);
    });

    test('scatter varie selon le seed', () {
      final a = computeLayout(
        pattern: GridPattern.scatter,
        count: 7,
        tileSize: tile,
        available: big,
        seed: 1,
      ).centers;
      final b = computeLayout(
        pattern: GridPattern.scatter,
        count: 7,
        tileSize: tile,
        available: big,
        seed: 2,
      ).centers;
      expect(a, isNot(equals(b)));
    });

    test('jittered est déterministe pour un même seed', () {
      final a = computeLayout(
        pattern: GridPattern.jittered,
        count: 6,
        tileSize: tile,
        available: big,
        seed: 88,
      ).centers;
      final b = computeLayout(
        pattern: GridPattern.jittered,
        count: 6,
        tileSize: tile,
        available: big,
        seed: 88,
      ).centers;
      expect(a, b);
    });
  });
}
