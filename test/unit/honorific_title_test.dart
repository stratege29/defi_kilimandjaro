import 'package:defi_kilimandjaro/domain/entities/honorific_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HonorificTitle.currentFor', () {
    test('returns null below first threshold', () {
      expect(HonorificTitle.currentFor(0), isNull);
      expect(HonorificTitle.currentFor(4), isNull);
    });

    test('returns Oreille at threshold 5', () {
      expect(
        HonorificTitle.currentFor(5),
        HonorificTitle.oreilleDuVillage,
      );
    });

    test('progression cascade', () {
      expect(
        HonorificTitle.currentFor(24),
        HonorificTitle.oreilleDuVillage,
      );
      expect(
        HonorificTitle.currentFor(25),
        HonorificTitle.gardienDeLaParole,
      );
      expect(HonorificTitle.currentFor(75), HonorificTitle.griotDuFeu);
      expect(
        HonorificTitle.currentFor(199),
        HonorificTitle.griotDuFeu,
      );
      expect(
        HonorificTitle.currentFor(200),
        HonorificTitle.ancetreVivant,
      );
      expect(
        HonorificTitle.currentFor(99999),
        HonorificTitle.ancetreVivant,
      );
    });
  });
}
