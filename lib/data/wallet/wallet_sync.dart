import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/wallet/cauris_credit_outbox.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Réconcilie le **wallet serveur** (cauris + packs) avec l'état local à la
/// (re)connexion de compte et au boot.
///
/// Comble le trou de récupération multi-appareil pour le solde : après une
/// réinstallation + reconnexion, le joueur retrouve ses cauris et ses packs
/// achetés via le wallet Cloud Functions (`users/{uid}/inventory/wallet`),
/// que la sauvegarde `player_progress/{uid}` exclut volontairement (le solde
/// est autorité serveur, jamais stocké dans un doc client-inscriptible).
///
/// Tout est *fail-soft* : une erreur réseau ne dégrade jamais le jeu offline.
class WalletSyncCoordinator {
  WalletSyncCoordinator(this._ref);

  final Ref _ref;

  /// Tire l'état serveur et l'adopte localement (`max` cauris, union packs).
  /// Si aucun wallet n'existe encore côté serveur (`not-found`), en crée un
  /// à partir de l'état local courant (bootstrap idempotent).
  Future<void> reconcileOnLogin() async {
    final wallet = _ref.read(walletServiceProvider);
    final progress = _ref.read(playerProgressProvider.notifier);
    try {
      final result = await wallet.sync();
      await progress.adoptWallet(
        serverCauris: result.cauris,
        serverOwnedPacks: result.ownedPacks,
      );
    } on WalletException catch (e) {
      if (e.isWalletNotFound) {
        await _bootstrapFromLocal(wallet);
      }
      // Autres erreurs (réseau, App Check…) : fail-soft, offline-first.
    } on Object {
      // fail-soft : la réconciliation re-tentera au prochain boot/login.
    }
    // Le wallet existe désormais (sync ou bootstrap) : on draine l'outbox
    // des crédits in-game accumulés offline, exactly-once via leurs clés.
    await _flushCreditOutbox();
  }

  Future<void> _flushCreditOutbox() async {
    try {
      await _ref.read(caurisCreditOutboxProvider).flush();
    } on Object {
      // fail-soft : un flush manqué sera retenté au prochain boot/gain.
    }
  }

  Future<void> _bootstrapFromLocal(WalletService wallet) async {
    final local = _ref.read(playerProgressProvider);
    try {
      await wallet.bootstrap(
        cauris: local.cauris,
        ownedPacks: local.ownedPacks.toList(),
      );
    } on Object {
      // fail-soft : un bootstrap manqué sera retenté plus tard.
    }
  }
}

final walletSyncCoordinatorProvider = Provider<WalletSyncCoordinator>(
  WalletSyncCoordinator.new,
);
