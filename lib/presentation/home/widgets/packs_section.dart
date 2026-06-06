import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/section_title.dart';
import 'package:defi_kilimandjaro/presentation/packs/widgets/active_pack_chip.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Section TES PACKS de l'accueil — carrousel horizontal des packs possédés
/// (pack actif mis en avant), une carte « Découvrir » pour débloquer de
/// nouveaux packs, et un lien « Gérer » vers l'écran de pondération complet.
///
/// Surfaces opaques `surfaceContainer`, bordures hairline, accent or réservé
/// au pack actif — cohérent avec les tuiles d'accès Vert Nuit.
class PacksSection extends ConsumerWidget {
  const PacksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedIds = ref.watch(ownedPacksProvider);
    final catalogAsync = ref.watch(packCatalogProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          label: 'TES PACKS',
          trailing: ActivePackChip(),
        ),
        SizedBox(
          height: 120,
          child: catalogAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (catalog) {
              final ownedPacks =
                  catalog.where((p) => ownedIds.contains(p.id)).toList();
              if (ownedPacks.isEmpty) {
                return _EmptyOwned(
                  onTap: () => context.push(AppRoutes.myPacks),
                );
              }
              final cards = <Widget>[
                for (final pack in ownedPacks) _OwnedPackCard(pack: pack),
                _DiscoverCard(
                  onTap: () => context.push(AppRoutes.myPacks),
                ),
              ];
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => cards[i],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Carte d'un pack possédé : nom · nb de devinettes · badge ACTIF.
/// Tap = active le pack (s'il ne l'est pas) puis va aux Sommets.
class _OwnedPackCard extends ConsumerWidget {
  const _OwnedPackCard({required this.pack});

  final Pack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activePackIdProvider);
    final isActive = activeId == pack.id;

    return SizedBox(
      width: 188,
      child: Material(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _resume(context, ref),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? AppColors.orJour : AppColors.hairline,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pack.nameKey.tr(),
                        style: AppTypography.headingSm
                            .copyWith(color: AppColors.textePrimaire),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive)
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppColors.success,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${pack.questionCount} devinettes',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.texteTertiaire),
                ),
                const Spacer(),
                Text(
                  isActive ? 'PACK ACTIF · GRIMPER' : 'ACTIVER',
                  style: AppTypography.bebas(
                    size: 12,
                    color: isActive ? AppColors.orJour : AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(playerProgressProvider.notifier);
    if (ref.read(activePackIdProvider) != pack.id) {
      await notifier.setActivePack(pack.id);
    }
    if (!context.mounted) return;
    context.go(AppRoutes.mountains);
  }
}

/// Carte d'appel à l'action « Découvrir » → catalogue de packs à débloquer.
class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Material(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.orJour.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: AppColors.orJour,
                  ),
                ),
                const Spacer(),
                Text(
                  'Découvrir',
                  style: AppTypography.headingSm
                      .copyWith(color: AppColors.textePrimaire),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nouveaux packs',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.texteTertiaire),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// État vide (aucun pack possédé) — CTA pleine largeur vers le catalogue.
class _EmptyOwned extends StatelessWidget {
  const _EmptyOwned({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.orJour.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.library_add,
                  color: AppColors.orJour,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Choisis ton premier pack',
                      style: AppTypography.headingSm
                          .copyWith(color: AppColors.textePrimaire),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Une famille de devinettes à explorer.',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.texteTertiaire),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.texteSecondaire,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
