import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Bandeau non-bloquant affiché en tête de « Mes packs » quand des mises à
/// jour de contenu sont disponibles pour les packs possédés.
///
/// Le téléchargement reste déclenché par l'utilisateur ([onUpdate]) — le
/// bandeau ne lance jamais de sync de lui-même (mitigation OOM : aucun
/// download non sollicité).
class PackUpdatesBanner extends StatelessWidget {
  const PackUpdatesBanner({
    required this.count,
    required this.onUpdate,
    super.key,
  });

  /// Nombre de packs possédés avec une mise à jour disponible (> 0).
  final int count;

  /// Déclenche la synchronisation (même chemin que le bouton de l'AppBar).
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.orJour.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orJour.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_alt_rounded,
            color: AppColors.orJour,
            size: 22,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'pack_notifications.updates_title'
                      .tr(namedArgs: {'count': '$count'}),
                  style: AppTypography.headingSm,
                ),
                Text(
                  'pack_notifications.updates_subtitle'.tr(),
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.texteSecondaire),
                ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onUpdate,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.orJour,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'pack_notifications.update_cta'.tr(),
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.boisFonce,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
