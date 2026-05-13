import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Devinette.fromJson', () {
    test('parse v2 multilingue (Map<String,String>)', () {
      final d = Devinette.fromJson(<String, dynamic>{
        'id': 'x_001',
        'world': 'village_des_or',
        'country': 'ci',
        'answer': 'foutou',
        'answer_normalized': 'foutou',
        'letters_pool':['F', 'O', 'U', 'T', 'O', 'U'],
        'riddle': {'fr': 'Au mortier', 'en': 'In the mortar'},
        'explanation': {'fr': 'Pâte pilée', 'en': 'Pounded paste'},
        'proverb': {'fr': 'Ensemble', 'en': 'Together'},
        'difficulty': 1,
        'estimated_time_s': 25,
        'tags': ['cuisine'],
        'format_version': 2,
      });

      expect(d.answer, 'FOUTOU');
      expect(d.formatVersion, 2);
      expect(d.riddleByLang['fr'], 'Au mortier');
      expect(d.riddleByLang['en'], 'In the mortar');
    });

    test('parse v1 legacy (riddle = String) → enrobé sous "fr"', () {
      final d = Devinette.fromJson(<String, dynamic>{
        'id': 'x_002',
        'world': 'village_des_or',
        'country': 'ci',
        'answer': 'mais',
        'letters_pool': <String>['M', 'A', 'I', 'S'],
        'riddle': 'Grain doré',
        'explanation': 'Céréale',
        'proverb': 'Chaque grain compte.',
        'difficulty': 1,
        'estimated_time_s': 20,
        'tags': ['cereale'],
      });

      expect(d.formatVersion, 1);
      expect(d.riddleByLang, {'fr': 'Grain doré'});
      expect(d.explanationByLang, {'fr': 'Céréale'});
      expect(d.proverbByLang, {'fr': 'Chaque grain compte.'});
    });
  });

  group('Devinette getters localisés', () {
    const d = Devinette(
      id: 'x',
      world: 'w',
      country: 'ci',
      answer: 'X',
      lettersPool: ['X'],
      riddleByLang: {'fr': 'fr-r', 'en': 'en-r'},
      explanationByLang: {'fr': 'fr-e'},
      proverbByLang: {'fr': 'fr-p'},
      difficulty: 1,
      estimatedTimeS: 10,
      tags: [],
    );

    test('utilise la langue active', () {
      DevinetteLocale.activeLang = 'en';
      expect(d.riddle, 'en-r');
      DevinetteLocale.activeLang = 'fr';
      expect(d.riddle, 'fr-r');
    });

    test('fallback sur fr puis premier disponible', () {
      DevinetteLocale.activeLang = 'es';
      // explanation n'a que 'fr' → fallback fr.
      expect(d.explanation, 'fr-e');
    });

    test('localized() avec lang explicite', () {
      DevinetteLocale.activeLang = 'fr';
      expect(d.localized(d.riddleByLang, lang: 'en'), 'en-r');
    });
  });

  group('Devinette.toJson roundtrip', () {
    test('v2 → toJson → fromJson conserve toutes les langues', () {
      const original = Devinette(
        id: 'x',
        world: 'w',
        country: 'ci',
        answer: 'OK',
        answerNormalized: 'ok',
        lettersPool: ['O', 'K'],
        riddleByLang: {'fr': 'a', 'en': 'b'},
        explanationByLang: {'fr': 'c'},
        proverbByLang: {'fr': 'd'},
        difficulty: 2,
        estimatedTimeS: 15,
        tags: ['t1'],
      );
      final restored = Devinette.fromJson(original.toJson());
      expect(restored.riddleByLang, original.riddleByLang);
      expect(restored.explanationByLang, original.explanationByLang);
      expect(restored.formatVersion, 2);
    });
  });
}
