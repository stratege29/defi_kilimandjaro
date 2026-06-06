import 'package:defi_kilimandjaro/domain/services/pack_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('packIdFromDevinetteId', () {
    test('dérive le packId du suffixe numérique (3 chiffres)', () {
      expect(packIdFromDevinetteId('culture_ci_221'), 'culture_ci');
    });

    test('dérive le packId (4 chiffres)', () {
      expect(packIdFromDevinetteId('football_ci_1024'), 'football_ci');
    });

    test('gère un packId à underscores multiples', () {
      expect(packIdFromDevinetteId('crack_nouchi_007'), 'crack_nouchi');
    });

    test('retourne null pour un id sans suffixe numérique (samples)', () {
      expect(packIdFromDevinetteId('sample_easy_1'), isNull);
      expect(packIdFromDevinetteId('kora'), isNull);
    });

    test('retourne null pour une chaîne vide', () {
      expect(packIdFromDevinetteId(''), isNull);
    });
  });
}
