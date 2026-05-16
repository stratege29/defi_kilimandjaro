import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

const String _indexJson = '''
{
  "format_version": 3,
  "packs": {
    "culture_ci": {
      "file": "culture_ci.json",
      "count": 30,
      "name_key": "pack.culture_ci.name",
      "description_key": "pack.culture_ci.description",
      "free_choice_eligible": true,
      "price_eur": 2.99,
      "price_cauris": 2000
    },
    "secret_pack": {
      "file": "secret_pack.json",
      "count": 12,
      "name_key": "pack.secret_pack.name",
      "description_key": "pack.secret_pack.description",
      "free_choice_eligible": false,
      "price_eur": 4.99,
      "price_cauris": 3000
    }
  },
  "total": 42
}
''';

void main() {
  group('BundledPackCatalogRepository', () {
    test('loadAll renvoie la liste complète des packs', () async {
      final repo = BundledPackCatalogRepository(
        assetLoader: (_) async => _indexJson,
      );
      final packs = await repo.loadAll();
      expect(packs.map((p) => p.id), containsAll(['culture_ci', 'secret_pack']));
      expect(packs.length, 2);
    });

    test('cache mémoire — un seul appel au loader', () async {
      var calls = 0;
      final repo = BundledPackCatalogRepository(
        assetLoader: (_) async {
          calls++;
          return _indexJson;
        },
      );
      await repo.loadAll();
      await repo.loadAll();
      await repo.byId('culture_ci');
      expect(calls, 1);
    });

    test('byId retourne le pack ou null', () async {
      final repo = BundledPackCatalogRepository(
        assetLoader: (_) async => _indexJson,
      );
      expect((await repo.byId('culture_ci'))?.id, 'culture_ci');
      expect(await repo.byId('inexistant'), isNull);
    });

    test('freeChoiceCandidates filtre sur free_choice_eligible', () async {
      final repo = BundledPackCatalogRepository(
        assetLoader: (_) async => _indexJson,
      );
      final candidates = await repo.freeChoiceCandidates();
      expect(candidates.map((p) => p.id), ['culture_ci']);
    });

    test('payload malformé → liste vide', () async {
      final repo = BundledPackCatalogRepository(
        assetLoader: (_) async => '{"format_version": 3}',
      );
      expect(await repo.loadAll(), isEmpty);
    });
  });
}
