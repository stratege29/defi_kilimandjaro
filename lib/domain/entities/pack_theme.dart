import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Motif culturel peint en fond du gameplay / des cartes Sommets.
///
/// **Phase A** : le champ est porté par [PackTheme] mais n'est pas encore
/// rendu (le rendu CustomPainter arrive en Phase B). [PackMotif.none] = aucun
/// motif (look « Vert Nuit » historique).
enum PackMotif { none, adinkra, kita, bogolan, kente, vagues }

/// Forme des tuiles-lettres de la grille circulaire.
///
/// **Phase A** : seul [TileShape.sculpted] (le look actuel) est rendu. Les
/// autres formes sont câblées en Phase B.
enum TileShape { sculpted, rounded, hex, diamond }

/// Skin visuel d'un pack — couleurs, motif et forme des éléments de jeu.
///
/// Un `PackTheme` est un **preset bundlé** identifié par [id]. Chaque pack
/// pointe vers un preset (via son `themeId`, sinon par convention de nom
/// d'id de pack), et ses **couleurs** peuvent être surchargées à distance
/// (`theme_overrides` Firestore) via [PackTheme.copyWithOverrides].
///
/// Le thème [PackThemes.defaultTheme] reproduit **à l'identique** la palette
/// « Vert Nuit » actuelle : un pack sans skin reste visuellement inchangé
/// (zéro régression).
///
/// Règle iOS 26 : tout rendu dérivé d'un thème doit rester GPU-safe — pas de
/// `MaskFilter.blur` (cf. crash boot OOM).
class PackTheme extends Equatable {
  const PackTheme({
    required this.id,
    required this.background,
    required this.backgroundEnd,
    required this.tile,
    required this.tileEdge,
    required this.tileSelected,
    required this.tileSelectedEdge,
    required this.tileText,
    required this.accent,
    required this.onAccent,
    required this.path,
    required this.validation,
    this.sommetsTint,
    this.motif = PackMotif.none,
    this.motifColor,
    this.tileShape = TileShape.sculpted,
  });

  /// Identifiant stable du preset (snake_case, ex. `vert_nuit`).
  final String id;

  /// Fond principal du scaffold gameplay (haut du dégradé).
  final Color background;

  /// Bas du dégradé de fond. Égal à [background] pour un fond plat.
  final Color backgroundEnd;

  /// Base de la tuile-lettre au repos (le dégradé est dérivé en widget).
  final Color tile;

  /// Lèvre 3D / bordure basse de la tuile au repos.
  final Color tileEdge;

  /// Base de la tuile-lettre sélectionnée.
  final Color tileSelected;

  /// Lèvre 3D / bordure de la tuile sélectionnée.
  final Color tileSelectedEdge;

  /// Couleur de la lettre peinte sur la tuile.
  final Color tileText;

  /// Accent principal — cellules-réponse remplies, halos, indices.
  final Color accent;

  /// Couleur du texte/contenu posé sur [accent] (contraste fort).
  final Color onAccent;

  /// Couleur du chemin tracé entre les lettres (golden path).
  final Color path;

  /// Couleur de validation (flip de victoire des cellules-réponse).
  final Color validation;

  /// Teinte d'ambiance Sommets — colore les gradients de biome vers cette
  /// couleur. `null` = ambiance purement altitude (look historique).
  final Color? sommetsTint;

  /// Motif culturel de fond (rendu en Phase B).
  final PackMotif motif;

  /// Couleur du motif. `null` = dérivée de [accent] à faible opacité.
  final Color? motifColor;

  /// Forme des tuiles (rendu non-`sculpted` en Phase B).
  final TileShape tileShape;

