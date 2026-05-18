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

    test('imageUrl null par défaut quand absent', () {
      final pack = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'a',
        'description_key': 'b',
      });
      expect(pack.imageUrl, isNull);
    });

    test('imageUrl parsé quand présent', () {
      final pack = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'a',
        'description_key': 'b',
        'image_url': 'https://cdn.example/x.webp?v=123',
      });
      expect(pack.imageUrl, 'https://cdn.example/x.webp?v=123');
    });
  });

  group('Pack.copyWith', () {
    test('remplace uniquement imageUrl', () {
      final p = Pack.fromIndexEntry('culture_ci', const <String, dynamic>{
        'name_key': 'pack.culture_ci.name',
        'description_key': 'pack.culture_ci.description',
        'count': 30,
        'free_choice_eligible': true,
        'price_eur': 2.99,
        'price_cauris': 2000,
      });
      final enriched = p.copyWith(imageUrl: 'https://x/img.webp?v=1');
      expect(enriched.imageUrl, 'https://x/img.webp?v=1');
      expect(enriched.id, p.id);
      expect(enriched.questionCount, p.questionCount);
      expect(enriched.freeChoiceEligible, p.freeChoiceEligible);
    });

    test('préserve imageUrl quand null passé', () {
      final p = Pack.fromIndexEntry('x', const <String, dynamic>{
        'name_key': 'a',
        'description_key': 'b',
        'image_url': 'https://existing.example/x.webp',
      });
      final c = p.copyWith();
      expect(c.imageUrl, 'https://existing.example/x.webp');
    });
  });
}
