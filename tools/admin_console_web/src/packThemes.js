// Miroir admin des presets de skin et des rôles couleur.
//
// Source de vérité côté app : `lib/domain/entities/pack_theme.dart`
// (`PackThemes` pour les ids de preset, `copyWithOverrides` pour les rôles).
// Garder ces deux listes synchronisées : un `theme_id` doit correspondre à un
// preset bundlé, une clé d'override à un rôle reconnu par le client.

/** Presets de skin bundlés sélectionnables (`theme_id`). */
export const THEME_PRESETS = [
  { id: '', label: '(défaut / par convention d’id de pack)' },
  { id: 'vert_nuit', label: 'Vert Nuit — défaut' },
  { id: 'terre_baoule', label: 'Terre Baoulé — Culture (adinkra)' },
  { id: 'abidjan_neon', label: 'Abidjan Néon — Nouchi (kita)' },
  { id: 'les_elephants', label: 'Les Éléphants — Football (vagues)' },
];

/** Motifs de fond (`theme_motif`). Vide = motif du preset. */
export const MOTIF_OPTIONS = [
  { id: '', label: '(motif du preset)' },
  { id: 'none', label: 'Aucun' },
  { id: 'adinkra', label: 'Adinkra (anneaux)' },
  { id: 'kita', label: 'Kita (tissage diagonal)' },
  { id: 'bogolan', label: 'Bogolan (chevrons)' },
  { id: 'kente', label: 'Kente (trame)' },
  { id: 'vagues', label: 'Vagues' },
];

/** Formes de tuiles (`theme_tile_shape`). Vide = forme du preset. */
export const TILE_SHAPE_OPTIONS = [
  { id: '', label: '(forme du preset)' },
  { id: 'sculpted', label: 'Sculptée (carré doux)' },
  { id: 'rounded', label: 'Arrondie (galet)' },
  { id: 'hex', label: 'Hexagone' },
  { id: 'diamond', label: 'Losange' },
];

/** Rôles couleur surchargeables (`theme_overrides`). */
export const THEME_ROLES = [
  { key: 'background', label: 'Fond (haut)' },
  { key: 'background_end', label: 'Fond (bas)' },
  { key: 'tile', label: 'Tuile' },
  { key: 'tile_edge', label: 'Tuile — lèvre' },
  { key: 'tile_selected', label: 'Tuile sélectionnée' },
  { key: 'tile_selected_edge', label: 'Tuile sél. — lèvre' },
  { key: 'tile_text', label: 'Lettre tuile' },
  { key: 'accent', label: 'Accent (cellules)' },
  { key: 'on_accent', label: 'Texte sur accent' },
  { key: 'path', label: 'Chemin' },
  { key: 'validation', label: 'Validation' },
  { key: 'sommets_tint', label: 'Teinte Sommets' },
];
