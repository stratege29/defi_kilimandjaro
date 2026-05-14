import 'package:defi_kilimandjaro/presentation/game/widgets/letter_grid_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectPattern', () {
    test('is deterministic for same seed and count', () {
      final a = selectPattern('foutou_civ_001', 6);
      final b = selectPattern('foutou_civ_001', 6);
      expect(a, b);
    });

    test('only returns patterns from compatiblePatterns(count)', () {
      for (var n = 3; n <= 9; n++) {
        final allowed = compatiblePatterns(n).toSet();
        for (final seed in const ['a', 'longer_id', 'civ_002', '∅', 'X']) {
          expect(allowed, contains(selectPattern(seed, n)),
              reason: 'seed=$seed count=$n');
        }
      }
    });

    test('square is excluded for count < 4', () {
      expect(compatiblePatterns(3), isNot(contains(GridPattern.square)));
      expect(compatiblePatterns(4), contains(GridPattern.square));
    });
  });

  group('computeLayout', () {
    const tile = 56.0;

    test('produces exactly count centers for each pattern', () {
      for (final p in GridPattern.values) {
        for (var n = 3; n <= 8; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final layout = computeLayout(pattern: p, count: n, tileSize: tile);
          expect(layout.centers.length, n,
              reason: 'pattern=$p count=$n');
        }
      }
    });

    test('all tile centers fit within canvas with tile margin', () {
      for (final p in GridPattern.values) {
        for (var n = 3; n <= 8; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final layout = computeLayout(pattern: p, count: n, tileSize: tile);
          for (final c in layout.centers) {
            expect(c.dx - tile / 2, greaterThanOrEqualTo(0),
                reason: 'pattern=$p count=$n out left');
            expect(c.dy - tile / 2, greaterThanOrEqualTo(0),
                reason: 'pattern=$p count=$n out top');
            expect(c.dx + tile / 2, lessThanOrEqualTo(layout.size.width),
                reason: 'pattern=$p count=$n out right');
            expect(c.dy + tile / 2, lessThanOrEqualTo(layout.size.height),
                reason: 'pattern=$p count=$n out bottom');
          }
        }
      }
    });

    test('tile centers are pairwise non-overlapping', () {
      for (final p in GridPattern.values) {
        for (var n = 3; n <= 8; n++) {
          if (!compatiblePatterns(n).contains(p)) continue;
          final centers = computeLayout(
            pattern: p,
            count: n,
            tileSize: tile,
          ).centers;
          for (var i = 0; i < centers.length; i++) {
            for (var j = i + 1; j < centers.length; j++) {
              final d = (centers[i] - centers[j]).distance;
              expect(d, greaterThan(tile),
                  reason: 'pattern=$p count=$n i=$i j=$j');
            }
          }
        }
      }
    });

    test('handles empty count gracefully', () {
      final layout = computeLayout(
        pattern: GridPattern.circle,
        count: 0,
        tileSize: tile,
      );
      expect(layout.centers, isEmpty);
      expect(layout.size.width, greaterThan(0));
    });
  });
}
