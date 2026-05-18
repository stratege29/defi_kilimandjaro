import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kilimandjaro_admin/src/packs/data/pack_image_optimizer.dart';

/// Génère un PNG aléatoire de dimensions (w, h) — outil pour les tests.
Uint8List _makePng(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, x % 255, y % 255, (x + y) % 255, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  const optimizer = PackImageOptimizer();

  group('PackImageOptimizer.prepare — validation', () {
    test('rejette les inputs > 10 MiB sans tenter de décoder', () {
      final tooBig = Uint8List(11 * 1024 * 1024);
      expect(
        () => optimizer.prepare(tooBig),
        throwsA(isA<InputTooLargeException>()),
      );
    });

    test('rejette les inputs au format non reconnu', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(
        () => optimizer.prepare(garbage),
        throwsA(isA<InputDecodeException>()),
      );
    });

    test('rejette les inputs < 256 px (côté court)', () {
      final tooSmall = _makePng(200, 400);
      expect(
        () => optimizer.prepare(tooSmall),
        throwsA(isA<InputDimensionsTooSmallException>()),
      );
    });
  });

  group('PackImageOptimizer.prepare — pipeline', () {
    test("produit une image 512×512 à partir d'un input carré", () {
      final input = _makePng(800, 800);
      final prepared = optimizer.prepare(input);
      expect(prepared.image.width, PackImageSpec.outputSize);
      expect(prepared.image.height, PackImageSpec.outputSize);
    });

    test('center-crop puis resize pour un input portrait', () {
      // 600×1200 → square 600×600 (centré) → resize 512×512.
      final input = _makePng(600, 1200);
      final prepared = optimizer.prepare(input);
      expect(prepared.image.width, PackImageSpec.outputSize);
      expect(prepared.image.height, PackImageSpec.outputSize);
    });

    test('center-crop puis resize pour un input landscape', () {
      // 1500×500 → square 500×500 → resize 512×512 (upscale léger).
      final input = _makePng(1500, 500);
      final prepared = optimizer.prepare(input);
      expect(prepared.image.width, PackImageSpec.outputSize);
      expect(prepared.image.height, PackImageSpec.outputSize);
    });

    test('accepte exactement la dimension minimale 256×256', () {
      final input = _makePng(256, 256);
      final prepared = optimizer.prepare(input);
      expect(prepared.image.width, PackImageSpec.outputSize);
    });
  });
}
