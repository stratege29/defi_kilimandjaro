// Tests unitaires de `RemoteDevinettePackDatasource.downloadAndParse` v0.2.
// Le download streamé + sha256 incrémental sont vérifiés via un MockClient
// `package:http/testing.dart` qui renvoie une StreamedResponse contrôlée.
//
// Les méthodes Firestore (`listActivePackIds`, `fetchManifest`, etc.) ne
// sont pas testées ici — elles requièrent un émulateur Firebase.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('downloadAndParse', () {
    test('roundtrip : gzip valide + hash OK → devinettes parsées', () async {
      final packJson = {
        'format_version': 2,
        'pack_id': 'p1',
        'pack_version': 1,
        'count': 2,
        'devinettes': [
          _devinetteMap('p1-a'),
          _devinetteMap('p1-b'),
        ],
      };
      final (bytes, hash) = _encodePack(packJson);
      final ds = _datasource(
        MockClient.streaming((req, body) async => _streamedOk(bytes)),
      );
      final manifest = _manifest('p1', hash: hash);

      final result = await ds.downloadAndParse(manifest);

      expect(result.length, 2);
      expect(result.map((d) => d.id), ['p1-a', 'p1-b']);
    });

    test('hash mismatch → PackHashMismatchException', () async {
      final (bytes, _) = _encodePack({
        'format_version': 2,
        'devinettes': [_devinetteMap('x')],
      });
      final ds = _datasource(
        MockClient.streaming((req, body) async => _streamedOk(bytes)),
      );
      final manifest = _manifest('p1', hash: 'wrong-hash');

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(isA<PackHashMismatchException>()),
      );
    });

    test('HTTP 404 → PackDownloadException', () async {
      final ds = _datasource(
        MockClient.streaming(
          (req, body) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            404,
          ),
        ),
      );
      final manifest = _manifest('p1', hash: 'h');

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(isA<PackDownloadException>()),
      );
    });

    test('manifest désactivé → PackDownloadException sans HTTP', () async {
      var called = 0;
      final ds = _datasource(
        MockClient.streaming((req, body) async {
          called++;
          return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
        }),
      );
      final manifest = _manifest('p1', hash: 'h', enabled: false);

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(isA<PackDownloadException>()),
      );
      expect(called, 0);
    });

    test('gzip invalide → PackParseException', () async {
      final ds = _datasource(
        MockClient.streaming(
          (req, body) async => _streamedOk(
            utf8.encode('not actually gzipped'),
          ),
        ),
      );
      final manifest = _manifest('p1', hash: 'h');

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(isA<PackParseException>()),
      );
    });

    test('JSON invalide → PackParseException', () async {
      final invalidPayload = utf8.encode('this is not json {[');
      final compressed = gzip.encode(invalidPayload);
      final hash = sha256.convert(invalidPayload).toString();
      final ds = _datasource(
        MockClient.streaming((req, body) async => _streamedOk(compressed)),
      );
      final manifest = _manifest('p1', hash: hash);

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(isA<PackParseException>()),
      );
    });

    test('large pack streamé en plusieurs chunks ⇒ hash final correct',
        () async {
      // Construit un pack avec 500 devinettes pour forcer plusieurs chunks
      // gzip et valider le digest incrémental.
      final entries = [
        for (var i = 0; i < 500; i++) _devinetteMap('p1-$i'),
      ];
      final (bytes, hash) = _encodePack({
        'format_version': 2,
        'devinettes': entries,
      });
      final ds = _datasource(
        MockClient.streaming(
          (req, body) async => _streamedOk(bytes, chunkSize: 256),
        ),
      );
      final manifest = _manifest('p1', hash: hash);

      final result = await ds.downloadAndParse(manifest);
      expect(result.length, 500);
    });

    test('body qui se fige après le 1er chunk → PackDownloadException (idle)',
        () async {
      final (bytes, hash) = _encodePack({
        'format_version': 2,
        'devinettes': [_devinetteMap('x')],
      });
      // Émet un seul chunk puis ne se termine jamais : simule une connexion
      // qui se fige en cours de body.
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add(bytes.sublist(0, 4));
      final ds = _datasource(
        MockClient.streaming(
          (req, body) async => http.StreamedResponse(controller.stream, 200),
        ),
        bodyIdleTimeout: const Duration(milliseconds: 50),
      );
      final manifest = _manifest('p1', hash: hash);

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.message,
            'message',
            contains('Timeout body'),
          ),
        ),
      );
    });

    test('flux décompressé au-delà du cap → PackDownloadException', () async {
      final entries = [
        for (var i = 0; i < 300; i++) _devinetteMap('p1-$i'),
      ];
      final (bytes, hash) = _encodePack({
        'format_version': 2,
        'devinettes': entries,
      });
      // size_bytes déclaré à 0 (manifest incomplet) : seul le comptage réel
      // du flux protège.
      final ds = _datasource(
        MockClient.streaming(
          (req, body) async => _streamedOk(bytes, chunkSize: 512),
        ),
        maxDecompressedBytes: 4 * 1024,
      );
      final manifest = _manifest('p1', hash: hash, sizeBytes: 0);

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.message,
            'message',
            contains('cap mémoire'),
          ),
        ),
      );
    });

    test('flux gzip reçu au-delà du cap → PackDownloadException', () async {
      final (bytes, hash) = _encodePack({
        'format_version': 2,
        'devinettes': [
          for (var i = 0; i < 300; i++) _devinetteMap('p1-$i'),
        ],
      });
      final ds = _datasource(
        MockClient.streaming(
          (req, body) async => _streamedOk(bytes, chunkSize: 256),
        ),
        maxGzipBytes: 1024,
      );
      final manifest = _manifest('p1', hash: hash, sizeBytes: 0);

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.message,
            'message',
            contains('cap gzip'),
          ),
        ),
      );
    });

    test('size_bytes > cap gzip → PackDownloadException sans HTTP', () async {
      var called = 0;
      final ds = _datasource(
        MockClient.streaming((req, body) async {
          called++;
          return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
        }),
      );
      final manifest = _manifest(
        'p1',
        hash: 'h',
        sizeBytes: kMaxPackGzipBytes + 1,
      );

      await expectLater(
        ds.downloadAndParse(manifest),
        throwsA(isA<PackDownloadException>()),
      );
      expect(called, 0);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

RemoteDevinettePackDatasource _datasource(
  http.Client client, {
  Duration bodyIdleTimeout = const Duration(seconds: 30),
  int maxGzipBytes = kMaxPackGzipBytes,
  int maxDecompressedBytes = kMaxPackDecompressedBytes,
}) {
  return RemoteDevinettePackDatasource(
    firestore: _NullFirestore(),
    httpClient: client,
    bodyIdleTimeout: bodyIdleTimeout,
    maxGzipBytes: maxGzipBytes,
    maxDecompressedBytes: maxDecompressedBytes,
  );
}

http.StreamedResponse _streamedOk(List<int> bytes, {int? chunkSize}) {
  final stream = chunkSize == null
      ? Stream<List<int>>.value(bytes)
      : _chunked(bytes, chunkSize);
  return http.StreamedResponse(
    stream,
    200,
    contentLength: bytes.length,
    headers: const {'content-type': 'application/json'},
  );
}

Stream<List<int>> _chunked(List<int> bytes, int chunkSize) async* {
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = (i + chunkSize).clamp(0, bytes.length);
    yield bytes.sublist(i, end);
  }
}

(List<int>, String) _encodePack(Map<String, dynamic> pack) {
  final raw = utf8.encode(jsonEncode(pack));
  final hash = sha256.convert(raw).toString();
  final compressed = gzip.encode(raw);
  return (compressed, hash);
}

Map<String, dynamic> _devinetteMap(String id) {
  return {
    'id': id,
    'pack': 'p1',
    'world': 'p1',
    'country': 'ci',
    'answer': id.toUpperCase(),
    'answer_normalized': id.toUpperCase(),
    'letters_pool': id.toUpperCase().split(''),
    'riddle': {'fr': 'riddle $id'},
    'explanation': {'fr': 'explanation'},
    'difficulty': 1,
    'estimated_time_s': 10,
    'tags': const <String>[],
  };
}

ContentPackManifest _manifest(
  String packId, {
  required String hash,
  bool enabled = true,
  int sizeBytes = 1024,
}) {
  return ContentPackManifest(
    packId: packId,
    pack: packId,
    currentVersion: 1,
    formatVersion: 3,
    hashSha256: hash,
    sizeBytes: sizeBytes,
    count: 1,
    storagePath: 'packs/v2/$packId/$packId-v1.json.gz',
    downloadUrl: 'https://example.test/$packId-v1.json.gz',
    minAppVersion: '0.1.0',
    langs: const ['fr'],
    defaultLang: 'fr',
    enabled: enabled,
    isCommunity: false,
  );
}

/// `RemoteDevinettePackDatasource` accepte un Firestore via constructeur
/// même si `downloadAndParse` ne l'utilise jamais. Ce stub évite l'init
/// Firebase complète.
class _NullFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'FirebaseFirestore non disponible en test unitaire — '
      '${invocation.memberName} appelé.',
    );
  }
}
