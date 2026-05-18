// Encodeur WebP — interface façade avec conditional import.
//   - VM / tests : stub qui jette `UnsupportedError` (les tests utilisent
//     `prepare()` au lieu de `optimize()`).
//   - Web : implémentation via `HTMLCanvasElement.toBlob('image/webp', q)`.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kilimandjaro_admin/src/packs/data/pack_image_webp_encoder_stub.dart'
    if (dart.library.js_interop) 'pack_image_webp_encoder_web.dart';

class PackImageWebpEncoder {
  const PackImageWebpEncoder();

  /// Encode [image] en WebP qualité [quality] (0..100).
  /// Sur web : utilise canvas.toBlob. Hors web : jette UnsupportedError.
  Future<Uint8List> encodeWebp(img.Image image, {required int quality}) {
    return encodeWebpViaPlatform(image, quality: quality);
  }
}
