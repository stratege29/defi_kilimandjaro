import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pack.fromIndexEntry', () {
    test('parse une entrée complète', () {
      final pack = Pack.fromIndexEntry('culture_ci', const <String, dynamic>{
        'file': 'culture_ci.json',
        'count': 30,
        'name_key': 'pack.culture_ci.name',
        'description_key': 'pack.culture_ci.description',
        'free_choice_eligible': true,
        'price_eur': 2.99,
        'price_cauris': 2000,
      });
      expect(pack.id, 'culture_ci');
      expect(pack.questionCount, 30);
      expect(pack.freeChoiceEligible, isTrue);
      expect(pack.priceEur, 2.99);
      expect(pack.priceCauris, 2000);
      expect(pack.nameKey, 'pack.culture_ci.name');
    });

    test('tolère les champs numériques manquants (default = 0)', () {
      final pack = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'pack.x.name',
        'description_key': 'pack.x.description',
      });
      expect(pack.questionCount, 0);
      expect(pack.priceEur, 0.0);
      expect(pack.priceCauris, 0);
      expect(pack.freeChoiceEligible, isFalse);
    });

    test('accepte price_eur en int comme en double', () {
      final pack = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'a',
        'description_key': 'b',
        'price_eur': 3,
        'count': 10,
      });
      expect(pack.priceEur, 3.0);
    });

    test('parse theme_id et theme_overrides depuis le bundle', () {
      final pack = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'a',
        'description_key': 'b',
        'theme_id': 'abidjan_neon',
        'theme_overrides': <String, dynamic>{'accent': '#FF0000'},
      });
      expect(pack.themeId, 'abidjan_neon');
      expect(pack.themeOverrides, <String, String>{'accent': '#FF0000'});
    });

    test('parse theme_motif et theme_tile_shape depuis le bundle', () {
      final pack = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'a',
        'description_key': 'b',
        'theme_motif': 'vagues',
        'theme_tile_shape': 'diamond',
      });
      expect(pack.themeMotif, 'vagues');
      expect(pack.themeTileShape, 'diamond');
    });
  });

  group('Pack.fromCatalogEntry', () {
    test('parse theme_id et theme_overrides remote', () {
      final pack = Pack.fromCatalogEntry(const <String, dynamic>{
        'id': 'crack_nouchi',
        'theme_id': 'abidjan_neon',
        'theme_overrides': <String, dynamic>{
          'path': '#35E0C8',
          'ignored': 42, // valeur non-String filtrée
        },
      });
      expect(pack.themeId, 'abidjan_neon');
      expect(pack.themeOverrides, <String, String>{'path': '#35E0C8'});
    });

    test('theme_overrides absent → null', () {
      final pack = Pack.fromCatalogEntry(const <String, dynamic>{
        'id': 'culture_ci',
      });
      expect(pack.themeId, isNull);
      expect(pack.themeOverrides, isNull);
    });
  });

  group('Pack.mergeWithRemote', () {
    test('le remote override themeId/overrides du bundle', () {
      final bundle = Pack.fromIndexEntry('culture_ci', const <String, dynamic>{
        'name_key': 'pack.culture_ci.name',
        'description_key': 'pack.culture_ci.description',
        'count': 30,
      });
      final remote = Pack.fromCatalogEntry(const <String, dynamic>{
        'id': 'culture_ci',
        'theme_id': 'terre_baoule',
        'theme_overrides': <String, dynamic>{'accent': '#E9B949'},
      });
      final merged = bundle.mergeWithRemote(remote);
      expect(merged.themeId, 'terre_baoule');
      expect(merged.themeOverrides, <String, String>{'accent': '#E9B949'});
    });
  });
}
