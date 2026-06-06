import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/services/pack_display.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Chip « pack actif » — omniprésent dans la boucle de jeu (header carte des
/// sommets + accueil). Affiche l'emoji + le nom du pack actif et ouvre
/// « Mes packs » au tap (changer de pack / découvrir / acheter).
///
/// Rend un [SizedBox.shrink] tant qu'aucun pack actif n'est résolu (onboarding
/// pas encore tranché) ou que le catalogue n'est pas chargé.
class ActivePackChip extends ConsumerWidget {
  const ActivePackChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activePackIdProvider);
    if (activeId == null || activeId.isEmpty) return const SizedBox.shrink();

    final name = ref.watch(packCatalogProvider).maybeWhen(
          data: (catalog) {
            for (final p in catalog) {
              if (p.id == activeId) return p.nameKey.tr();
            }
            return null;
          },
          orElse: () => null,
        );
    if (name == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: 'my_packs.title'.tr(),
      child: Material(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => context.push(AppRoutes.myPacks),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.orJour.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(packEmoji(activeId), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.orJour,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.unfold_more,
                  size: 14,
                  color: AppColors.orJour,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
