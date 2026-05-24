// Tests unitaires de `ManifestSyncService` v0.2 (séquentiel, idempotent,
// abort sur memory pressure, SyncReport correct). Voir `docs/ota_v2_design.md`.
//
// Strategy : fakes par `implements` plutôt que mockito codegen (cohérent
// avec le style des autres tests du projet).

import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/data/sync/manifest_sync_service.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  late _FakeRemote remote;
  late _FakeCache cache;
  late _FakePressure pressure;
  late ManifestSyncService service;

  setUp(() {
    remote = _FakeRemote();
    cache = _FakeCache();
    pressure = _FakePressure();
    service = ManifestSyncService(
      remote: remote,
      cache: cache,
      memoryPressure: pressure,
      logger: Logger(level: Level.off),
    );
  });

  test('no active packs → SyncReport vide', () async {
    remote.activePackIds = const [];
    final report = await service.refresh();
    expect(report.updated, 0);
    expect(report.skipped, 0);
    expect(report.errors, 0);
  });

  test('refresh est séquentiel (jamais deux downloads en parallèle)', () async {
    remote
      ..activePackIds = ['p1', 'p2', 'p3']
      ..manifests = [
        _manifest('p1', version: 1),
        _manifest('p2', version: 1),
        _manifest('p3', version: 1),
      ]
      ..downloadDelay = const Duration(milliseconds: 30);

    await service.refresh();

    // Aucune des fenêtres de download ne doit chevaucher la suivante.
    for (var i = 0; i + 1 < remote.downloadWindows.length; i++) {
      final (_, end) = remote.downloadWindows[i];
      final (nextStart, _) = remote.downloadWindows[i + 1];
      expect(
        nextStart.isAfter(end) || nextStart.isAtSameMomentAs(end),
        isTrue,
        reason: 'Download $i et ${i + 1} se chevauchent.',
      );
    }
  });

  test('refresh idempotent : pack à jour est skippé sans download', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 5, hash: 'h5')];
    cache.states['p1'] = _packState('p1', version: 5, hash: 'h5');

    final report = await service.refresh();

    expect(remote.downloadCalls, 0);
    expect(report.updated, 0);
    expect(report.skipped, 1);
    expect(report.errors, 0);
  });

  test('refresh émet onProgress après chaque pack', () async {
    remote
      ..activePackIds = ['p1', 'p2', 'p3']
      ..manifests = [
        _manifest('p1', version: 1),
        _manifest('p2', version: 1),
        _manifest('p3', version: 1),
      ];

    final emitted = <SyncProgress>[];
    await service.refresh(onProgress: emitted.add);

    expect(emitted.length, 3);
    expect(emitted[0].packIndex, 1);
    expect(emitted[0].packTotal, 3);
    expect(emitted[0].currentPackId, 'p1');
    expect(emitted[2].packIndex, 3);
    expect(emitted[2].overallFraction, 1.0);
  });

  test('refresh abort dès que memory pressure est détectée', () async {
    remote
      ..activePackIds = ['p1', 'p2', 'p3']
      ..manifests = [
        _manifest('p1', version: 1),
        _manifest('p2', version: 1),
        _manifest('p3', version: 1),
      ]
      // Pression mémoire après le 1er pack.
      ..onAfterDownload = () {
        if (remote.downloadCalls == 1) pressure.underPressure = true;
      };

    final report = await service.refresh();

    expect(report.updated, 1);
    expect(report.totalProcessed, 1);
    expect(remote.downloadCalls, 1);
    expect(report.abortedByMemoryPressure, isTrue);
  });

  test('refresh reset le signal de pression avant de boucler', () async {
    // Simule un signal de pression émis pendant le boot — il doit être
    // réinitialisé au tout début du refresh, pas empêcher le sync.
    pressure.underPressure = true;
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 1)];

    final report = await service.refresh();

    expect(report.updated, 1);
    expect(report.abortedByMemoryPressure, isFalse);
  });

  test('refresh swallow errors par pack et compte dans errors', () async {
    remote
      ..activePackIds = ['p1', 'p2', 'p3']
      ..manifests = [
        _manifest('p1', version: 1),
        _manifest('p2', version: 1),
        _manifest('p3', version: 1),
      ]
      ..failOnPack = 'p2';

    final report = await service.refresh();

    expect(report.updated, 2);
    expect(report.errors, 1);
    // p1 + p3 ont été téléchargés (p2 a thrown).
    expect(remote.downloadCalls, 3);
  });

  test('refresh mutex : double appel concurrent partage le Future', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 1)]
      ..downloadDelay = const Duration(milliseconds: 20);

    final f1 = service.refresh();
    final f2 = service.refresh();

    expect(identical(f1, f2), isTrue);
    final reports = await Future.wait([f1, f2]);
    expect(reports[0].updated, 1);
    expect(reports[1].updated, 1);
    expect(remote.downloadCalls, 1);
  });

  test('refresh : pack désactivé est skippé', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 1, enabled: false)];

    final report = await service.refresh();

    expect(remote.downloadCalls, 0);
    expect(report.updated, 0);
    expect(report.skipped, 1);
    expect(report.errors, 0);
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRemote implements RemoteDevinettePackDatasource {
  List<String> activePackIds = const [];
  List<ContentPackManifest> manifests = const [];
  Duration downloadDelay = Duration.zero;
  int downloadCalls = 0;
  String? failOnPack;
  void Function()? onAfterDownload;
  final List<(DateTime, DateTime)> downloadWindows = [];

  @override
  Future<List<String>> listActivePackIds() async => activePackIds;

  @override
  Future<ContentPackManifest?> fetchManifest(String packId) async {
    return manifests.where((m) => m.packId == packId).firstOrNull;
  }

  @override
  Future<List<ContentPackManifest>> fetchManifests(List<String> packIds) async {
    return manifests.where((m) => packIds.contains(m.packId)).toList();
  }

  @override
  Future<List<Devinette>> downloadAndParse(ContentPackManifest manifest) async {
    downloadCalls++;
    final start = DateTime.now();
    if (downloadDelay > Duration.zero) {
      await Future<void>.delayed(downloadDelay);
    }
    final end = DateTime.now();
    downloadWindows.add((start, end));
    onAfterDownload?.call();
    if (failOnPack == manifest.packId) {
      throw const PackDownloadException('forced failure');
    }
    return [
      Devinette(
        id: '${manifest.packId}-1',
        pack: manifest.pack,
        country: 'ci',
        answer: 'X',
        lettersPool: const ['X'],
        riddleByLang: const {'fr': 'r'},
        explanationByLang: const {'fr': 'e'},
        difficulty: 1,
        estimatedTimeS: 10,
        tags: const [],
        source: manifest.isCommunity
            ? DevinetteSource.community
            : DevinetteSource.remotePack,
      ),
    ];
  }

  @override
  void dispose() {}
}

