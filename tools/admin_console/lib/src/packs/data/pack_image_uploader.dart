// Upload + delete d'une image de pack. API publique = `uploadOptimized` et
// `deleteImage`.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/packs/data/pack_image_optimizer.dart';
import 'package:kilimandjaro_admin/src/packs/data/packs_repository.dart';

/// Résultat d'un upload réussi — les champs ré-écrits sur le doc Firestore
/// `content_packs/{packId}`.
class PackImageUploadResult {
  const PackImageUploadResult({
    required this.imageUrl,
    required this.imagePath,
    required this.imageHash,
    required this.sizeBytes,
  });

  final String imageUrl;
  final String imagePath;
  final String imageHash;
  final int sizeBytes;
}

/// Orchestration : upload bytes optimisés → Cloud Storage → ré-écriture
/// des champs image_* sur le doc Firestore du pack.
///
/// Cache busting : on suffixe l'URL de téléchargement avec ?v={timestamp_ms}
/// pour invalider les CDN downstream (l'overwrite Storage ne suffit pas car
/// les clients gardent la même download URL à long terme).
class PackImageUploader {
  PackImageUploader({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  String _storagePath(String packId) => 'packs/v2/$packId/image.webp';

  /// Upload des bytes WebP 512×512 pour le pack [packId].
  /// Renvoie le résultat (URL + métadonnées) ou jette si erreur réseau.
  Future<PackImageUploadResult> uploadOptimized({
    required String packId,
    required OptimizedImage optimized,
  }) async {
    final path = _storagePath(packId);
    final hash = sha256.convert(optimized.bytes).toString();
    final uploadedAtMs = DateTime.now().millisecondsSinceEpoch;

    // 1. Upload vers Cloud Storage (overwrite).
    final ref = _storage.ref().child(path);
    await ref.putData(
      optimized.bytes,
      SettableMetadata(
        contentType: 'image/webp',
        cacheControl: 'public, max-age=31536000, immutable',
        customMetadata: {
          'packId': packId,
          'hashSha256': hash,
          'sourceWidth': optimized.width.toString(),
          'sourceHeight': optimized.height.toString(),
        },
      ),
    );

    // 2. URL téléchargement + cache busting via query param `?v=<ts>`.
    final baseUrl = await ref.getDownloadURL();
    final separator = baseUrl.contains('?') ? '&' : '?';
    final imageUrl = '$baseUrl${separator}v=$uploadedAtMs';

    // 3. Ré-écriture des champs `image_*` sur le doc Firestore.
    await _firestore.collection('content_packs').doc(packId).set(
      <String, dynamic>{
        'image_url': imageUrl,
        'image_path': path,
        'image_hash': hash,
        'image_updated_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return PackImageUploadResult(
      imageUrl: imageUrl,
      imagePath: path,
      imageHash: hash,
      sizeBytes: optimized.sizeBytes,
    );
  }

  /// Supprime l'image du pack (Storage + champs Firestore).
  ///
  /// Si l'objet Storage n'existe pas, on ignore l'erreur — l'important
  /// est que les champs Firestore soient nettoyés. Pour `image_*` on
  /// utilise `FieldValue.delete()` pour retirer les clés (vs écrire `null`).
  Future<void> deleteImage({
    required String packId,
    required String storagePath,
  }) async {
    // 1. Tentative de suppression Storage — tolère "object-not-found"
    //    (race avec un overwrite manuel ou re-suppression).
    try {
      await _storage.ref().child(storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }

    // 2. Nettoyage Firestore — on retire les 4 champs.
    await _firestore.collection('content_packs').doc(packId).update(
      <String, Object?>{
        'image_url': FieldValue.delete(),
        'image_path': FieldValue.delete(),
        'image_hash': FieldValue.delete(),
        'image_updated_at': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Helper expose pour les tests : recalcul du hash sans toucher au réseau.
  static String hashOf(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// Helper expose pour les logs : encode hex court (les 12 premiers chars).
  static String shortHash(String hash) =>
      hash.length >= 12 ? hash.substring(0, 12) : hash;

  /// Helper expose pour debug : décodage symbolique d'un base64 URL-safe
  /// (utilisé pour diagnostiquer certains messages d'erreur Storage).
  static String base64UrlDecodeUtf8(String input) {
    final padded = input.padRight((input.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64Url.decode(padded));
  }
}

// -----------------------------------------------------------------------------
// Providers
// -----------------------------------------------------------------------------

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (_) => FirebaseStorage.instance,
);

final packImageOptimizerProvider = Provider<PackImageOptimizer>(
  (_) => const PackImageOptimizer(),
);

final packImageUploaderProvider = Provider<PackImageUploader>((ref) {
  return PackImageUploader(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});
