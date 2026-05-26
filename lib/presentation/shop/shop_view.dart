import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/rewarded_daily_cap_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/iap/cauris_pack.dart';
import 'package:defi_kilimandjaro/data/iap/iap_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Boutique de Cauris de Sagesse — packs IAP.
///
/// Cf. plan.md §1 et §4. Si le catalogue store est vide (produits pas
/// encore créés en App Store Connect / Play Console), affiche les packs
/// avec leurs prix fallback en mode "indisponible".
class ShopView extends ConsumerWidget {
  const ShopView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(caurisOffersProvider);
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
            child: _CaurisHeaderChip(cauris: progress.cauris),
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
                  // Starter Pack — visible H+0 → H+48 après install, une
                  // seule fois. Couronne le top des cartes pour maximiser
                  // l'engagement à chaud.
                  if (_isStarterEligible(progress))
                    _StarterPackCard(
                      cauris: starterPackCauris,
                      priceLabel: ref
                          .watch(caurisOffersProvider.notifier)
                          .starterPackPriceLabel,
                      available: ref
                          .watch(caurisOffersProvider.notifier)
                          .starterPackAvailable,
                      remaining: _starterRemaining(progress.installDate!),
                      onBuy: () => _handleBuyStarter(context, ref),
                    ),
                  // Carte rewarded au-dessus des packs payants : exposer
                  // l'option gratuite **avant** le paywall augmente la
                  // confiance et la conversion IAP au passage des joueurs
                  // qui hésitent. Visible uniquement si offre encore
                  // possible (cap quotidien, killswitch, No-Ads).
                  if (!progress.noAdsPurchased &&
                      ref.watch(canOfferRewardedProvider))
                    _RewardedFreeCard(
                      amount: ref.watch(
                        gameEconomyConfigProvider.select(
                          (c) => c.rewardedVideoBonus,
                        ),
                      ),
                      onWatch: () => _handleWatchRewarded(context, ref),
                    ),
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
            _RestoreButton(
              onTap: () async {
                await ref.read(caurisOffersProvider.notifier).restore();
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
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Fenêtre d'éligibilité Starter Pack : pas encore acheté, installé
  /// il y a moins de 48 h, et date d'installation connue (`null` pour
  /// les profils créés avant le déploiement Phase 4 — pas de starter).
  static bool _isStarterEligible(PlayerProgress p) {
    if (p.starterPackPurchased) return false;
    final installed = p.installDate;
    if (installed == null) return false;
    return DateTime.now().difference(installed) < const Duration(hours: 48);
  }

  /// Temps restant avant expiration du Starter Pack (chronométré côté UI).
  static Duration _starterRemaining(DateTime installDate) {
    const window = Duration(hours: 48);
    final elapsed = DateTime.now().difference(installDate);
    final remaining = window - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _handleBuyStarter(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(caurisOffersProvider.notifier);
    if (!notifier.starterPackAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bientôt disponible', style: AppTypography.bebas()),
          backgroundColor: AppColors.boisFonce,
        ),
      );
      return;
    }
    final ok = await notifier.buyStarterPack();
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

  Future<void> _handleWatchRewarded(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final amount = ref.read(gameEconomyConfigProvider).rewardedVideoBonus;
    final got = await ref.read(adsServiceProvider).showRewardedForCauris();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          got
              ? '+$amount Cauris de Sagesse — merci !'
              : 'Pub non disponible — réessaie plus tard',
          style: AppTypography.bebas(),
        ),
        backgroundColor: got ? AppColors.vertClair : AppColors.boisFonce,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  Future<void> _handleBuyNoAds(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(caurisOffersProvider.notifier);
    if (!notifier.noAdsAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bientôt disponible', style: AppTypography.bebas()),
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
          content: Text('Achat non lancé', style: AppTypography.bebas()),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }

  Future<void> _handleBuy(
    BuildContext context,
    WidgetRef ref,
    CaurisPackOffer offer,
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
    final ok = await ref.read(caurisOffersProvider.notifier).buy(offer.pack);
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
// Header chip (current cauris)
// ---------------------------------------------------------------------------

class _CaurisHeaderChip extends StatelessWidget {
  const _CaurisHeaderChip({required this.cauris});
  final int cauris;

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
          const CaurisIcon(size: 16),
          const SizedBox(width: 4),
          Text(
            '$cauris',
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
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
      child: Row(
        children: [
          // Hero illustration : planche calebasses + coffres + trône.
          Image.asset(AppAssets.shopPackSheet, width: 110, height: 110),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CAURIS DE SAGESSE',
                  style: AppTypography.bebas(
                    size: 18,
                    color: AppColors.orSoleil,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Achète des cauris pour révéler des indices et progresser '
                  'plus vite vers le sommet du Kilimandjaro.',
                  style: AppTypography.crimson(
                    size: 13,
                    color: AppColors.textePrimaire,
                    style: FontStyle.italic,
                  ),
                ),
              ],
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

  final CaurisPackOffer offer;
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
                _IconBadge(cauris: pack.cauris),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${pack.cauris} Cauris',
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
                          color: AppColors.texteSecondaire,
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
                          : AppColors.texteTertiaire,
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
  const _IconBadge({required this.cauris});
  final int cauris;

  /// Sélection du visuel selon la taille du pack — palette progressive
  /// petite calebasse → grande calebasse → coffre → coffre cérémoniel → trône.
  String _assetForCauris(int c) {
    if (c >= 4000) return AppAssets.shopCaurisMega;
    if (c >= 1000) return AppAssets.shopCaurisXL;
    if (c >= 400) return AppAssets.shopCaurisL;
    if (c >= 150) return AppAssets.shopCaurisM;
    return AppAssets.shopCaurisS;
  }

  @override
  Widget build(BuildContext context) {
    final size = cauris >= 1499
        ? 78.0
        : cauris >= 499
        ? 68.0
        : 58.0;
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(_assetForCauris(cauris), fit: BoxFit.contain),
    );
  }
}

class _NoAdsCard extends ConsumerWidget {
  const _NoAdsCard({required this.purchased, required this.onBuy});
  final bool purchased;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(caurisOffersProvider.notifier);
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
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.asset(AppAssets.shopNoAds, fit: BoxFit.contain),
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
                          color: AppColors.texteSecondaire,
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
                            : AppColors.texteTertiaire,
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

/// Starter Pack — carte premium one-time visible 48h après install.
///
/// Pourquoi ce placement & ce design :
/// - Position #1 dans la liste (avant la carte rewarded + packs payants).
/// - Compte à rebours visible "expire dans 47h 32min" : crée de l'urgence
///   sans agressivité (la fenêtre est large).
/// - Badge "OFFRE DE BIENVENUE" pour signifier que c'est exceptionnel.
///
/// Benchmark : conversion D1 +35-40% sur le segment word puzzle.
class _StarterPackCard extends StatelessWidget {
  const _StarterPackCard({
    required this.cauris,
    required this.priceLabel,
    required this.available,
    required this.remaining,
    required this.onBuy,
  });

  final int cauris;
  final String priceLabel;
  final bool available;
  final Duration remaining;
  final VoidCallback onBuy;

  String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    return '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.orJour.withValues(alpha: 0.30),
            AppColors.orChaud.withValues(alpha: 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orJour, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.orJour.withValues(alpha: 0.25),
            blurRadius: 24,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: available ? onBuy : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.orJour,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'OFFRE DE BIENVENUE',
                        style: AppTypography.bebas(
                          size: 11,
                          color: AppColors.vertForet,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: AppColors.orJour.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'expire dans ${_formatRemaining(remaining)}',
                      style: AppTypography.bebas(
                        size: 12,
                        color: AppColors.orJour.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Image.asset(
                        AppAssets.shopCaurisL,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                '$cauris Cauris',
                                style: AppTypography.bebas(size: 22),
                              ),
                              const SizedBox(width: 6),
                              const CaurisIcon(size: 16),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Boost de démarrage — achat unique',
                            style: AppTypography.crimson(
                              size: 12,
                              color: AppColors.texteSecondaire,
                              style: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: available
                            ? AppColors.orJour
                            : AppColors.bois.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        priceLabel,
                        style: AppTypography.bebas(
                          color: available
                              ? AppColors.vertForet
                              : AppColors.texteTertiaire,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte rewarded gratuite placée en tête de la boutique.
///
/// Pourquoi en haut : exposer l'option non-payante **avant** les packs
/// augmente la confiance et lève l'objection "vous voulez juste mon
/// argent". La conversion IAP au passage des joueurs free-to-play
/// s'améliore (benchmark Wordscapes, Word Connect!).
class _RewardedFreeCard extends StatelessWidget {
  const _RewardedFreeCard({required this.amount, required this.onWatch});

  final int amount;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.orJour.withValues(alpha: 0.18),
            AppColors.orChaud.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orJour.withValues(alpha: 0.55)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onWatch,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.orJour.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.play_circle_filled_rounded,
                    size: 34,
                    color: AppColors.orJour,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            '+$amount Cauris',
                            style: AppTypography.bebas(size: 18),
                          ),
                          const SizedBox(width: 6),
                          const CaurisIcon(size: 14),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Gratuit — regarde une courte vidéo',
                        style: AppTypography.crimson(
                          size: 12,
                          color: AppColors.texteSecondaire,
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
                    color: AppColors.orJour,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'GRATUIT',
                    style: AppTypography.bebas(color: AppColors.vertForet),
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
            color: AppColors.texteSecondaire,
            style: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
