// Pipeline d'optimisation client-side d'une image de pack — partie
// pure-Dart (validation + decode + crop + resize). L'encodage WebP est
// dans `pack_image_webp_encoder.dart` (web-only).
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kilimandjaro_admin/src/packs/data/pack_image_webp_encoder.dart';

/// Spécifications verrouillées de l'output (cf. CLAUDE.md / specs produit).
class PackImageSpec {
  const PackImageSpec._();

  /// Côté carré en pixels de l'image finale.
  static const int outputSize = 512;

  /// Quality WebP (0..100 côté pipeline, converti en 0..1 côté canvas).
  static const int webpQuality = 80;

  /// Dimensions minimales acceptées en input (côté le plus petit).
  static const int minInputDim = 256;

  /// Taille maximale acceptée en input (bytes). 10 MiB.
  static const int maxInputBytes = 10 * 1024 * 1024;
}

/// Erreur typée pour différencier les rejets pré-decode des erreurs de
/// pipeline. Chaque sous-classe a un `userMessage` localisé en FR
/// (backoffice = pas de easy_localization).
sealed class PackImageOptimizationException implements Exception {
  const PackImageOptimizationException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class InputTooLargeException extends PackImageOptimizationException {
  const InputTooLargeException(this.sizeBytes)
      : super(
          'Fichier trop volumineux : '
          'taille max acceptée 10 Mo.',
        );

  final int sizeBytes;
}

class InputDimensionsTooSmallException extends PackImageOptimizationException {
  const InputDimensionsTooSmallException(this.width, this.height)
      : super(
          'Dimensions trop petites : '
          'minimum 256×256 px requis.',
        );

  final int width;
  final int height;
}

class InputDecodeException extends PackImageOptimizationException {
  const InputDecodeException()
      : super('Format non reconnu — utilise PNG, JPG ou WebP.');
}

class WebpEncodeException extends PackImageOptimizationException {
  const WebpEncodeException(String detail)
      : super('Échec de la conversion en WebP : $detail');
}

/// Résultat de la pipeline.
class OptimizedImage {
  const OptimizedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  int get sizeBytes => bytes.length;
}

/// Représentation intermédiaire après décodage + crop + resize, avant
/// encodage. Exposée pour permettre des tests unitaires de la logique
/// de cropping sans dépendre du DOM.
class PreparedImage {
  const PreparedImage(this.image);

  final img.Image image;
}

/// Pipeline : decode → square center-crop → resize 512×512 → encode WebP.
///
/// Le décodage / cropping / resize utilise `package:image` (pure-Dart,
/// testable). L'encodage WebP utilise l'API browser `HTMLCanvasElement.
/// toBlob('image/webp', q)` parce que :
///   - `package:image` 4.x n'expose pas d'encodeur WebP (seulement le
///     décodeur) ;
///   - tous les navigateurs supportés par le backoffice (Chrome, Firefox,
///     Safari ≥14, Edge) supportent l'output WebP via canvas ;
///   - on évite ainsi 2 Mo de wasm/lib supplémentaire dans le bundle web.
class PackImageOptimizer {
  const PackImageOptimizer({
    PackImageWebpEncoder encoder = const PackImageWebpEncoder(),
  }) : _encoder = encoder;

  final PackImageWebpEncoder _encoder;

  /// Étape pure-Dart : validation + decode + center-crop + resize.
  /// Sortie : `PreparedImage` de 512×512 prête à encoder.
  PreparedImage prepare(Uint8List inputBytes) {
    if (inputBytes.length > PackImageSpec.maxInputBytes) {
      throw InputTooLargeException(inputBytes.length);
    }

    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const InputDecodeException();
    }

    if (decoded.width < PackImageSpec.minInputDim ||
        decoded.height < PackImageSpec.minInputDim) {
      throw InputDimensionsTooSmallException(decoded.width, decoded.height);
    }

    // Center-crop pour obtenir un carré : on garde le côté le plus court.
    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final cropX = (decoded.width - side) ~/ 2;
    final cropY = (decoded.height - side) ~/ 2;
    final squared = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: side,
      height: side,
    );

    // Resize bilinéaire vers 512×512 (qualité suffisante pour vignette).
    final resized = img.copyResize(
      squared,
      width: PackImageSpec.outputSize,
      height: PackImageSpec.outputSize,
      interpolation: img.Interpolation.linear,
    );

    return PreparedImage(resized);
  }

  /// Pipeline complète : prepare → encode WebP.
  /// Sur web, l'encodage utilise `HTMLCanvasElement.toBlob`.
  /// Sur VM (tests), l'encodeur jette `UnsupportedError` — utiliser
  /// `prepare()` à la place dans les tests pure-Dart.
  Future<OptimizedImage> optimize(Uint8List inputBytes) async {
    final prepared = prepare(inputBytes);
    final encoded = await _encoder.encodeWebp(
      prepared.image,
      quality: PackImageSpec.webpQuality,
    );
    return OptimizedImage(
      bytes: encoded,
      width: prepared.image.width,
      height: prepared.image.height,
    );
  }
}
