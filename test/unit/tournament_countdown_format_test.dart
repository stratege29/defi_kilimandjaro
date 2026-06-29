import 'package:defi_kilimandjaro/presentation/tournament/widgets/tournament_countdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TournamentCountdown.format', () {
    test('shows MM:SS under one hour', () {
      expect(
        TournamentCountdown.format(const Duration(minutes: 5, seconds: 9)),
        '05:09',
      );
    });

    test('shows HH:MM:SS at one hour or more', () {
      expect(
        TournamentCountdown.format(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '01:02:03',
      );
    });

    test('zero duration', () {
      expect(TournamentCountdown.format(Duration.zero), '00:00');
    });

    test('rolls minutes correctly', () {
      expect(
        TournamentCountdown.format(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
    });
  });
}