class _FakeCache implements LocalDevinetteCacheDatasource {
  final Map<String, PackStateRow> states = {};
  final List<String> replacedPacks = [];

  @override
  Future<PackStateRow?> packState(String packId) async => states[packId];

  @override
  Future<void> markManifestSync(String packId) async {}

  @override
  Future<void> replacePackContents({
    required String pack,
    required DevinetteSource source,
    required List<Devinette> devinettes,
    required int packVersion,
  }) async {
    replacedPacks.add(pack);
  }

  @override
  Future<void> upsertPackState({
    required String packId,
    required String pack,
    required int packVersion,
    required String hashSha256,
    required int sizeBytes,
    required int count,
  }) async {
    states[packId] = PackStateRow(
      packId: packId,
      pack: pack,
      packVersion: packVersion,
      hashSha256: hashSha256,
      sizeBytes: sizeBytes,
      count: count,
      downloadedAt: DateTime.now(),
      lastSyncedManifestAt: DateTime.now(),
    );
  }

  @override
  Future<int> countByPack(String pack) async => 0;

  @override
  Future<void> deletePack({
    required String pack,
    required DevinetteSource source,
  }) async {}

  @override
  Future<List<Devinette>> loadByPack(String pack) async => const [];
}

class _FakePressure implements MemoryPressureSignal {
  bool underPressure = false;

  @override
  bool get isUnderPressure => underPressure;

  @override
  void reset() {
    underPressure = false;
  }

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

ContentPackManifest _manifest(
  String packId, {
  required int version,
  String hash = 'hX',
  bool enabled = true,
}) {
  return ContentPackManifest(
    packId: packId,
    pack: packId,
    currentVersion: version,
    formatVersion: 3,
    hashSha256: hash,
    sizeBytes: 1024,
    count: 1,
    storagePath: 'packs/v2/$packId/$packId-v$version.json.gz',
    downloadUrl: 'https://example.test/$packId-v$version.json.gz',
    minAppVersion: '0.1.0',
    langs: const ['fr'],
    defaultLang: 'fr',
    enabled: enabled,
    isCommunity: false,
  );
}

PackStateRow _packState(
  String packId, {
  required int version,
  required String hash,
}) {
  return PackStateRow(
    packId: packId,
    pack: packId,
    packVersion: version,
    hashSha256: hash,
    sizeBytes: 1024,
    count: 1,
    downloadedAt: DateTime.now(),
    lastSyncedManifestAt: DateTime.now(),
  );
}
