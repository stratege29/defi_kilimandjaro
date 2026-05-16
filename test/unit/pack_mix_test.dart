import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackMix construction', () {
    test('accepte un mix qui somme à 1.0', () {
      final mix = PackMix(
        weights: const <String, double>{'a': 0.7, 'b': 0.3},
      );
      expect(mix.weights['a'], 0.7);
      expect(mix.weights['b'], 0.3);
    });

    test('tolère ±epsilon sur la somme (rounding flottant)', () {
      // 0.1 + 0.2 = 0.30000000000000004 en IEEE-754
      final mix = PackMix(
        weights: const <String, double>{'a': 0.1, 'b': 0.2, 'c': 0.7},
      );
      expect(mix.packIds, {'a', 'b', 'c'});
    });

    test("throw quand somme != 1.0 (au-delà d'epsilon)", () {
      expect(
        () => PackMix(weights: const <String, double>{'a': 0.5, 'b': 0.4}),
        throwsArgumentError,
      );
    });

    test('throw quand mix vide', () {
      expect(
        () => PackMix(weights: const <String, double>{}),
        throwsArgumentError,
      );
    });

    test('throw quand un poids est nul', () {
      expect(
        () => PackMix(weights: const <String, double>{'a': 1.0, 'b': 0.0}),
        throwsArgumentError,
      );
    });

    test('throw quand un poids est négatif', () {
      expect(
        () => PackMix(weights: const <String, double>{'a': 1.2, 'b': -0.2}),
        throwsArgumentError,
      );
    });
  });

  group('PackMix factories', () {
    test('single renvoie un mix mono-pack à 100%', () {
      final mix = PackMix.single('culture_ci');
      expect(mix.weights, {'culture_ci': 1.0});
      expect(mix.isSingle, isTrue);
    });

    test('uniform distribue équitablement', () {
      final mix = PackMix.uniform(const ['a', 'b', 'c', 'd']);
      for (final w in mix.weights.values) {
        expect(w, closeTo(0.25, 1e-9));
      }
    });

    test('uniform throw sur liste vide', () {
      expect(() => PackMix.uniform(const <String>[]), throwsArgumentError);
    });

    test('normalized renormalise des poids non-sommés', () {
      final mix = PackMix.normalized(
        const <String, double>{'a': 70, 'b': 30},
      );
      expect(mix.weights['a'], closeTo(0.7, 1e-9));
      expect(mix.weights['b'], closeTo(0.3, 1e-9));
    });

    test('normalized retire les entrées ≤ 0 avant validation', () {
      final mix = PackMix.normalized(
        const <String, double>{'a': 70, 'b': 30, 'c': 0, 'd': -5},
      );
      expect(mix.packIds, {'a', 'b'});
    });

    test('normalized throw quand tout est ≤ 0', () {
      expect(
        () => PackMix.normalized(const <String, double>{'a': 0, 'b': -1}),
        throwsArgumentError,
      );
    });
  });

  group('PackMix JSON roundtrip', () {
    test('tryFromJson parse un Map valide', () {
      final mix = PackMix.tryFromJson(
        const <String, dynamic>{'a': 0.7, 'b': 0.3},
      );
      expect(mix, isNotNull);
      expect(mix!.packIds, {'a', 'b'});
    });

    test('tryFromJson normalise un Map non sommé', () {
      final mix = PackMix.tryFromJson(
        const <String, dynamic>{'a': 70, 'b': 30},
      );
      expect(mix!.weights['a'], closeTo(0.7, 1e-9));
    });

    test('tryFromJson retourne null sur payload invalide', () {
      expect(PackMix.tryFromJson(null), isNull);
      expect(PackMix.tryFromJson('not a map'), isNull);
      expect(
        PackMix.tryFromJson(<String, dynamic>{'a': 'not a number'}),
        isNull,
      );
      expect(PackMix.tryFromJson(<String, dynamic>{}), isNull);
    });

    test('toJson → tryFromJson roundtrip stable', () {
      final original = PackMix(
        weights: const <String, double>{'culture_ci': 0.6, 'crack_nouchi': 0.4},
      );
      final back = PackMix.tryFromJson(original.toJson());
      expect(back, original);
    });
  });

  group('PackMix equality', () {
    test('deux mixes avec mêmes poids sont égaux', () {
      final a = PackMix(weights: const <String, double>{'x': 0.5, 'y': 0.5});
      final b = PackMix(weights: const <String, double>{'x': 0.5, 'y': 0.5});
      expect(a, b);
    });
  });
}
