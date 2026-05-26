import 'package:equatable/equatable.dart';

/// Catalogue des packs de Cauris de Sagesse vendus en IAP.
///
/// Les `productId` sont conservés en `coins_pack_*` car ils correspondent
/// aux SKUs déjà déclarés (ou à déclarer) sur App Store Connect / Play
/// Console — un rename casserait les achats existants.
enum CaurisPack {
  small(productId: 'coins_pack_49', cauris: 49, fallbackPriceLabel: '0,99 €'),
  medium(
    productId: 'coins_pack_199',
    cauris: 199,
    fallbackPriceLabel: '2,99 €',
  ),
  large(
    productId: 'coins_pack_499',
    cauris: 499,
    fallbackPriceLabel: '4,99 €',
    isBestValue: true,
  ),
  huge(
    productId: 'coins_pack_1499',
    cauris: 1499,
    fallbackPriceLabel: '9,99 €',
  ),
  mega(
    productId: 'coins_pack_4999',
    cauris: 4999,
    fallbackPriceLabel: '24,99 €',
  );

  const CaurisPack({
    required this.productId,
    required this.cauris,
    required this.fallbackPriceLabel,
    this.isBestValue = false,
  });

  final String productId;
  final int cauris;

  /// Prix affiché si on n'a pas pu charger le catalogue store
  /// (ex: products pas encore créés en App Store Connect).
  final String fallbackPriceLabel;

  /// Mis en avant comme meilleur rapport qualité/prix.
  final bool isBestValue;

  static CaurisPack? fromProductId(String id) {
    for (final p in CaurisPack.values) {
      if (p.productId == id) return p;
    }
    return null;
  }

  /// Tous les product IDs (à enregistrer dans le store).
  static List<String> allProductIds() =>
      CaurisPack.values.map((e) => e.productId).toList();
}

/// Product ID du non-consumable "Supprimer les pubs" (4,99 €).
const String noAdsProductId = 'no_ads_remove';
const String noAdsFallbackPrice = '4,99 €';

/// Product ID du **Starter Pack** non-consumable (2,99 € — 350 cauris
/// bonus, achat unique, visible 48h après install seulement).
const String starterPackProductId = 'starter_pack_299';
const String starterPackFallbackPrice = '2,99 €';

/// Récompense créditée à l'achat du Starter Pack.
const int starterPackCauris = 350;

/// Snapshot d'un pack avec son prix résolu depuis le store.
class CaurisPackOffer extends Equatable {
  const CaurisPackOffer({
    required this.pack,
    required this.priceLabel,
    this.available = true,
  });

  /// Construction avec prix fallback (utilisé en mode dev sans store).
  factory CaurisPackOffer.fallback(CaurisPack pack) => CaurisPackOffer(
        pack: pack,
        priceLabel: pack.fallbackPriceLabel,
        available: false,
      );

  final CaurisPack pack;
  final String priceLabel;
  final bool available;

  @override
  List<Object?> get props => [pack, priceLabel, available];
}