  /// Applique des overrides couleur distants (`theme_overrides`) sur ce preset.
  ///
  /// Les clés reconnues correspondent aux rôles couleur (`background`,
  /// `accent`, `path`, `sommets_tint`, …). Les valeurs sont des hex
  /// `#RRGGBB` / `#AARRGGBB`. Une clé absente ou invalide laisse la valeur
  /// du preset inchangée.
  PackTheme copyWithOverrides(Map<String, String>? overrides) {
    if (overrides == null || overrides.isEmpty) return this;
    Color pick(String key, Color fallback) =>
        parseHexColor(overrides[key]) ?? fallback;
    return PackTheme(
      id: id,
      background: pick('background', background),
      backgroundEnd: pick('background_end', backgroundEnd),
      tile: pick('tile', tile),
      tileEdge: pick('tile_edge', tileEdge),
      tileSelected: pick('tile_selected', tileSelected),
      tileSelectedEdge: pick('tile_selected_edge', tileSelectedEdge),
      tileText: pick('tile_text', tileText),
      accent: pick('accent', accent),
      onAccent: pick('on_accent', onAccent),
      path: pick('path', path),
      validation: pick('validation', validation),
      sommetsTint: overrides.containsKey('sommets_tint')
          ? parseHexColor(overrides['sommets_tint']) ?? sommetsTint
          : sommetsTint,
      motif: motif,
      motifColor: motifColor,
      tileShape: tileShape,
    );
  }

  /// Copie en surchargeant des champs (overrides motif/forme depuis le remote).
  PackTheme copyWith({PackMotif? motif, TileShape? tileShape}) {
    return PackTheme(
      id: id,
      background: background,
      backgroundEnd: backgroundEnd,
      tile: tile,
      tileEdge: tileEdge,
      tileSelected: tileSelected,
      tileSelectedEdge: tileSelectedEdge,
      tileText: tileText,
      accent: accent,
      onAccent: onAccent,
      path: path,
      validation: validation,
      sommetsTint: sommetsTint,
      motif: motif ?? this.motif,
      motifColor: motifColor,
      tileShape: tileShape ?? this.tileShape,
    );
  }

  /// Parse un nom de motif (`adinkra`, `kita`…) → [PackMotif]. `null` si
  /// nul/inconnu (laisse le motif du preset).
  static PackMotif? motifFromName(String? name) {
    if (name == null) return null;
    for (final m in PackMotif.values) {
      if (m.name == name.trim()) return m;
    }
    return null;
  }

  /// Parse un nom de forme (`sculpted`, `rounded`…) → [TileShape]. `null` si
  /// nul/inconnu (laisse la forme du preset).
  static TileShape? tileShapeFromName(String? name) {
    if (name == null) return null;
    for (final s in TileShape.values) {
      if (s.name == name.trim()) return s;
    }
    return null;
  }

