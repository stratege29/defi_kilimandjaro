import 'dart:convert';

import 'package:defi_kilimandjaro/data/wallet/cauris_credit_outbox.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake `WalletService` scriptable : on contrôle l'issue de chaque
/// `creditCauris` et on enregistre les appels (clé d'idempotence incluse).
class _FakeWallet implements WalletService {
  _FakeWallet({this.behavior});

  /// Décide de l'issue par appel ; `null` → succès. Lève une
  /// [WalletException] pour simuler un rejet.
  WalletException? Function(String key)? behavior;

  final List<({String? key, int amount, CaurisCreditSource source})> calls = [];

  @override
  Future<CreditCaurisResult> creditCauris({
    required int amount,
    required CaurisCreditSource source,
    String? reference,
    String? idempotencyKey,
  }) async {
    calls.add((key: idempotencyKey, amount: amount, source: source));
    final err = behavior?.call(idempotencyKey ?? '');
    if (err != null) throw err;
    return CreditCaurisResult(cauris: 1000, version: 2, amount: amount);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non utilisé en test');
}

const _storageKey = 'cauris_credit_outbox';

List<Map<String, dynamic>> _queue(SharedPreferences prefs) {
  final raw = prefs.getString(_storageKey);
  if (raw == null) return [];
  return (jsonDecode(raw) as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .toList();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  group('CaurisCreditOutbox — outbox idempotent durable', () {
    test('enqueue puis flush : pousse une fois et vide la file', () async {
      final wallet = _FakeWallet();
      CaurisCreditOutbox(prefs: prefs, wallet: wallet)
          .enqueue(amount: 30, source: CaurisCreditSource.win);
      await pumpEventQueue();

      expect(wallet.calls, hasLength(1));
      expect(wallet.calls.single.amount, 30);
      expect(wallet.calls.single.source, CaurisCreditSource.win);
      expect(wallet.calls.single.key, isNotNull); // clé UUID émise.
      expect(_queue(prefs), isEmpty); // file drainée.
    });

    test('amount <= 0 : aucun enqueue', () async {
      final wallet = _FakeWallet();
      CaurisCreditOutbox(prefs: prefs, wallet: wallet)
        ..enqueue(amount: 0, source: CaurisCreditSource.win)
        ..enqueue(amount: -5, source: CaurisCreditSource.win);
      await pumpEventQueue();

      expect(wallet.calls, isEmpty);
      expect(_queue(prefs), isEmpty);
    });

    test("erreur transitoire : retient l'entrée pour un flush ultérieur",
        () async {
      // Le 1er essai échoue (réseau), le 2e réussit — même clé (exactly-once).
      var attempt = 0;
      final wallet = _FakeWallet(
        behavior: (_) {
          attempt++;
          if (attempt == 1) {
            return WalletException(code: 'unavailable', message: 'offline');
          }
          return null;
        },
      );
      final outbox = CaurisCreditOutbox(prefs: prefs, wallet: wallet)
        ..enqueue(amount: 50, source: CaurisCreditSource.rewarded);
      await pumpEventQueue();

      // 1er flush a échoué → entrée conservée.
      expect(_queue(prefs), hasLength(1));
      final keyAfterFail = _queue(prefs).single['key'] as String;
      expect(_queue(prefs).single['attempts'], 1);

      await outbox.flush();

      // 2e flush a réussi → file vidée, et la clé était STABLE entre essais.
      expect(_queue(prefs), isEmpty);
      expect(wallet.calls.map((c) => c.key).toSet(), {keyAfterFail});
      expect(wallet.calls, hasLength(2));
    });

    test('cap anti-cheat (invalid-argument) : rejet permanent, drop', () async {
      final wallet = _FakeWallet(
        behavior: (_) => WalletException(
          code: 'invalid-argument',
          message: 'Montant dépasse le cap',
        ),
      );
      CaurisCreditOutbox(prefs: prefs, wallet: wallet)
          .enqueue(amount: 99999, source: CaurisCreditSource.win);
      await pumpEventQueue();

      expect(wallet.calls, hasLength(1));
      expect(_queue(prefs), isEmpty); // supprimée, pas de retry infini.
    });

    test('wallet non bootstrapped : retient pour flush post-reconcile',
        () async {
      final wallet = _FakeWallet(
        behavior: (_) => WalletException(
          code: 'failed-precondition',
          message: "Wallet non initialisé. Appeler bootstrapWallet d'abord.",
        ),
      );
      CaurisCreditOutbox(prefs: prefs, wallet: wallet)
          .enqueue(amount: 30, source: CaurisCreditSource.win);
      await pumpEventQueue();

      expect(_queue(prefs), hasLength(1)); // conservée pour plus tard.
    });

    test("flush draine plusieurs entrées dans l'ordre", () async {
      final wallet = _FakeWallet();
      CaurisCreditOutbox(prefs: prefs, wallet: wallet)
        ..enqueue(amount: 30, source: CaurisCreditSource.win)
        ..enqueue(amount: 100, source: CaurisCreditSource.daily)
        ..enqueue(amount: 50, source: CaurisCreditSource.rewarded);
      await pumpEventQueue();

      expect(wallet.calls.map((c) => c.amount).toList(), [30, 100, 50]);
      // Clés toutes distinctes (un crédit ≠ un autre).
      expect(wallet.calls.map((c) => c.key).toSet(), hasLength(3));
      expect(_queue(prefs), isEmpty);
    });

    test('durabilité : une file pré-persistée est rejouée au flush', () async {
      // Simule des crédits accumulés offline puis app tuée → reboot.
      await prefs.setString(
        _storageKey,
        jsonEncode([
          {'key': 'k1', 'amount': 30, 'source': 'win', 'attempts': 0},
          {'key': 'k2', 'amount': 100, 'source': 'daily', 'attempts': 2},
        ]),
      );
      final wallet = _FakeWallet();
      final outbox = CaurisCreditOutbox(prefs: prefs, wallet: wallet);

      await outbox.flush();

      expect(wallet.calls.map((c) => c.key).toList(), ['k1', 'k2']);
      expect(_queue(prefs), isEmpty);
    });
  });
}
