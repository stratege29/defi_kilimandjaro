import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/iap/coin_pack.dart';
import 'package:defi_kilimandjaro/data/iap/iap_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Boutique de Coins de Sagesse — packs IAP.
///
/// Cf. plan.md §1 et §4. Si le catalogue store est vide (produits pas
/// encore créés en App Store Connect / Play Console), affiche les packs
/// avec leurs prix fallback en mode "indisponible".
class ShopView extends ConsumerWidget {
  const ShopView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(coinOffersProvider);
    final progress = ref.watch(playerProgressProvider);

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.orSoleil,
          onPressed: () => context.pop(),
        ),
        title: Text('BOUTIQUE', style: AppTypography.bebas(size: 18)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _CoinsHeaderChip(coins: progress.coins),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const _PromoBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final o in offers)
                    _PackCard(
                      offer: o,
                      onBuy: () => _handleBuy(context, ref, o),
                    ),
                  const SizedBox(height: 14),
                  _NoAdsCard(
                    purchased: progress.noAdsPurchased,
                    onBuy: () => _handleBuyNoAds(context, ref),
                  ),
                ],
              ),
            ),
            _RestoreButton(onTap: () async {
              await ref.read(coinOffersProvider.notifier).restore();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Achats restaurés',
                    style: AppTypography.bebas(),
                  ),
                  backgroundColor: AppColors.boisFonce,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBuyNoAds(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(coinOffersProvider.notifier);
    if (!notifier.noAdsAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bientôt disponible',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
        ),
      );
      return;
    }
    final ok = await notifier.buyNoAds();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Achat non lancé',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }

  Future<void> _handleBuy(
    BuildContext context,
    WidgetRef ref,
    CoinPackOffer offer,
  ) async {
    if (!offer.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Boutique en cours de configuration. Reviens bientôt !',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
        ),
      );
      return;
    }
    final ok = await ref.read(coinOffersProvider.notifier).buy(offer.pack);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Achat non lancé — réessaie',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Header chip (current coins)
// ---------------------------------------------------------------------------

class _CoinsHeaderChip extends StatelessWidget {
  const _CoinsHeaderChip({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$coins',
            style: AppTypography.bebas(
              size: 14,
              color: AppColors.orSoleil,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.orSoleil.withValues(alpha: 0.18),
            AppColors.orChaud.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COINS DE SAGESSE',
            style: AppTypography.bebas(
              size: 18,
              color: AppColors.orSoleil,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Achète des coins pour révéler des indices et progresser '
            'plus vite vers le sommet du Kilimandjaro.',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.ivoire.withValues(alpha: 0.85),
              style: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pack card
// ---------------------------------------------------------------------------

class _PackCard extends StatelessWidget {
  const _PackCard({required this.offer, required this.onBuy});

  final CoinPackOffer offer;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final pack = offer.pack;
    final highlight = pack.isBestValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.vertClair.withValues(alpha: 0.18)
            : AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? AppColors.vertClair.withValues(alpha: 0.7)
              : AppColors.orSoleil.withValues(alpha: 0.4),
          width: highlight ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: offer.available ? onBuy : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _IconBadge(coins: pack.coins),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${pack.coins} Coins',
                            style: AppTypography.bebas(size: 18),
                          ),
                          if (highlight) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.vertClair,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'POPULAIRE',
                                style: AppTypography.bebas(
                                  size: 10,
                                  color: AppColors.vertForet,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.available
                            ? 'Achat unique en jeu'
                            : 'Bientôt disponible',
                        style: AppTypography.crimson(
                          size: 12,
                          color: AppColors.ivoire.withValues(alpha: 0.7),
                          style: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: offer.available
                        ? AppColors.vertClair
                        : AppColors.bois.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    offer.priceLabel,
                    style: AppTypography.bebas(
                      color: offer.available
                          ? AppColors.vertForet
                          : AppColors.ivoire.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    final size = coins >= 1499
        ? 64.0
        : coins >= 499
            ? 56.0
            : 48.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.orSoleil.withValues(alpha: 0.25),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.7),
                width: 2,
              ),
            ),
          ),
          const Text('🪙', style: TextStyle(fontSize: 28)),
        ],
      ),
    );
  }
}

class _NoAdsCard extends ConsumerWidget {
  const _NoAdsCard({required this.purchased, required this.onBuy});
  final bool purchased;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(coinOffersProvider.notifier);
    final price = notifier.noAdsPriceLabel;
    final available = notifier.noAdsAvailable;

    return Container(
      decoration: BoxDecoration(
        color: purchased
            ? AppColors.vertClair.withValues(alpha: 0.18)
            : AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: purchased
              ? AppColors.vertClair.withValues(alpha: 0.7)
              : AppColors.orSoleil.withValues(alpha: 0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: purchased ? null : onBuy,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orSoleil.withValues(alpha: 0.25),
                    border: Border.all(
                      color: AppColors.orSoleil.withValues(alpha: 0.7),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Text('🚫', style: TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Supprimer les pubs',
                        style: AppTypography.bebas(size: 17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        purchased
                            ? '✓ Déjà acheté — merci !'
                            : "Plus jamais d'interstitielles. Achat unique.",
                        style: AppTypography.crimson(
                          size: 12,
                          color: AppColors.ivoire.withValues(alpha: 0.7),
                          style: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!purchased)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: available
                          ? AppColors.orSoleil
                          : AppColors.bois.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      price,
                      style: AppTypography.bebas(
                        color: available
                            ? AppColors.vertForet
                            : AppColors.ivoire.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextButton(
        onPressed: onTap,
        child: Text(
          'Restaurer mes achats',
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.ivoire.withValues(alpha: 0.6),
            style: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
