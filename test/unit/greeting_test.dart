import 'package:defi_kilimandjaro/presentation/home/greeting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('greetingFor', () {
    test('matin (5h-11h) tire dans le pool matin', () {
      final s = greetingFor(DateTime(2026, 5, 25, 8));
      expect(
        ['Akwaba', 'I ni sɔgɔma', "N'douba", 'Anuanom'].contains(s),
        isTrue,
        reason: 'salutation reçue: $s',
      );
    });

    test('après-midi (12h-17h) tire dans le pool après-midi', () {
      final s = greetingFor(DateTime(2026, 5, 25, 14));
      expect(
        ['Akwaba', 'I ni wula', 'Bonjour', 'Anuanom'].contains(s),
        isTrue,
        reason: 'salutation reçue: $s',
      );
    });

    test('soir (18h-21h) tire dans le pool soir', () {
      final s = greetingFor(DateTime(2026, 5, 25, 20));
      expect(
        ['I ni su', 'Bonsoir', 'Akwaba'].contains(s),
        isTrue,
        reason: 'salutation reçue: $s',
      );
    });

    test('nuit (22h-4h) tire dans le pool nuit', () {
      final s23 = greetingFor(DateTime(2026, 5, 25, 23));
      final s3 = greetingFor(DateTime(2026, 5, 25, 3));
      for (final s in [s23, s3]) {
        expect(
          ['Akwaba', 'Bonsoir'].contains(s),
          isTrue,
          reason: 'salutation reçue: $s',
        );
      }
    });

    test('déterministe pour un même (jour, heure)', () {
      final d = DateTime(2026, 5, 25, 8);
      expect(greetingFor(d), greetingFor(d));
    });
  });
}
