import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Résout le [PackTheme] d'un pack donné en croisant le catalogue (pour
/// récupérer `themeId` / `themeOverrides` remote) avec le registre de presets.
///
/// Le catalogue étant async, on résout d'abord par **convention d'id de pack**
/// (skin disponible immédiatement, offline-first) puis on raffine avec les
/// champs remote dès qu'ils sont chargés.
PackTheme _resolveForPack(String? packId, AsyncValue<List<Pack>> catalog) {
  if (packId == null) return PackThemes.defaultTheme;
  final pack = catalog.maybeWhen(
    data: (packs) {
      for (final p in packs) {
        if (p.id == packId) return p;
      }
      return null;
    },
    orElse: () => null,
  );
  return PackThemes.resolve(
    packId: packId,
    themeId: pack?.themeId,
    overrides: pack?.themeOverrides,
    motifName: pack?.themeMotif,
    tileShapeName: pack?.themeTileShape,
  );
}

/// Skin du pack actuellement actif (gameplay solo, header, Sommets).
///
/// Retombe sur [PackThemes.defaultTheme] si aucun pack actif — look « Vert
/// Nuit » historique, zéro régression.
final activePackThemeProvider = Provider<PackTheme>((ref) {
  final packId = ref.watch(activePackIdProvider);
  final catalog = ref.watch(packCatalogProvider);
  return _resolveForPack(packId, catalog);
});

/// Skin d'un pack précis (prévisualisation, carte de pack, Sommets d'un pack
/// non actif). Family paramétrée par l'id de pack.
final packThemeForProvider = Provider.family<PackTheme, String>((ref, packId) {
  final catalog = ref.watch(packCatalogProvider);
  return _resolveForPack(packId, catalog);
});
