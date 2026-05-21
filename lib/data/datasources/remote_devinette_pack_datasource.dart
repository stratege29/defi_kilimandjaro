import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

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
/// v0.2 — voir `docs/ota_v2_design.md`. Le download passe désormais par
/// `http.Client.send()` en mode streamé, avec décompression gzip et
/// digest SHA256 incrémentaux. Les bytes gzippés ne sont jamais
/// totalement en RAM (seul le buffer décompressé l'est, pendant le temps
/// du `jsonDecode`). Trade-off honnête : on garde l'arbre JSON Dart en
/// RAM pendant le parse — gain principal vient du fait de ne pas
/// matérialiser deux fois la même donnée.
class RemoteDevinettePackDatasource {
  RemoteDevinettePackDatasource({
    required FirebaseFirestore firestore,
    http.Client? httpClient,
  })  : _firestore = firestore,
        _http = httpClient ?? _defaultClient();

  /// Crée un client HTTP avec `autoUncompress = false` : Firebase Storage sert
  /// les packs avec `Content-Encoding: gzip`, et `dart:io HttpClient` les
  /// auto-décompresse par défaut. On veut recevoir les bytes gzippés bruts
  /// pour que notre décodeur streamé + sha256 incrémental fonctionne.
  static http.Client _defaultClient() {
    final inner = HttpClient()..autoUncompress = false;
    return IOClient(inner);
  }

  final FirebaseFirestore _firestore;
  final http.Client _http;

  static const String _manifestCollection = 'content_packs';
  static const String _indexCollection = 'content_index';
  static const String _indexDocId = 'global';
  static const Duration _httpTimeout = Duration(seconds: 30);

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

  /// Télécharge le pack en streaming, décompresse et hash au fil de l'eau,
  /// vérifie l'intégrité puis parse les devinettes.
  ///
  /// Lève [PackDownloadException], [PackHashMismatchException] ou
  /// [PackParseException] selon l'étape qui échoue. Le cache local n'est
  /// pas modifié — c'est le rôle de l'appelant.
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

    final http.StreamedResponse response;
    try {
      response = await _http
          .send(http.Request('GET', uri))
          .timeout(_httpTimeout);
    } on SocketException catch (e) {
      throw PackDownloadException('Network error: ${e.message}');
    } on HttpException catch (e) {
      throw PackDownloadException('HTTP error: ${e.message}');
    } on TimeoutException catch (e) {
      throw PackDownloadException('Timeout: ${e.message}');
    }

    if (response.statusCode != 200) {
      // Drain le stream pour libérer la socket.
      await response.stream.drain<void>();
      throw PackDownloadException(
        'HTTP ${response.statusCode} pour ${manifest.packId}',
      );
    }

    final decompressed = BytesBuilder(copy: false);
    final hashSink = _DigestSink();
    final hashConv = sha256.startChunkedConversion(hashSink);

    final gzipSink = gzip.decoder.startChunkedConversion(
      _ChunkCallbackSink((chunk) {
        decompressed.add(chunk);
        hashConv.add(chunk);
      }),
    );

    try {
      await for (final chunk in response.stream) {
        gzipSink.add(chunk);
      }
      gzipSink.close();
    } on FormatException catch (e) {
      hashConv.close();
      throw PackParseException('Gzip decode failed: ${e.message}');
    } on SocketException catch (e) {
      hashConv.close();
      throw PackDownloadException('Stream error: ${e.message}');
    }

    hashConv.close();
    final digest = hashSink.value;
    if (digest == null) {
      throw const PackParseException('Empty pack stream');
    }
    final actualHash = digest.toString();
    if (actualHash != manifest.hashSha256) {
      throw PackHashMismatchException(
        expected: manifest.hashSha256,
        actual: actualHash,
      );
    }

    // À ce stade les bytes gzippés ont été libérés au fil du stream.
    // On matérialise les bytes décompressés en `Uint8List` une seule fois.
    final bytes = decompressed.takeBytes();

    final Map<String, dynamic> packJson;
    try {
      packJson = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw PackParseException('JSON decode failed: ${e.message}');
    }

    final entries = (packJson['devinettes'] as List<dynamic>?) ??
        const <dynamic>[];
    final defaultSource = manifest.isCommunity
        ? DevinetteSource.community
        : DevinetteSource.remotePack;

    final result = <Devinette>[];
    // Itère + null la slot pour aider le GC à récupérer les `Map` source
    // au fil de la construction des entités domain.
    final mutableEntries = List<dynamic>.from(entries);
    for (var i = 0; i < mutableEntries.length; i++) {
      final raw = mutableEntries[i] as Map<String, dynamic>;
      result.add(Devinette.fromJson(raw, source: defaultSource));
      mutableEntries[i] = null;
    }
    return result;
  }

  void dispose() => _http.close();
}

/// Sink minimaliste qui forwarde chaque chunk décompressé à un callback,
/// utilisé par `gzip.decoder.startChunkedConversion`. La version
/// `ByteConversionSink.withCallback` accumule tout avant d'appeler le
/// callback — pas ce qu'on veut ici.
class _ChunkCallbackSink extends ByteConversionSink {
  _ChunkCallbackSink(this._onChunk);

  final void Function(List<int> chunk) _onChunk;

  @override
  void add(List<int> chunk) {
    if (chunk.isNotEmpty) _onChunk(chunk);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    if (end > start) _onChunk(chunk.sublist(start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}

/// Sink à un seul slot pour récupérer le `Digest` final de
/// `sha256.startChunkedConversion`. Remplace `AccumulatorSink<Digest>` du
/// package `convert` (non importé dans pubspec).
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
