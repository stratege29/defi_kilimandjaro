import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Devinette.fromJson', () {
    test('parse v3 multilingue (Map<String,String>) avec pack thématique', () {
      final d = Devinette.fromJson(const <String, dynamic>{
        'id': 'culture_ci_001',
        'pack': 'culture_ci',
        'country': 'ci',
        'answer': 'foutou',
        'answer_normalized': 'foutou',
        'letters_pool': <String>['F', 'O', 'U', 'T', 'O', 'U'],
        'riddle': <String, String>{'fr': 'Au mortier', 'en': 'In the mortar'},
        'explanation': <String, String>{
          'fr': 'Pâte pilée',
          'en': 'Pounded paste',
        },
        'difficulty': 1,
        'estimated_time_s': 25,
        'tags': <String>['cuisine'],
        'format_version': 3,
      });

      expect(d.answer, 'FOUTOU');
      expect(d.formatVersion, 3);
      expect(d.pack, 'culture_ci');
      expect(d.riddleByLang['fr'], 'Au mortier');
      expect(d.riddleByLang['en'], 'In the mortar');
    });

    test('tolère un String plat dans riddle (enrobé sous "fr")', () {
      final d = Devinette.fromJson(const <String, dynamic>{
        'id': 'crack_nouchi_x',
        'pack': 'crack_nouchi',
        'country': 'ci',
        'answer': 'mais',
        'letters_pool': <String>['M', 'A', 'I', 'S'],
        'riddle': 'Grain doré',
        'explanation': 'Céréale',
        'difficulty': 1,
        'estimated_time_s': 20,
        'tags': <String>['cereale'],
      });

      expect(d.formatVersion, 3);
      expect(d.pack, 'crack_nouchi');
      expect(d.riddleByLang, {'fr': 'Grain doré'});
      expect(d.explanationByLang, {'fr': 'Céréale'});
    });
  });

  group('Devinette getters localisés', () {
    const d = Devinette(
      id: 'x',
      pack: 'culture_ci',
      country: 'ci',
      answer: 'X',
      lettersPool: ['X'],
      riddleByLang: {'fr': 'fr-r', 'en': 'en-r'},
      explanationByLang: {'fr': 'fr-e'},
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
    test('v3 → toJson → fromJson conserve toutes les langues', () {
      const original = Devinette(
        id: 'x',
        pack: 'culture_ci',
        country: 'ci',
        answer: 'OK',
        answerNormalized: 'ok',
        lettersPool: ['O', 'K'],
        riddleByLang: {'fr': 'a', 'en': 'b'},
        explanationByLang: {'fr': 'c'},
        difficulty: 2,
        estimatedTimeS: 15,
        tags: ['t1'],
      );
      final restored = Devinette.fromJson(original.toJson());
      expect(restored.pack, 'culture_ci');
      expect(restored.riddleByLang, original.riddleByLang);
      expect(restored.explanationByLang, original.explanationByLang);
      expect(restored.formatVersion, 3);
    });
  });
}
