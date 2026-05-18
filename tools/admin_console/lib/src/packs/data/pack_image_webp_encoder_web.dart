// Implémentation web de l'encodeur WebP via HTMLCanvasElement.toBlob.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:web/web.dart' as web;

/// Encode [image] en WebP via la pipeline browser :
///   `img.Image → ImageData (Uint8ClampedArray RGBA) → canvas → Blob
///    → ArrayBuffer → Uint8List`.
///
/// Les tailles 512×512 sont triviales (< 5 ms côté Chrome / Safari).
/// L'encodage WebP est natif au navigateur — pas de polyfill, pas de wasm.
Future<Uint8List> encodeWebpViaPlatform(
  img.Image image, {
  required int quality,
}) async {
  // 1. RGBA bytes → Uint8ClampedList → JSUint8ClampedArray.
  final rgba = image.convert(numChannels: 4, format: img.Format.uint8);
  final pixels = rgba.toUint8List();
  final clamped = Uint8ClampedList.fromList(pixels);

  // ImageData(JSAny dataOrSw, int shOrSw, [JSAny settingsOrSh, ...]) :
  // forme `(data, width, height)`.
  final imageData = web.ImageData(
    clamped.toJS,
    rgba.width,
    rgba.height.toJS,
  );

  // 2. Canvas off-DOM + putImageData.
  final canvas = web.HTMLCanvasElement()
    ..width = rgba.width
    ..height = rgba.height;
  (canvas.getContext('2d')! as web.CanvasRenderingContext2D)
      .putImageData(imageData, 0, 0);

  // 3. toBlob (callback-based) → Completer.
  final completer = Completer<Uint8List>();
  final callback = ((web.Blob? blob) {
    if (blob == null) {
      completer.completeError(
        UnsupportedError('canvas.toBlob a renvoyé null'),
      );
      return;
    }
    blob.arrayBuffer().toDart.then((buffer) {
      final bytes = buffer.toDart.asUint8List();
      completer.complete(Uint8List.fromList(bytes));
    }).onError<Object>((e, _) {
      completer.completeError(e);
    });
  }).toJS;

  canvas.toBlob(
    callback,
    'image/webp',
    (quality / 100.0).toJS,
  );
  return completer.future;
}
