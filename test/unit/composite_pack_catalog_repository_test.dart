import 'package:defi_kilimandjaro/data/datasources/remote_catalog_datasource.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_pack_catalog_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests unit du `CompositePackCatalogRepository`.
///
/// Stratégie : on mock le `BundledPackCatalogRepository` via son `assetLoader`
/// pour contrôler ce que renvoie le bundle. Le `RemoteCatalogDatasource` est
/// remplacé par une fake impl qui retourne un snapshot fixe.
void main() {
  group('Pack.fromCatalogEntry', () {
    test('parse une entrée standard avec tous les champs', () {
      final pack = Pack.fromCatalogEntry({
        'id': 'culture_ci',
        'visible': true,
        'ordering': 10,
        'free_choice_eligible': true,
        'unlock_cost_cauris': 2000,
        'theme_color_hex': '#E07A19',
        'count': 350,
      });
      expect(pack.id, 'culture_ci');
      expect(pack.visible, true);
      expect(pack.ordering, 10);
      expect(pack.freeChoiceEligible, true);
      expect(pack.priceCauris, 2000);
      expect(pack.unlockCostCauris, 2000);
      expect(pack.themeColorHex, '#E07A19');
      expect(pack.questionCount, 350);
      expect(pack.source, PackSource.remote);
      // Les name_key/description_key sont générés depuis l'id si non fournis
      expect(pack.nameKey, 'pack.culture_ci.name');
      expect(pack.descriptionKey, 'pack.culture_ci.description');
    });

    test('respecte les valeurs par défaut quand des champs sont absents', () {
      final pack = Pack.fromCatalogEntry({'id': 'new_pack'});
      expect(pack.visible, true);
      expect(pack.ordering, 100);
      expect(pack.freeChoiceEligible, false);
      expect(pack.questionCount, 0);
      expect(pack.unlockCostCauris, null);
      expect(pack.themeColorHex, null);
    });

    test('parse correctement available_from/until', () {
      final pack = Pack.fromCatalogEntry({
        'id': 'limited',
        'available_from': '2026-06-01T00:00:00Z',
        'available_until': '2026-06-30T23:59:59Z',
      });
      expect(pack.availableFrom, DateTime.parse('2026-06-01T00:00:00Z'));
      expect(pack.availableUntil, DateTime.parse('2026-06-30T23:59:59Z'));
    });

    test('tolère les dates invalides (null silencieux)', () {
      final pack = Pack.fromCatalogEntry({
        'id': 'broken',
        'available_from': 'not-a-date',
      });
      expect(pack.availableFrom, null);
    });
  });

  group('Pack.mergeWithRemote', () {
    final bundlePack = Pack.fromIndexEntry('culture_ci', {
      'name_key': 'pack.culture_ci.name',
      'description_key': 'pack.culture_ci.description',
      'count': 70,
      'free_choice_eligible': true,
      'price_eur': 2.99,
      'price_cauris': 2000,
    });

    test('le remote override visible/ordering/freeChoiceEligible', () {
      final remote = Pack.fromCatalogEntry({
        'id': 'culture_ci',
        'visible': false,
        'ordering': 5,
        'free_choice_eligible': false,
      });
      final merged = bundlePack.mergeWithRemote(remote);
      expect(merged.visible, false);
      expect(merged.ordering, 5);
      expect(merged.freeChoiceEligible, false);
    });

    test('le bundle garde nameKey/descriptionKey/questionCount', () {
      final remote = Pack.fromCatalogEntry({
        'id': 'culture_ci',
        'count': 9999, // ignored
      });
      final merged = bundlePack.mergeWithRemote(remote);
      expect(merged.nameKey, 'pack.culture_ci.name');
      expect(merged.descriptionKey, 'pack.culture_ci.description');
      expect(merged.questionCount, 70); // bundle gagne sur count
    });

    test('source devient PackSource.merged', () {
      final remote = Pack.fromCatalogEntry({'id': 'culture_ci'});
      final merged = bundlePack.mergeWithRemote(remote);
      expect(merged.source, PackSource.merged);
    });

    test('themeColorHex/iconUrl/availabilities remote propagent', () {
      final remote = Pack.fromCatalogEntry({
        'id': 'culture_ci',
        'theme_color_hex': '#FF0000',
        'available_from': '2026-12-01T00:00:00Z',
      });
      final merged = bundlePack.mergeWithRemote(remote);
      expect(merged.themeColorHex, '#FF0000');
      expect(merged.availableFrom, DateTime.parse('2026-12-01T00:00:00Z'));
    });
  });

  group('Pack.isWithinAvailability', () {
    test('true par défaut quand aucune date', () {
      final pack = Pack.fromIndexEntry('x', {
        'name_key': 'k',
        'description_key': 'd',
      });
      expect(pack.isWithinAvailability, true);
    });

    test('false si on est avant availableFrom', () {
      final pack = Pack.fromCatalogEntry({
        'id': 'x',
        'available_from':
            DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      });
      expect(pack.isWithinAvailability, false);
    });

    test('false si on est après availableUntil', () {
      final pack = Pack.fromCatalogEntry({
        'id': 'x',
        'available_until':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      });
      expect(pack.isWithinAvailability, false);
    });

    test('true dans la fenêtre', () {
      final pack = Pack.fromCatalogEntry({
        'id': 'x',
        'available_from':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'available_until':
            DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      });
      expect(pack.isWithinAvailability, true);
    });
  });

  group('CompositePackCatalogRepository (sans remote)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<CompositePackCatalogRepository> buildComposite({
      String? bundleJson,
    }) async {
      final bundle = BundledPackCatalogRepository(
        assetLoader: (path) async => bundleJson ?? _kDefaultBundleJson,
      );
      final remote = _NoopRemoteDatasource();
      return CompositePackCatalogRepository(bundle: bundle, remote: remote);
    }

    test('loadAll retourne le bundle quand pas de remote', () async {
      final composite = await buildComposite();
      final packs = await composite.loadAll();
      expect(packs, hasLength(2));
      expect(packs.map((p) => p.id), containsAll(['culture_ci', 'crack_nouchi']));
    });

    test('byId trouve le pack bundle', () async {
      final composite = await buildComposite();
      final pack = await composite.byId('culture_ci');
      expect(pack?.id, 'culture_ci');
      expect(pack?.questionCount, 70);
    });

    test('byId retourne null si packId inconnu', () async {
      final composite = await buildComposite();
      final pack = await composite.byId('inexistant');
      expect(pack, null);
    });

    test('freeChoiceCandidates filtre sur free_choice_eligible', () async {
      final composite = await buildComposite();
      final candidates = await composite.freeChoiceCandidates();
      expect(candidates.map((p) => p.id),
          containsAll(['culture_ci', 'crack_nouchi']));
    });
  });

  group('CompositePackCatalogRepository (avec remote)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('remote override le bundle pour visible=false', () async {
      final bundle = BundledPackCatalogRepository(
        assetLoader: (_) async => _kDefaultBundleJson,
      );
      final remote = _FakeRemoteDatasource(RemoteCatalogSnapshot(
        schemaVersion: 4,
        catalogVersion: 1,
        fetchedAt: DateTime.now(),
        packs: [
          Pack.fromCatalogEntry({
            'id': 'culture_ci',
            'visible': false, // masqué via remote
            'ordering': 10,
          }),
          Pack.fromCatalogEntry({
            'id': 'crack_nouchi',
            'visible': true,
            'ordering': 20,
          }),
        ],
      ));
      final composite = CompositePackCatalogRepository(
        bundle: bundle,
        remote: remote,
      );
      await composite.refresh(); // force le fetch
      final packs = await composite.loadAll();
      // culture_ci masqué → seulement crack_nouchi visible
      expect(packs.map((p) => p.id), ['crack_nouchi']);
    });

    test('remote ajoute des nouveaux packs absents du bundle', () async {
      final bundle = BundledPackCatalogRepository(
        assetLoader: (_) async => _kDefaultBundleJson,
      );
      final remote = _FakeRemoteDatasource(RemoteCatalogSnapshot(
        schemaVersion: 4,
        catalogVersion: 1,
        fetchedAt: DateTime.now(),
        packs: [
          Pack.fromCatalogEntry({
            'id': 'culture_ci',
            'ordering': 10,
          }),
          Pack.fromCatalogEntry({
            'id': 'crack_nouchi',
            'ordering': 20,
          }),
          Pack.fromCatalogEntry({
            'id': 'football_ci',
            'ordering': 30,
            'visible': true,
          }),
        ],
      ));
      final composite = CompositePackCatalogRepository(
        bundle: bundle,
        remote: remote,
      );
      await composite.refresh();
      final packs = await composite.loadAll();
      expect(packs.map((p) => p.id),
          containsAll(['culture_ci', 'crack_nouchi', 'football_ci']));
      // football_ci a source=remote (pas dans bundle)
      final football = packs.firstWhere((p) => p.id == 'football_ci');
      expect(football.source, PackSource.remote);
    });

    test('tri par ordering croissant après merge', () async {
      final bundle = BundledPackCatalogRepository(
        assetLoader: (_) async => _kDefaultBundleJson,
      );
      final remote = _FakeRemoteDatasource(RemoteCatalogSnapshot(
        schemaVersion: 4,
        catalogVersion: 1,
        fetchedAt: DateTime.now(),
        packs: [
          Pack.fromCatalogEntry({'id': 'crack_nouchi', 'ordering': 5}),
          Pack.fromCatalogEntry({'id': 'culture_ci', 'ordering': 20}),
        ],
      ));
      final composite = CompositePackCatalogRepository(
        bundle: bundle,
        remote: remote,
      );
      await composite.refresh();
      final packs = await composite.loadAll();
      expect(packs.first.id, 'crack_nouchi'); // ordering=5
      expect(packs.last.id, 'culture_ci'); // ordering=20
    });

    test('availability gating exclut les packs hors fenêtre', () async {
      final bundle = BundledPackCatalogRepository(
        assetLoader: (_) async => _kDefaultBundleJson,
      );
      final remote = _FakeRemoteDatasource(RemoteCatalogSnapshot(
        schemaVersion: 4,
        catalogVersion: 1,
        fetchedAt: DateTime.now(),
        packs: [
          Pack.fromCatalogEntry({'id': 'culture_ci'}),
          // Disponible dans le futur — exclu
          Pack.fromCatalogEntry({
            'id': 'crack_nouchi',
            'available_from':
                DateTime.now().add(const Duration(days: 7)).toIso8601String(),
          }),
        ],
      ));
      final composite = CompositePackCatalogRepository(
        bundle: bundle,
        remote: remote,
      );
      await composite.refresh();
      final packs = await composite.loadAll();
      expect(packs.map((p) => p.id), ['culture_ci']);
    });
  });
}

