import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:http/http.dart' as http;

/// Erreurs spécifiques au téléchargement / vérification d'un pack.
sealed class RemotePackException implements Exception {
  const RemotePackException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PackHashMismatchException extends RemotePackException {
  const PackHashMismatchException({
    required this.expected,
    required this.actual,
  }) : super('Hash mismatch: expected $expected, got $actual');

  final String expected;
  final String actual;
}

class PackDownloadException extends RemotePackException {
  const PackDownloadException(super.message);
}

class PackParseException extends RemotePackException {
  const PackParseException(super.message);
}

/// Récupère les manifests Firestore et télécharge les packs JSON gzippés
/// depuis Cloud Storage. Vérifie le hash SHA256 avant retour.
///
/// Ne touche jamais au cache local — c'est le rôle du repository composite
/// (orchestration) ou du `ManifestSyncService` (workflow de synchronisation).
class RemoteDevinettePackDatasource {
  RemoteDevinettePackDatasource({
    required FirebaseFirestore firestore,
    http.Client? httpClient,
  })  : _firestore = firestore,
        _http = httpClient ?? http.Client();

  final FirebaseFirestore _firestore;
  final http.Client _http;

  static const String _manifestCollection = 'content_packs';
  static const String _indexCollection = 'content_index';
  static const String _indexDocId = 'global';

  /// Liste des `packId` actifs déclarés dans `content_index/global`.
  /// Permet de découvrir packs officiels et communautaires en un seul read.
  Future<List<String>> listActivePackIds() async {
    final snap = await _firestore
        .collection(_indexCollection)
        .doc(_indexDocId)
        .get();
    final data = snap.data();
    if (data == null) return const <String>[];
    final raw = data['packs'] as List<dynamic>?;
    if (raw == null) return const <String>[];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  /// Récupère le manifest d'un pack donné.
  Future<ContentPackManifest?> fetchManifest(String packId) async {
    final snap =
        await _firestore.collection(_manifestCollection).doc(packId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return ContentPackManifest.fromFirestore(docId: packId, data: data);
  }

  /// Récupère plusieurs manifests en une seule passe (whereIn limit 30).
  Future<List<ContentPackManifest>> fetchManifests(
    List<String> packIds,
  ) async {
    if (packIds.isEmpty) return const <ContentPackManifest>[];
    final results = <ContentPackManifest>[];
    // Firestore `whereIn` limite à 30 valeurs ; on chunke.
    for (var i = 0; i < packIds.length; i += 30) {
      final chunk = packIds.sublist(
        i,
        i + 30 > packIds.length ? packIds.length : i + 30,
      );
      final snap = await _firestore
          .collection(_manifestCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        results.add(
          ContentPackManifest.fromFirestore(
            docId: doc.id,
            data: doc.data(),
          ),
        );
      }
    }
    return results;
  }

  /// Télécharge le pack, décompresse, vérifie le hash, parse les devinettes.
  ///
  /// Lève [PackDownloadException], [PackHashMismatchException] ou
  /// [PackParseException] selon l'étape qui échoue. Le cache local n'est pas
  /// modifié — c'est le rôle de l'appelant.
  Future<List<Devinette>> downloadAndParse(
    ContentPackManifest manifest,
  ) async {
    if (!manifest.enabled) {
      throw PackDownloadException(
        'Pack ${manifest.packId} désactivé via Remote Config / manifest.',
      );
    }

    final Uri uri;
    try {
      uri = Uri.parse(manifest.downloadUrl);
    } on FormatException catch (e) {
      throw PackDownloadException('URL invalide: ${e.message}');
    }

    final http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw PackDownloadException('Network error: ${e.message}');
    } on HttpException catch (e) {
      throw PackDownloadException('HTTP error: ${e.message}');
    }

    if (response.statusCode != 200) {
      throw PackDownloadException(
        'HTTP ${response.statusCode} pour ${manifest.packId}',
      );
    }

    final compressed = response.bodyBytes;
    final List<int> decompressed;
    try {
      decompressed = const GZipDecoder().decodeBytes(compressed);
    } on Exception catch (e) {
      throw PackParseException('Gzip decode failed: $e');
    }

    final actualHash = sha256.convert(decompressed).toString();
    if (actualHash != manifest.hashSha256) {
      throw PackHashMismatchException(
        expected: manifest.hashSha256,
        actual: actualHash,
      );
    }

    final Map<String, dynamic> packJson;
    try {
      packJson = jsonDecode(utf8.decode(decompressed))
          as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw PackParseException('JSON decode failed: ${e.message}');
    }

    final entries = (packJson['devinettes'] as List<dynamic>?) ??
        const <dynamic>[];
    final defaultSource = manifest.isCommunity
        ? DevinetteSource.community
        : DevinetteSource.remotePack;

    return entries
        .cast<Map<String, dynamic>>()
        .map((e) => Devinette.fromJson(e, source: defaultSource))
        .toList(growable: false);
  }

  void dispose() => _http.close();
}
