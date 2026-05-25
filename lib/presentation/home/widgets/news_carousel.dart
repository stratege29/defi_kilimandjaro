import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/section_title.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Section ACTUALITÉS — agrège packs payants en promo + cards statiques
/// (events, release notes). Sources Remote Config à câbler en Phase 3+.
class NewsCarousel extends ConsumerWidget {
  const NewsCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedIds = ref.watch(ownedPacksProvider);
    final catalogAsync = ref.watch(packCatalogProvider);

    final items = <_NewsItem>[];

    // Cards promo : packs non possédés avec prix (cauris ou EUR).
    catalogAsync.whenData((catalog) {
      for (final pack in catalog) {
        if (ownedIds.contains(pack.id)) continue;
        if (pack.priceCauris <= 0 && pack.priceEur <= 0) continue;
        items.add(_PromoPackItem(pack));
      }
    });

    items
      ..add(_StaticItem(
        icon: Icons.brush,
        title: 'Crée ton propre pack',
        subtitle: 'Partage tes devinettes',
        color: AppColors.vertClair,
        onTap: (ctx) => ctx.push(AppRoutes.ugcSubmit),
      ))
      ..add(_StaticItem(
        icon: Icons.emoji_events,
        title: 'Top de la semaine',
        subtitle: 'Vois où tu te situes',
        color: AppColors.orChaud,
        onTap: (ctx) => ctx.push(AppRoutes.leaderboard),
      ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'ACTUALITÉS'),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => items[i].build(context),
          ),
        ),
      ],
    );
  }
}

sealed class _NewsItem {
  Widget build(BuildContext context);
}

class _PromoPackItem extends _NewsItem {
  _PromoPackItem(this.pack);

  final Pack pack;

  @override
  Widget build(BuildContext context) {
    final priceLabel = pack.priceCauris > 0
        ? '${pack.priceCauris} cauris'
        : '${pack.priceEur.toStringAsFixed(2)} €';

    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(AppRoutes.shop),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.orSoleil.withValues(alpha: 0.22),
                  AppColors.bois.withValues(alpha: 0.22),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orSoleil,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'NOUVEAU PACK',
                    style: AppTypography.bebas(
                      size: 10,
                      color: AppColors.vertForet,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  pack.nameKey.tr(),
                  style: AppTypography.bebas(color: AppColors.orSoleil),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${pack.questionCount} devinettes · $priceLabel',
                  style: AppTypography.crimson(
                    size: 11,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'DÉVERROUILLER →',
                  style: AppTypography.bebas(
                    size: 12,
                    color: AppColors.vertClair,
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

class _StaticItem extends _NewsItem {
  _StaticItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final void Function(BuildContext) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
                Text(
                  title,
                  style: AppTypography.bebas(size: 15, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.crimson(
                    size: 11,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
