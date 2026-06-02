import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/data/iap/cauris_pack.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
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
      starterPackProductId,
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

  /// Lance l'achat one-time du **Starter Pack** (2,99 € — 350 cauris).
  Future<bool> buyStarterPack() async {
    final details = _details[starterPackProductId];
    if (details == null) return false;
    final purchaseParam = PurchaseParam(productDetails: details);
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Détails du No-Ads (null si pas dans le catalogue).
  ProductDetails? get noAdsDetails => _details[noAdsProductId];

  /// Détails du Starter Pack (null si pas dans le catalogue).
  ProductDetails? get starterPackDetails => _details[starterPackProductId];

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
    // Grant local immédiat pour la réactivité UX (cauris affichés sans
    // attendre l'aller-retour réseau). La validation serveur tourne en
    // parallèle pour idempotence + audit log — un échec réseau ne perd
    // donc PAS l'achat (le reçu reste sur le device et restore() le
    // ré-emettra, où l'idempotence serveur évitera le double-crédit).
    unawaited(_recordOnServer(purchase));

    if (purchase.productID == noAdsProductId) {
      await _progress.grantNoAds();
      _log.i('No-Ads accordé via IAP');
      return;
    }
    if (purchase.productID == starterPackProductId) {
      await _progress.grantStarterPack(caurisBonus: starterPackCauris);
      _log.i('Starter Pack accordé (+$starterPackCauris cauris)');
      return;
    }
    final pack = CaurisPack.fromProductId(purchase.productID);
    if (pack == null) {
      _log.w('Achat reconnu mais produit inconnu: ${purchase.productID}');
      return;
    }
    await _progress.addCauris(
      pack.cauris,
      source: CaurisCreditSource.iap,
      reference: pack.productId,
    );
    _log.i('+${pack.cauris} cauris crédités via IAP ${pack.productId}');
  }

  /// Fire-and-forget : appelle la Cloud Function `validateIapReceipt`
  /// pour enregistrer le reçu côté Firestore (idempotent + audit).
  /// N'affecte pas le grant local — un échec ne perd pas l'achat.
  Future<void> _recordOnServer(PurchaseDetails purchase) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      // purchaseID est l'orderId Android / transactionId iOS selon le SDK.
      final orderOrTransactionId =
          purchase.purchaseID ?? 'unknown_${DateTime.now().microsecondsSinceEpoch}';
      final rawReceipt =
          purchase.verificationData.serverVerificationData;
      final purchaseDate = int.tryParse(purchase.transactionDate ?? '');
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('validateIapReceipt')
          .call<Map<String, dynamic>>(<String, dynamic>{
        'platform': platform,
        'productId': purchase.productID,
        'orderOrTransactionId': orderOrTransactionId,
        'rawReceipt': rawReceipt,
        if (purchaseDate != null) 'purchaseDateMs': purchaseDate,
      });
      _log.i('IAP validateIapReceipt → enregistré ${purchase.productID}');
    } on Object catch (e) {
      _log.w('IAP server validation failed (best-effort): $e');
    }
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

  Future<bool> buyStarterPack() => _service.buyStarterPack();

  String get noAdsPriceLabel =>
      _service.noAdsDetails?.price ?? noAdsFallbackPrice;

  bool get noAdsAvailable => _service.noAdsDetails != null;

  String get starterPackPriceLabel =>
      _service.starterPackDetails?.price ?? starterPackFallbackPrice;

  bool get starterPackAvailable => _service.starterPackDetails != null;

  Future<void> restore() => _service.restore();
}

final caurisOffersProvider =
    StateNotifierProvider<CaurisOffersNotifier, List<CaurisPackOffer>>((ref) {
  return CaurisOffersNotifier(ref.watch(iapServiceProvider));
});
