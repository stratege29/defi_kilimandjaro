import 'dart:async';

import 'package:defi_kilimandjaro/data/iap/coin_pack.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logger/logger.dart';

/// Service d'achats in-app — wrap léger autour de `in_app_purchase`.
///
/// - Charge le catalogue produits depuis App Store Connect / Play Console.
/// - Écoute les transactions et les applique au [PlayerProgressNotifier].
/// - Mode dev : si aucun produit retourné par le store, expose les packs
///   en fallback (prix locaux statiques) — la transaction reste désactivée
///   tant que le catalogue n'est pas peuplé.
class IAPService {
  IAPService(this._iap, this._progress);

  final InAppPurchase _iap;
  final PlayerProgressNotifier _progress;
  final Logger _log = Logger();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  Map<String, ProductDetails> _details = const <String, ProductDetails>{};

  /// Appelé une fois au boot.
  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) {
      _log.w('IAP indisponible (sandbox/device sans Apple ID ?)');
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchasesUpdated,
      onError: (Object e) => _log.e('IAP stream error', error: e),
    );

    final response = await _iap.queryProductDetails(
      CoinPack.allProductIds().toSet(),
    );
    if (response.error != null) {
      _log.w('IAP query error: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      _log.w('IAP products not found: ${response.notFoundIDs}');
    }
    _details = <String, ProductDetails>{
      for (final p in response.productDetails) p.id: p,
    };
    _log.i('IAP init done — ${_details.length} products available');
  }

  /// Liste des offres à afficher dans la boutique.
  ///
  /// Si le catalogue store est vide (dev / produits pas encore créés),
  /// on renvoie tous les packs avec leurs prix fallback et `available=false`.
  List<CoinPackOffer> offers() {
    if (_details.isEmpty) {
      return CoinPack.values.map(CoinPackOffer.fallback).toList();
    }
    return [
      for (final p in CoinPack.values)
        if (_details[p.productId] case final d?)
          CoinPackOffer(pack: p, priceLabel: d.price)
        else
          CoinPackOffer.fallback(p),
    ];
  }

  /// Lance l'achat. Retourne `false` si le pack n'est pas dans le catalogue
  /// store (impossible d'acheter en l'état).
  Future<bool> buy(CoinPack pack) async {
    final details = _details[pack.productId];
    if (details == null) {
      _log.w("Tentative achat d'un pack non dispo: ${pack.productId}");
      return false;
    }
    final purchaseParam = PurchaseParam(productDetails: details);
    return _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchasesUpdated(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grant(p);
        case PurchaseStatus.error:
          _log.e('Achat échoué', error: p.error);
        case PurchaseStatus.canceled:
          _log.i("Achat annulé par l'utilisateur");
        case PurchaseStatus.pending:
          _log.i('Achat en attente');
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  Future<void> _grant(PurchaseDetails purchase) async {
    final pack = CoinPack.fromProductId(purchase.productID);
    if (pack == null) {
      _log.w('Achat reconnu mais pack inconnu: ${purchase.productID}');
      return;
    }
    await _progress.addCoins(pack.coins);
    _log.i('+${pack.coins} coins crédités via IAP ${pack.productId}');
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
  }
}

final inAppPurchaseInstanceProvider = Provider<InAppPurchase>(
  (ref) => InAppPurchase.instance,
);

final iapServiceProvider = Provider<IAPService>((ref) {
  final svc = IAPService(
    ref.watch(inAppPurchaseInstanceProvider),
    ref.watch(playerProgressProvider.notifier),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Liste d'offres réactive — re-fetch quand on appelle `refresh()`.
class CoinOffersNotifier extends StateNotifier<List<CoinPackOffer>> {
  CoinOffersNotifier(this._service) : super(_service.offers());

  final IAPService _service;

  Future<void> refresh() async {
    state = _service.offers();
  }

  Future<bool> buy(CoinPack pack) => _service.buy(pack);

  Future<void> restore() => _service.restore();
}

final coinOffersProvider =
    StateNotifierProvider<CoinOffersNotifier, List<CoinPackOffer>>((ref) {
  return CoinOffersNotifier(ref.watch(iapServiceProvider));
});
