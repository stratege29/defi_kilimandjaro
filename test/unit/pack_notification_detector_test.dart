import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_notification_repository.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/services/pack_notification_detector.dart';
import 'package:flutter_test/flutter_test.dart';

Pack _pack(String id) => Pack(
      id: id,
      nameKey: 'pack.$id.name',
      descriptionKey: 'pack.$id.description',
      questionCount: 10,
      freeChoiceEligible: false,
      priceEur: 0,
      priceCauris: 0,
    );

ContentPackManifest _manifest(
  String id, {
  int version = 1,
  String hash = 'h1',
  bool enabled = true,
}) =>
    ContentPackManifest(
      packId: id,
      pack: id,
      currentVersion: version,
      formatVersion: 3,
      hashSha256: hash,
      sizeBytes: 100,
      count: 10,
      storagePath: 'p',
      downloadUrl: 'u',
      minAppVersion: '0.0.0',
      langs: const ['fr'],
      defaultLang: 'fr',
      enabled: enabled,
      isCommunity: false,
    );

PackStateRow _local(
  String id, {
  int version = 1,
  String hash = 'h1',
}) =>
    PackStateRow(
      packId: id,
      pack: id,
      packVersion: version,
      hashSha256: hash,
      sizeBytes: 100,
      count: 10,
      downloadedAt: DateTime(2026),
    );

void main() {
  group('PackNotificationDetector.newPacks', () {
    final catalog = [_pack('a'), _pack('b'), _pack('c')];

    test('returns packs neither owned nor already seen', () {
      final result = PackNotificationDetector.newPacks(
        catalog: catalog,
        ownedIds: {'a'},
        seenIds: {'b'},
      );
      expect(result.map((p) => p.id), ['c']);
    });

    test('preserves catalog order', () {
      final result = PackNotificationDetector.newPacks(
        catalog: catalog,
        ownedIds: const {},
        seenIds: const {},
      );
      expect(result.map((p) => p.id), ['a', 'b', 'c']);
    });

    test('owned packs are never announced even if unseen', () {
      final result = PackNotificationDetector.newPacks(
        catalog: catalog,
        ownedIds: {'a', 'b', 'c'},
        seenIds: const {},
      );
      expect(result, isEmpty);
    });
  });

  group('PackNotificationRepository.needsUpdate', () {
    test('true when never downloaded locally', () {
      expect(
        PackNotificationRepository.needsUpdate(_manifest('a'), null),
        isTrue,
      );
    });

    test('false when up to date (same version and hash)', () {
      expect(
        PackNotificationRepository.needsUpdate(
          _manifest('a', version: 3, hash: 'x'),
          _local('a', version: 3, hash: 'x'),
        ),
        isFalse,
      );
    });

    test('true when remote version is newer', () {
      expect(
        PackNotificationRepository.needsUpdate(
          _manifest('a', version: 4, hash: 'x'),
          _local('a', version: 3, hash: 'x'),
        ),
        isTrue,
      );
    });

    test('true when hash differs at same version (content republished)', () {
      expect(
        PackNotificationRepository.needsUpdate(
          _manifest('a', version: 3, hash: 'new'),
          _local('a', version: 3, hash: 'old'),
        ),
        isTrue,
      );
    });

    test('false when manifest disabled, even if local is missing', () {
      expect(
        PackNotificationRepository.needsUpdate(
          _manifest('a', enabled: false),
          null,
        ),
        isFalse,
      );
    });
  });
}
