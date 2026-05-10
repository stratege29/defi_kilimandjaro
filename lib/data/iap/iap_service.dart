import 'dart:async';

import 'package:defi_kilimandjaro/data/iap/cauris_pack.dart';
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

    final allIds = <String>{
      ...CaurisPack.allProductIds(),
      noAdsProductId,
    };
    final response = await _iap.queryProductDetails(allIds);
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

  /// Lance l'achat du non-consumable "Supprimer les pubs".
  Future<bool> buyNoAds() async {
    final details = _details[noAdsProductId];
    if (details == null) return false;
    final purchaseParam = PurchaseParam(productDetails: details);
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Détails du No-Ads (null si pas dans le catalogue).
  ProductDetails? get noAdsDetails => _details[noAdsProductId];

  /// Liste des offres à afficher dans la boutique.
  ///
  /// Si le catalogue store est vide (dev / produits pas encore créés),
  /// on renvoie tous les packs avec leurs prix fallback et `available=false`.
  List<CaurisPackOffer> offers() {
    if (_details.isEmpty) {
      return CaurisPack.values.map(CaurisPackOffer.fallback).toList();
    }
    return [
      for (final p in CaurisPack.values)
        if (_details[p.productId] case final d?)
          CaurisPackOffer(pack: p, priceLabel: d.price)
        else
          CaurisPackOffer.fallback(p),
    ];
  }

  /// Lance l'achat. Retourne `false` si le pack n'est pas dans le catalogue
  /// store (impossible d'acheter en l'état).
  Future<bool> buy(CaurisPack pack) async {
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
    if (purchase.productID == noAdsProductId) {
      await _progress.grantNoAds();
      _log.i('No-Ads accordé via IAP');
      return;
    }
    final pack = CaurisPack.fromProductId(purchase.productID);
    if (pack == null) {
      _log.w('Achat reconnu mais produit inconnu: ${purchase.productID}');
      return;
    }
    await _progress.addCauris(pack.cauris);
    _log.i('+${pack.cauris} cauris crédités via IAP ${pack.productId}');
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
class CaurisOffersNotifier extends StateNotifier<List<CaurisPackOffer>> {
  CaurisOffersNotifier(this._service) : super(_service.offers());

  final IAPService _service;

  Future<void> refresh() async {
    state = _service.offers();
  }

  Future<bool> buy(CaurisPack pack) => _service.buy(pack);

  Future<bool> buyNoAds() => _service.buyNoAds();

  String get noAdsPriceLabel =>
      _service.noAdsDetails?.price ?? noAdsFallbackPrice;

  bool get noAdsAvailable => _service.noAdsDetails != null;

  Future<void> restore() => _service.restore();
}

final caurisOffersProvider =
    StateNotifierProvider<CaurisOffersNotifier, List<CaurisPackOffer>>((ref) {
  return CaurisOffersNotifier(ref.watch(iapServiceProvider));
});
