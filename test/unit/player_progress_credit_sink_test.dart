import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/wallet/cauris_credit_sink.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSink implements CaurisCreditSink {
  final List<({int amount, CaurisCreditSource source, String? reference})>
      credits = [];

  @override
  void enqueue({
    required int amount,
    required CaurisCreditSource source,
    String? reference,
  }) {
    credits.add((amount: amount, source: source, reference: reference));
  }
}

void main() {
  late _RecordingSink sink;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sink = _RecordingSink();
  });

  Future<PlayerProgressNotifier> buildNotifier() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerProgressNotifier(
      PlayerProgressRepository(prefs),
      creditSink: sink,
    );
  }

  group('PlayerProgressNotifier — enqueue des crédits vers le wallet', () {
    test('recordWin enfile le gain avec source win', () async {
      final notifier = await buildNotifier();
      await notifier.recordWin(
        mountainId: 'kili',
        caurisAwarded: 42,
        levelIndex: 0,
        starsEarned: 3,
        devinetteId: 'dev_7',
      );

      expect(sink.credits, hasLength(1));
      expect(sink.credits.single.amount, 42);
      expect(sink.credits.single.source, CaurisCreditSource.win);
      expect(sink.credits.single.reference, 'dev_7');
    });

    test('claimDailyStreak enfile le bonus avec source streak', () async {
      final notifier = await buildNotifier();
      const config = GameEconomyConfig.defaults;
      final bonus = await notifier.claimDailyStreak(config: config);

      expect(bonus, greaterThan(0));
      expect(sink.credits, hasLength(1));
      expect(sink.credits.single.amount, bonus);
      expect(sink.credits.single.source, CaurisCreditSource.streak);
    });

    test("recordDailyChallengeResult succès enfile, échec n'enfile rien",
        () async {
      final notifier = await buildNotifier();
      final awarded = await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 6, 2),
        success: true,
      );
      expect(awarded, greaterThan(0));
      expect(sink.credits, hasLength(1));
      expect(sink.credits.single.source, CaurisCreditSource.daily);

      await notifier.recordDailyChallengeResult(
        date: DateTime(2026, 6, 3),
        success: false,
      );
      // Échec → pas de nouveau crédit.
      expect(sink.credits, hasLength(1));
    });

    test("addCauris sans source : crédit purement local (pas d'enqueue)",
        () async {
      final notifier = await buildNotifier();
      await notifier.addCauris(100);
      expect(sink.credits, isEmpty);
    });

    test('addCauris avec source rewarded : enfile', () async {
      final notifier = await buildNotifier();
      await notifier.addCauris(50, source: CaurisCreditSource.rewarded);
      expect(sink.credits.single.source, CaurisCreditSource.rewarded);
      expect(sink.credits.single.amount, 50);
    });

    test('grantStarterPack enfile le bonus avec source iap', () async {
      final notifier = await buildNotifier();
      await notifier.grantStarterPack(caurisBonus: 300);
      expect(sink.credits.single.source, CaurisCreditSource.iap);
      expect(sink.credits.single.amount, 300);
      expect(sink.credits.single.reference, 'starter_pack');
    });
  });
}
