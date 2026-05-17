import 'package:flutter_test/flutter_test.dart';
import 'package:kilimandjaro_admin/src/packs/domain/question_validators.dart';

void main() {
  group('canonicalizeAnswer', () {
    test('uppercase + ASCII-only', () {
      expect(canonicalizeAnswer('foutou'), 'FOUTOU');
      expect(canonicalizeAnswer('attiéké'), 'ATTIEKE');
      expect(canonicalizeAnswer('  Baoulé '), 'BAOULE');
    });

    test('strips digits, punctuation and spaces', () {
      expect(canonicalizeAnswer('foutou123'), 'FOUTOU');
      expect(canonicalizeAnswer("D'jolof"), 'DJOLOF');
      expect(canonicalizeAnswer('foutou-bis'), 'FOUTOUBIS');
    });
  });

  group('normalizeAnswer', () {
    test('matches TS normalize (lowercase + strip diacritics)', () {
      expect(normalizeAnswer('FOUTOU'), 'foutou');
      expect(normalizeAnswer('Attiéké'), 'attieke');
      expect(normalizeAnswer('CÉCEDILLE'), 'cecedille');
    });
  });

  group('validateAnswer', () {
    test('rejects too short / too long', () {
      expect(validateAnswer(''), isNotNull);
      expect(validateAnswer('ABC'), isNotNull);
      expect(validateAnswer('ABCDEFGHI'), isNotNull);
    });
    test('accepts 4..8 letters', () {
      expect(validateAnswer('ABCD'), isNull);
      expect(validateAnswer('FOUTOU'), isNull);
      expect(validateAnswer('ATTIEKE'), isNull);
      expect(validateAnswer('AKWABASS'), isNull);
    });
    test('rejects non-A-Z', () {
      expect(validateAnswer('ABC1'), isNotNull);
    });
  });

  group('lettersPoolFromAnswer / validateLettersPool', () {
    test('pool == letters of answer', () {
      expect(lettersPoolFromAnswer('FOUTOU'),
          ['F', 'O', 'U', 'T', 'O', 'U']);
      expect(lettersPoolFromAnswer('BAOULE'),
          ['B', 'A', 'O', 'U', 'L', 'E']);
    });
    test('detects mismatch in length', () {
      expect(
        validateLettersPool('FOUTOU', ['F', 'O', 'U', 'T', 'O']),
        isNotNull,
      );
    });
    test('detects mismatch in multiset (different letters)', () {
      expect(
        validateLettersPool('FOUTOU', ['F', 'O', 'U', 'T', 'O', 'A']),
        isNotNull,
      );
    });
    test('accepts pool in any order (multiset)', () {
      expect(
        validateLettersPool('FOUTOU', ['O', 'F', 'O', 'U', 'T', 'U']),
        isNull,
      );
    });
  });

  group('estimatedTimeForDifficulty', () {
    test('deterministic mapping', () {
      expect(estimatedTimeForDifficulty(1), 20);
      expect(estimatedTimeForDifficulty(2), 25);
      expect(estimatedTimeForDifficulty(3), 30);
      expect(estimatedTimeForDifficulty(4), 35);
      expect(estimatedTimeForDifficulty(5), 40);
    });
  });

  group('validatePackId / validateId', () {
    test('packId rules', () {
      expect(validatePackId('culture_ci'), isNull);
      expect(validatePackId('histoire_ci'), isNull);
      expect(validatePackId('1bad'), isNotNull);
      expect(validatePackId('UPPER'), isNotNull);
      expect(validatePackId(''), isNotNull);
    });
    test('id must start with packId_', () {
      expect(validateId('culture_ci_001', pack: 'culture_ci'), isNull);
      expect(validateId('crack_nouchi_001', pack: 'crack_nouchi'), isNull);
      expect(validateId('wrong_001', pack: 'culture_ci'), isNotNull);
      expect(validateId('Bad-Id', pack: 'x'), isNotNull);
    });
  });

  group('validateRiddleFr / validateExplanationFr', () {
    test('riddle bounds', () {
      expect(validateRiddleFr(''), isNotNull);
      expect(validateRiddleFr('short'), isNotNull);
      expect(validateRiddleFr('Un énoncé suffisamment long.'), isNull);
      expect(validateRiddleFr('a' * 281), isNotNull);
    });
    test('explanation bounds', () {
      expect(validateExplanationFr(''), isNotNull);
      expect(validateExplanationFr('too short'), isNotNull);
      expect(
        validateExplanationFr('Une explication assez longue avec contexte.'),
        isNull,
      );
      expect(validateExplanationFr('a' * 501), isNotNull);
    });
  });

  group('validateTags', () {
    test('accepts up to 8 lowercase tags', () {
      expect(validateTags(['cuisine', 'tradition']), isNull);
      expect(validateTags(List.generate(9, (i) => 'tag$i')), isNotNull);
      expect(validateTags(['Bad Case']), isNotNull);
      expect(validateTags(['']), isNotNull);
    });
  });
}
