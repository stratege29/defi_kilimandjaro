import 'package:defi_kilimandjaro/data/datasources/bundled_devinette_datasource.dart';
import 'package:defi_kilimandjaro/data/datasources/local_devinette_cache_datasource.dart';
import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBundled extends BundledDevinetteDatasource {
  _FakeBundled(this.entries);
  final List<Devinette> entries;
  @override
  Future<List<Devinette>> loadPack(String packId) async => entries;
}

Devinette _make({
  required String id,
  String pack = 'culture_ci',
  DevinetteSource source = DevinetteSource.bundled,
  String riddle = 'r',
}) {
  return Devinette(
    id: id,
    pack: pack,
    country: 'ci',
    answer: id.toUpperCase(),
    lettersPool: id.toUpperCase().split(''),
    riddleByLang: <String, String>{'fr': riddle},
    explanationByLang: const {'fr': 'expl'},
    difficulty: 1,
    estimatedTimeS: 10,
    tags: const [],
    source: source,
  );
}

void main() {
  late DevinetteDatabase db;
  late LocalDevinetteCacheDatasource cache;

  setUp(() {
    db = DevinetteDatabase.forTesting(NativeDatabase.memory());
    cache = LocalDevinetteCacheDatasource(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('loadPack retourne le starter quand le cache est vide', () async {
    final repo = CompositeDevinetteRepository(
      bundled: _FakeBundled([_make(id: 'a'), _make(id: 'b')]),
      cache: cache,
    );
    final list = await repo.loadPack('culture_ci');
    expect(list.map((d) => d.id), ['a', 'b']);
  });

  test('cache distant supplante starter sur même id', () async {
    await cache.replacePackContents(
      pack: 'culture_ci',
      source: DevinetteSource.remotePack,
      devinettes: [
        _make(id: 'a', source: DevinetteSource.remotePack, riddle: 'remote-a'),
        _make(id: 'c', source: DevinetteSource.remotePack, riddle: 'remote-c'),
      ],
      packVersion: 1,
    );

    final repo = CompositeDevinetteRepository(
      bundled: _FakeBundled([
        _make(id: 'a', riddle: 'bundled-a'),
        _make(id: 'b', riddle: 'bundled-b'),
      ]),
      cache: cache,
    );

    final list = await repo.loadPack('culture_ci');
    final byId = {for (final d in list) d.id: d};
    expect(byId.keys.toSet(), {'a', 'b', 'c'});
    expect(byId['a']!.riddleByLang['fr'], 'remote-a',
        reason: 'remote doit gagner sur bundled');
    expect(byId['b']!.riddleByLang['fr'], 'bundled-b');
    expect(byId['c']!.riddleByLang['fr'], 'remote-c');
  });

  test('upsertPackState + packState (drift roundtrip)', () async {
    await cache.upsertPackState(
      packId: 'culture_ci',
      pack: 'culture_ci',
      packVersion: 7,
      hashSha256: 'abc',
      sizeBytes: 1024,
      count: 42,
    );
    final state = await cache.packState('culture_ci');
    expect(state, isNotNull);
    expect(state!.packVersion, 7);
    expect(state.hashSha256, 'abc');
    expect(state.count, 42);
  });

  test('replacePackContents est atomique (delete-by-source-puis-insert)',
      () async {
    await cache.replacePackContents(
      pack: 'culture_ci',
      source: DevinetteSource.remotePack,
      devinettes: [_make(id: 'old1'), _make(id: 'old2')],
      packVersion: 1,
    );
    expect(await cache.countByPack('culture_ci'), 2);

    await cache.replacePackContents(
      pack: 'culture_ci',
      source: DevinetteSource.remotePack,
      devinettes: [_make(id: 'new1')],
      packVersion: 2,
    );
    final list = await cache.loadByPack('culture_ci');
    expect(list.map((d) => d.id), ['new1']);
  });

  // Dummy assert pour s'assurer que `drift` import est utilisé même si
  // certaines branches conditionnelles le retirent.
  test('drift import sanity', () {
    expect(const drift.Variable<int>(1).value, 1);
  });
}
