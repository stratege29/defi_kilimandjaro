import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/section_title.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Section TES PACKS : carrousel horizontal des packs possédés + bouton
/// SYNC (placebo pour le MVP — vraie synchro Phase 3+, cf. tâche #14).
class PacksSection extends ConsumerStatefulWidget {
  const PacksSection({super.key});

  @override
  ConsumerState<PacksSection> createState() => _PacksSectionState();
}

class _PacksSectionState extends ConsumerState<PacksSection> {
  bool _syncing = false;

  Future<void> _onSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    // Placebo : laisse le temps au spinner d'apparaître, puis snackbar.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tes packs sont à jour',
          style: AppTypography.bebas(),
        ),
        backgroundColor: AppColors.boisFonce,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownedIds = ref.watch(ownedPacksProvider);
    final catalogAsync = ref.watch(packCatalogProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          label: 'TES PACKS',
          trailing: _SyncButton(syncing: _syncing, onTap: _onSync),
        ),
        SizedBox(
          height: 100,
          child: catalogAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (catalog) {
              final ownedPacks =
                  catalog.where((p) => ownedIds.contains(p.id)).toList();
              if (ownedPacks.isEmpty) {
                return _EmptyOwned(
                  onTap: () => context.push(AppRoutes.packChooser),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: ownedPacks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _OwnedPackCard(pack: ownedPacks[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.syncing, required this.onTap});

  final bool syncing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: syncing ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.bois.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.orSoleil,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.refresh,
                  size: 14,
                  color: AppColors.orSoleil,
                ),
              const SizedBox(width: 4),
              Text(
                'SYNC',
                style:
                    AppTypography.bebas(size: 12, color: AppColors.orSoleil),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnedPackCard extends ConsumerWidget {
  const _OwnedPackCard({required this.pack});

  final Pack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMix = ref.watch(packMixProvider);
    final isActive = activeMix.packIds.contains(pack.id);

    return SizedBox(
      width: 190,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _resume(context, ref),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bois.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? AppColors.orSoleil.withValues(alpha: 0.85)
                    : AppColors.orSoleil.withValues(alpha: 0.3),
                width: isActive ? 2 : 1,
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
                        style: AppTypography.bebas(
                          size: 14,
                          color: AppColors.orSoleil,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive)
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.vertClair,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${pack.questionCount} devinettes',
                  style: AppTypography.crimson(
                    size: 11,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                Text(
                  isActive ? 'PACK ACTIF · GRIMPER' : 'REPRENDRE',
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

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(playerProgressProvider.notifier);
    final activeMix = ref.read(packMixProvider);
    if (!activeMix.packIds.contains(pack.id)) {
      await notifier.setPackMix(PackMix.single(pack.id));
    }
    if (!context.mounted) return;
    context.go(AppRoutes.mountains);
  }
}

class _EmptyOwned extends StatelessWidget {
  const _EmptyOwned({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bois.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.library_add,
                color: AppColors.orSoleil,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHOISIS TON PREMIER PACK',
                      style: AppTypography.bebas(
                        size: 14,
                        color: AppColors.orSoleil,
                      ),
                    ),
                    Text(
                      'Une famille de devinettes culturelles à explorer.',
                      style: AppTypography.crimson(
                        size: 11,
                        color: AppColors.texteSecondaire,
                        style: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
