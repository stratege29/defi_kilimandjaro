import 'package:equatable/equatable.dart';

/// Catalogue des packs de Coins de Sagesse vendus en IAP.
///
/// Les `productId` doivent être identiques entre App Store Connect et
/// Play Console. Convention `coins_pack_<amount>`.
enum CoinPack {
  small(productId: 'coins_pack_49', coins: 49, fallbackPriceLabel: '0,99 €'),
  medium(productId: 'coins_pack_199', coins: 199, fallbackPriceLabel: '2,99 €'),
  large(
    productId: 'coins_pack_499',
    coins: 499,
    fallbackPriceLabel: '4,99 €',
    isBestValue: true,
  ),
  huge(productId: 'coins_pack_1499', coins: 1499, fallbackPriceLabel: '9,99 €'),
  mega(productId: 'coins_pack_4999', coins: 4999, fallbackPriceLabel: '24,99 €');

  const CoinPack({
    required this.productId,
    required this.coins,
    required this.fallbackPriceLabel,
    this.isBestValue = false,
  });

  final String productId;
  final int coins;

  /// Prix affiché si on n'a pas pu charger le catalogue store
  /// (ex: products pas encore créés en App Store Connect).
  final String fallbackPriceLabel;

  /// Mis en avant comme meilleur rapport qualité/prix.
  final bool isBestValue;

  static CoinPack? fromProductId(String id) {
    for (final p in CoinPack.values) {
      if (p.productId == id) return p;
    }
    return null;
  }

  /// Tous les product IDs (à enregistrer dans le store).
  static List<String> allProductIds() =>
      CoinPack.values.map((e) => e.productId).toList();
}

/// Snapshot d'un pack avec son prix résolu depuis le store.
class CoinPackOffer extends Equatable {
  const CoinPackOffer({
    required this.pack,
    required this.priceLabel,
    this.available = true,
  });

  /// Construction avec prix fallback (utilisé en mode dev sans store).
  factory CoinPackOffer.fallback(CoinPack pack) => CoinPackOffer(
        pack: pack,
        priceLabel: pack.fallbackPriceLabel,
        available: false,
      );

  final CoinPack pack;
  final String priceLabel;
  final bool available;

  @override
  List<Object?> get props => [pack, priceLabel, available];
}
