import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests unitaires des DTOs et de la logique pure de `WalletService`.
///
/// Les appels Firebase Functions réels sont testés via emulator
/// (Phase 4.7 — différé).
void main() {
  group('BootstrapWalletResult.fromMap', () {
    test('parse un payload standard de la CF', () {
      final r = BootstrapWalletResult.fromMap({
        'created': true,
        'cauris': 120,
        'ownedPacks': ['culture_ci'],
        'version': 1,
        'capped': false,
      });
      expect(r.created, true);
      expect(r.cauris, 120);
      expect(r.ownedPacks, ['culture_ci']);
      expect(r.version, 1);
      expect(r.capped, false);
    });

    test('défaut created=false si manquant (idempotent re-call)', () {
      final r = BootstrapWalletResult.fromMap({
        'cauris': 350,
        'version': 5,
      });
      expect(r.created, false);
      expect(r.ownedPacks, isEmpty);
    });
  });

  group('UnlockPackResult.fromMap', () {
    test('parse un payload après débit réussi', () {
      final r = UnlockPackResult.fromMap({
        'packId': 'football_ci',
        'cauris': 1500,
        'ownedPacks': ['culture_ci', 'football_ci'],
        'version': 7,
        'cost': 500,
      });
      expect(r.packId, 'football_ci');
      expect(r.cauris, 1500);
      expect(r.ownedPacks, hasLength(2));
      expect(r.cost, 500);
    });
  });

  group('CreditCaurisResult.fromMap', () {
    test('expose amount effectivement crédité (peut être < demande si plafond)', () {
      final r = CreditCaurisResult.fromMap({
        'cauris': 999999,
        'version': 42,
        'amount': 50, // peut être < requestedAmount si plafond atteint
      });
      expect(r.cauris, 999999);
      expect(r.amount, 50);
    });
  });

  group('SyncWalletResult.fromMap', () {
    test('tolère updatedAtMs null', () {
      final r = SyncWalletResult.fromMap({
        'cauris': 100,
        'ownedPacks': [],
        'version': 1,
      });
      expect(r.updatedAtMs, null);
    });
  });

  group('WalletException', () {
    test('isInsufficientFunds détecte solde insuffisant', () {
      final e = WalletException(
        code: 'failed-precondition',
        message: 'Solde insuffisant : 100 cauris, requis 500.',
      );
      expect(e.isInsufficientFunds, true);
      expect(e.isAlreadyOwned, false);
      expect(e.isNotBootstrapped, false);
    });

    test('isAlreadyOwned détecte already-exists', () {
      final e = WalletException(
        code: 'already-exists',
        message: 'Pack "culture_ci" déjà possédé.',
      );
      expect(e.isAlreadyOwned, true);
      expect(e.isInsufficientFunds, false);
    });

    test('isNotBootstrapped détecte wallet non initialisé', () {
      final e = WalletException(
        code: 'failed-precondition',
        message: 'Wallet non initialisé. Appeler bootstrapWallet d\'abord.',
      );
      expect(e.isNotBootstrapped, true);
      expect(e.isInsufficientFunds, false);
    });

    test('isWalletNotFound détecte syncWallet sur wallet absent', () {
      final e = WalletException(
        code: 'not-found',
        message: 'Wallet pas encore initialisé pour cet utilisateur.',
      );
      expect(e.isWalletNotFound, true);
    });

    test('fromFirebase parse correctement FirebaseFunctionsException', () {
      final fbe = FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Login required',
        details: {'foo': 'bar'},
      );
      final e = WalletException.fromFirebase(fbe);
      expect(e.code, 'unauthenticated');
      expect(e.message, 'Login required');
      expect(e.details, {'foo': 'bar'});
    });

    test('toString contient code + message (debugging)', () {
      final e = WalletException(code: 'x-y', message: 'oups');
      expect(e.toString(), contains('x-y'));
      expect(e.toString(), contains('oups'));
    });
  });

  group('CaurisCreditSource enum', () {
    test('contient toutes les sources prévues serveur', () {
      // Doit matcher CAURIS_CREDIT_MAX_BY_SOURCE côté functions
      final expected = ['win', 'daily', 'rewarded', 'streak', 'iap', 'manual'];
      for (final s in expected) {
        expect(
          CaurisCreditSource.values.map((e) => e.name),
          contains(s),
          reason: 'source $s manquante côté client',
        );
      }
    });
  });
}
