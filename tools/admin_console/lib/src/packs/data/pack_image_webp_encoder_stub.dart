// Stub VM-side de l'encodeur WebP.
// Le binaire de prod cible Flutter web — le stub n'est utilisé qu'en VM
// (jamais en prod) et permet d'exécuter les tests pure-Dart sans la
// dépendance `package:web` qui ne compile pas en VM.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:image/image.dart' as img;

Future<Uint8List> encodeWebpViaPlatform(
  img.Image image, {
  required int quality,
}) {
  throw UnsupportedError(
    "encodeWebp n'est disponible qu'en Flutter web "
    '(la console est buildée en --target web).',
  );
}
