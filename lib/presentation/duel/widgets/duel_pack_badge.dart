import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/domain/services/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/packs/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/widgets/pack_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pastille de catégorie (pack) d'une manche de duel : icône + nom
/// (ex. « Crack Nouchi », « Football »). Affichée sous la pastille de manche
/// dans l'intro / le countdown — donne le thème aux deux joueurs sans encombrer
/// l'écran de jeu.
///
/// Dérivée du `devinette_id` (`<packId>_NNN`) via [packIdFromDevinetteId] +
/// `packCatalogProvider` — aucun appel backend. Affiche `SizedBox.shrink` si la
/// provenance est inconnue (samples de fallback `sample_*`) ou si le catalogue
/// n'est pas chargé : dégradation propre.
class DuelPackBadge extends ConsumerWidget {
  const DuelPackBadge({required this.devinetteId, super.key});

  final String? devinetteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = devinetteId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    final packId = packIdFromDevinetteId(id);
    if (packId == null) return const SizedBox.shrink();

    final pack = ref.watch(packCatalogProvider).maybeWhen(
          data: (catalog) {
            for (final p in catalog) {
              if (p.id == packId) return p;
            }
            return null;
          },
          orElse: () => null,
        );
    if (pack == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 18, 5),
      decoration: BoxDecoration(
        // Fond OPAQUE : sinon la barre diagonale du décor VERSUS transparaît
        // à travers la pastille et semble passer au-dessus.
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.orJour.withValues(alpha: 0.75),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.orJour.withValues(alpha: 0.28),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PackIcon(pack: pack, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              pack.displayName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSm.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: AppColors.orJour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
