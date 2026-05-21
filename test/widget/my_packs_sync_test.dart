// Tests du `ManifestSyncNotifier` qui relie `ManifestSyncService` à l'UI
// (`MyPacksView`). Couvre les transitions d'état Idle → Syncing → Success/Error
// et l'idempotence du double-tap.
//
// Le widget tree complet de MyPacksView dépend de >4 providers métier
// (catalog, owned packs, mix, progress) qui demandent un setup Drift +
// SharedPreferences. Ici on focus sur la logique du notifier — la pose
// du SnackBar / banner est triviale Flutter Material et vérifiée par
// inspection manuelle (voir docs/ota_v2_design.md Vérification).

import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/remote_devinette_pack_datasource.dart';
import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
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
  late ManifestSyncNotifier notifier;

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
    notifier = ManifestSyncNotifier(service);
  });

  tearDown(() => notifier.dispose());

  test('état initial = SyncStateIdle', () {
    expect(notifier.state, isA<SyncStateIdle>());
  });

  test('startRefresh transitionne Idle → Syncing → Success', () async {
    remote
      ..activePackIds = ['p1', 'p2']
      ..manifests = [
        _manifest('p1', version: 1),
        _manifest('p2', version: 1),
      ];

    final emitted = <SyncState>[];
    notifier.addListener(emitted.add, fireImmediately: true);

    await notifier.startRefresh();

    // initial Idle + Syncing initial + 2 progress updates + Success.
    expect(emitted.first, isA<SyncStateIdle>());
    expect(emitted.whereType<SyncStateSyncing>(), isNotEmpty);
    expect(emitted.last, isA<SyncStateSuccess>());
    final success = emitted.last as SyncStateSuccess;
    expect(success.report.updated, 2);
  });

  test('startRefresh pendant Syncing est ignoré (double-tap safe)', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 1)]
      ..downloadDelay = const Duration(milliseconds: 50);

    final first = notifier.startRefresh();
    // Démarrer un 2e immédiatement pendant que le 1er est en cours.
    final second = notifier.startRefresh();
    await Future.wait([first, second]);

    // Un seul download effectivement réalisé.
    expect(remote.downloadCalls, 1);
    expect(notifier.state, isA<SyncStateSuccess>());
  });

  test('erreur du service → SyncStateError', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 1)]
      ..throwOnList = true;

    await notifier.startRefresh();

    expect(notifier.state, isA<SyncStateError>());
  });

  test('progress de syncing reflète fraction et currentPackId', () async {
    remote
      ..activePackIds = ['p1', 'p2', 'p3']
      ..manifests = [
        _manifest('p1', version: 1),
        _manifest('p2', version: 1),
        _manifest('p3', version: 1),
      ];

    final syncingStates = <SyncStateSyncing>[];
    notifier.addListener((s) {
      if (s is SyncStateSyncing) syncingStates.add(s);
    });

    await notifier.startRefresh();

    expect(syncingStates.length, greaterThanOrEqualTo(3));
    expect(syncingStates.first.progress, 0);
    expect(syncingStates.last.progress, closeTo(1.0, 0.01));
    expect(syncingStates.last.currentPackId, 'p3');
  });

  test('SyncReport.hasChanges true si au moins un update', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 1)];

    await notifier.startRefresh();

    final state = notifier.state as SyncStateSuccess;
    expect(state.report.hasChanges, isTrue);
  });

  test('SyncReport.hasChanges false si tout skip (idempotence)', () async {
    remote
      ..activePackIds = ['p1']
      ..manifests = [_manifest('p1', version: 5, hash: 'h5')];
    cache.states['p1'] = _packState('p1', version: 5, hash: 'h5');

    await notifier.startRefresh();

    final state = notifier.state as SyncStateSuccess;
    expect(state.report.hasChanges, isFalse);
    expect(state.report.skipped, 1);
  });
}

// ---------------------------------------------------------------------------
// Fakes (dupliqués depuis manifest_sync_service_test.dart pour rester
// auto-contenus — les patterns sont triviaux)
// ---------------------------------------------------------------------------

class _FakeRemote implements RemoteDevinettePackDatasource {
  List<String> activePackIds = const [];
  List<ContentPackManifest> manifests = const [];
  Duration downloadDelay = Duration.zero;
  int downloadCalls = 0;
  bool throwOnList = false;

  @override
  Future<List<String>> listActivePackIds() async {
    if (throwOnList) throw Exception('forced error');
    return activePackIds;
  }

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
    if (downloadDelay > Duration.zero) {
      await Future<void>.delayed(downloadDelay);
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
        source: DevinetteSource.remotePack,
      ),
    ];
  }

  @override
  void dispose() {}
}

class _FakeCache implements LocalDevinetteCacheDatasource {
  final Map<String, PackStateRow> states = {};

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
  }) async {}

  @override
  Future<void> upsertPackState({
    required String packId,
    required String pack,
    required int packVersion,
    required String hashSha256,
    required int sizeBytes,
    required int count,
  }) async {
    states[packId] = _packState(
      packId,
      version: packVersion,
      hash: hashSha256,
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
  @override
  bool get isUnderPressure => false;

  @override
  void reset() {}

  @override
  void dispose() {}
}

ContentPackManifest _manifest(
  String packId, {
  required int version,
  String hash = 'hX',
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
    enabled: true,
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
