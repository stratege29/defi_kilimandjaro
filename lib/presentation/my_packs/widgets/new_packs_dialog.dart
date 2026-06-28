import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/presentation/packs/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/pack_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Action choisie par l'utilisateur sur la modale « nouveau pack ».
enum NewPacksDialogAction {
  /// Aller voir les packs (→ écran Mes packs).
  discover,

  /// Reporter — relance après un délai, sans marquer comme vu.
  later,
}

/// Modale d'annonce d'un (ou plusieurs) nouveau(x) pack(s) disponible(s).
///
/// Affichée par `HomeView` au boot quand `newPacksProvider` retourne des packs.
/// Volontairement purement présentationnelle : elle retourne l'action choisie
/// via `Navigator.pop`, et l'appelant se charge de la persistance (marquer vu /
/// snooze) et de la navigation. Style aligné sur `DailyStreakDialog`.
class NewPacksDialog extends StatelessWidget {
  const NewPacksDialog({required this.packs, super.key});

  final List<Pack> packs;

  /// Ouvre la modale et retourne l'action choisie (null si fermée au tap-out,
  /// traité comme [NewPacksDialogAction.later]).
  static Future<NewPacksDialogAction?> show(
    BuildContext context, {
    required List<Pack> packs,
  }) {
    return showDialog<NewPacksDialogAction>(
      context: context,
      builder: (_) => NewPacksDialog(packs: packs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = packs.length == 1;
    final pack = packs.first;

    final title = isSingle
        ? pack.displayName
        : 'pack_notifications.new_title_multi'
            .tr(namedArgs: {'count': '${packs.length}'});
    final body = isSingle
        ? pack.displayDescription
        : 'pack_notifications.new_body_multi'.tr();

    return Dialog(
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.orJour.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isSingle)
              PackIcon(pack: pack)
            else
              const Icon(
                Icons.auto_awesome_rounded,
                size: 40,
                color: AppColors.orJour,
              ),
            const SizedBox(height: 12),
            // Eyebrow doré all-caps espacé (maquette `.eyebrow2`).
            Text(
              'pack_notifications.new_eyebrow'.tr(),
              style: AppTypography.labelXs.copyWith(
                color: AppColors.orJour,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headingLg,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                fontSize: 13,
                color: AppColors.texteSecondaire,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'pack_notifications.discover'.tr(),
              fullWidth: true,
              onPressed: () =>
                  Navigator.of(context).pop(NewPacksDialogAction.discover),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'pack_notifications.later'.tr(),
              variant: AppButtonVariant.soft,
              fullWidth: true,
              onPressed: () =>
                  Navigator.of(context).pop(NewPacksDialogAction.later),
            ),
          ],
        ),
      ),
    );
  }
}