// ===========================================================================
// JSON bundle fixture
// ===========================================================================

const String _kDefaultBundleJson = '''
{
  "format_version": 3,
  "packs": {
    "culture_ci": {
      "file": "culture_ci.json",
      "count": 70,
      "name_key": "pack.culture_ci.name",
      "description_key": "pack.culture_ci.description",
      "free_choice_eligible": true,
      "price_eur": 2.99,
      "price_cauris": 2000
    },
    "crack_nouchi": {
      "file": "crack_nouchi.json",
      "count": 38,
      "name_key": "pack.crack_nouchi.name",
      "description_key": "pack.crack_nouchi.description",
      "free_choice_eligible": true,
      "price_eur": 2.99,
      "price_cauris": 2000
    }
  }
}
''';

// ===========================================================================
// Test doubles
// ===========================================================================

/// Datasource qui ne fait rien (pas de remote configuré).
class _NoopRemoteDatasource implements RemoteCatalogDatasource {
  @override
  Future<RemoteCatalogSnapshot?> fetch() async => null;

  @override
  Stream<RemoteCatalogSnapshot?> watch() => const Stream.empty();

  @override
  Future<RemoteCatalogSnapshot?> loadCache() async => null;

  @override
  Future<void> clearCache() async {}
}

/// Datasource qui retourne toujours un snapshot fixe (pour tests).
class _FakeRemoteDatasource implements RemoteCatalogDatasource {
  _FakeRemoteDatasource(this._snapshot);
  final RemoteCatalogSnapshot _snapshot;

  @override
  Future<RemoteCatalogSnapshot?> fetch() async => _snapshot;

  @override
  Stream<RemoteCatalogSnapshot?> watch() => Stream.value(_snapshot);

  @override
  Future<RemoteCatalogSnapshot?> loadCache() async => null;

  @override
  Future<void> clearCache() async {}
}