  /// Parse un hex `#RRGGBB` ou `#AARRGGBB` (le `#` est optionnel). Retourne
  /// `null` si la chaîne est nulle/vide/invalide.
  static Color? parseHexColor(String? hex) {
    if (hex == null) return null;
    var v = hex.trim().replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    if (v.length != 8) return null;
    final value = int.tryParse(v, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  @override
  List<Object?> get props => [
    id,
    background,
    backgroundEnd,
    tile,
    tileEdge,
    tileSelected,
    tileSelectedEdge,
    tileText,
    accent,
    onAccent,
    path,
    validation,
    sommetsTint,
    motif,
    motifColor,
    tileShape,
  ];
}

/// Registre des presets de skins bundlés.
///
/// [resolve] résout un thème par son id de preset OU par convention d'id de
/// pack (les 3 packs de lancement ont chacun leur skin dédié). Tout id
/// inconnu retombe sur [PackThemes.defaultTheme] — le look « Vert Nuit »
/// historique.
abstract final class PackThemes {
  /// Thème par défaut — reproduit la palette « Vert Nuit » actuelle.
  /// Sert de fallback à tout pack sans skin dédié → zéro régression.
  static const PackTheme defaultTheme = PackTheme(
    id: 'vert_nuit',
    background: AppColors.vertForet,
    backgroundEnd: AppColors.vertForet,
    tile: AppColors.bois,
    tileEdge: AppColors.boisFonce,
    tileSelected: AppColors.orJour,
    tileSelectedEdge: AppColors.orCrepuscule,
    tileText: AppColors.surface,
    accent: AppColors.orJour,
    onAccent: AppColors.surface,
    path: AppColors.orSoleil,
    validation: AppColors.success,
  );

  /// **Culture CI** — « Terre Baoulé » : or chaud sur terre sombre,
  /// registre traditionnel.
  static const PackTheme cultureCi = PackTheme(
    id: 'terre_baoule',
    background: Color(0xFF3A2810),
    backgroundEnd: Color(0xFF20160A),
    tile: AppColors.bois,
    tileEdge: AppColors.boisFonce,
    tileSelected: AppColors.orSoleil,
    tileSelectedEdge: AppColors.orCrepuscule,
    tileText: Color(0xFF1C1409),
    accent: AppColors.orSoleil,
    onAccent: Color(0xFF1C1409),
    path: AppColors.orSoleil,
    validation: AppColors.success,
    sommetsTint: AppColors.savanneOcre,
    motif: PackMotif.adinkra,
  );

  /// **Crack Nouchi** — « Abidjan Néon » : néon urbain, teal + kola sur
  /// indigo profond.
  static const PackTheme crackNouchi = PackTheme(
    id: 'abidjan_neon',
    background: Color(0xFF2A1E4A),
    backgroundEnd: Color(0xFF150F2B),
    tile: Color(0xFF2FA39A),
    tileEdge: Color(0xFF14524C),
    tileSelected: AppColors.kola,
    tileSelectedEdge: Color(0xFFB5311F),
    tileText: Color(0xFF0B0816),
    accent: AppColors.kola,
    onAccent: AppColors.textePrimaire,
    path: Color(0xFF35E0C8),
    validation: AppColors.success,
    sommetsTint: Color(0xFF7A5CC4),
    motif: PackMotif.kita,
    tileShape: TileShape.rounded,
  );

  /// **Football Ivoirien** — « Les Éléphants » : orange/vert du drapeau CI,
  /// vibe pelouse.
  static const PackTheme footballCi = PackTheme(
    id: 'les_elephants',
    background: Color(0xFF134A24),
    backgroundEnd: Color(0xFF0A2A14),
    tile: Color(0xFFE07B2E),
    tileEdge: Color(0xFF7A3D10),
    tileSelected: Color(0xFFF59E0B),
    tileSelectedEdge: Color(0xFFB5710A),
    tileText: Color(0xFF05130A),
    accent: Color(0xFFF59E0B),
    onAccent: Color(0xFF05130A),
    path: Color(0xFFFF8A3D),
    validation: AppColors.success,
    sommetsTint: Color(0xFF1F8A4C),
    motif: PackMotif.vagues,
  );

  /// Tous les presets indexés par leur [PackTheme.id].
  static const Map<String, PackTheme> _byPresetId = <String, PackTheme>{
    'vert_nuit': defaultTheme,
    'terre_baoule': cultureCi,
    'abidjan_neon': crackNouchi,
    'les_elephants': footballCi,
  };

  /// Skin dédié par id de pack de lancement (convention de mapping).
  static const Map<String, PackTheme> _byPackId = <String, PackTheme>{
    'culture_ci': cultureCi,
    'crack_nouchi': crackNouchi,
    'football_ci': footballCi,
  };

  /// Résout un thème à appliquer.
  ///
  /// Ordre de priorité :
  ///   1. [themeId] explicite (depuis le remote) correspondant à un preset ;
  ///   2. skin conventionnel de [packId] ;
  ///   3. [defaultTheme].
  ///
  /// Les [overrides] couleur distants sont appliqués sur le preset résolu.
  static PackTheme resolve({
    String? packId,
    String? themeId,
    Map<String, String>? overrides,
    String? motifName,
    String? tileShapeName,
  }) {
    final base =
        (themeId != null ? _byPresetId[themeId] : null) ??
        (packId != null ? _byPackId[packId] : null) ??
        defaultTheme;
    final withColors = base.copyWithOverrides(overrides);
    final motif = PackTheme.motifFromName(motifName);
    final shape = PackTheme.tileShapeFromName(tileShapeName);
    if (motif == null && shape == null) return withColors;
    return withColors.copyWith(motif: motif, tileShape: shape);
  }

  /// Liste de tous les presets (debug / écran de prévisualisation futur).
  static List<PackTheme> get all => _byPresetId.values.toList();
}
