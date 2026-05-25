import 'package:defi_kilimandjaro/data/services/daily_streak_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DailyStreakService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('première ouverture renvoie 1', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = DailyStreakService(prefs);
      expect(await svc.registerOpen(DateTime(2026, 5, 25)), 1);
    });

    test('même jour = no-op (idempotent)', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = DailyStreakService(prefs);
      final day = DateTime(2026, 5, 25, 8);
      await svc.registerOpen(day);
      expect(await svc.registerOpen(day.add(const Duration(hours: 6))), 1);
    });

    test('lendemain = +1', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = DailyStreakService(prefs);
      await svc.registerOpen(DateTime(2026, 5, 25));
      expect(await svc.registerOpen(DateTime(2026, 5, 26)), 2);
    });

    test('gap > 1 jour reset à 1', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = DailyStreakService(prefs);
      await svc.registerOpen(DateTime(2026, 5, 25));
      await svc.registerOpen(DateTime(2026, 5, 26));
      expect(await svc.registerOpen(DateTime(2026, 5, 30)), 1);
    });

    test('current() lit sans muter', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = DailyStreakService(prefs);
      await svc.registerOpen(DateTime(2026, 5, 25));
      expect(svc.current(), 1);
      expect(svc.current(), 1);
    });
  });
}
