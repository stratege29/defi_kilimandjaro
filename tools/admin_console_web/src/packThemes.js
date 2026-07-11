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
  { key: 'bubble_background', label: 'Bulle question — fond' },
  { key: 'bubble_accent', label: 'Bulle question — filet' },
  { key: 'bubble_text', label: 'Bulle question — texte' },
  { key: 'sommets_tint', label: 'Teinte Sommets' },
];

// -------------------------------------------------------------------------
// Palettes résolues des presets — MIROIR EXACT de `PackThemes` (Dart).
// Sert uniquement à la prévisualisation admin. Les valeurs par défaut de la
// bulle question (bubble_*) sont celles du constructeur `PackTheme`
// (surfaceContainer / orJour / textePrimaire) — un preset qui ne les surcharge
// pas les hérite ici aussi. Garder synchro avec `pack_theme.dart`.
// -------------------------------------------------------------------------

/** Défauts « Vert Nuit » — base de tout preset non surchargé. */
const VERT_NUIT = {
  background: '#0C1712',
  background_end: '#0C1712',
  tile: '#C68A42',
  tile_edge: '#5E3D1A',
  tile_selected: '#E9B949',
  tile_selected_edge: '#B07E22',
  tile_text: '#0C1712',
  accent: '#E9B949',
  on_accent: '#0C1712',
  path: '#E9B949',
  validation: '#28C76F',
  bubble_background: '#1E3328',
  bubble_accent: '#E9B949',
  bubble_text: '#F4ECD8',
  sommets_tint: null,
};

/** Couleurs pleines par id de preset (tous les rôles résolus). */
export const THEME_PRESET_COLORS = {
  vert_nuit: { ...VERT_NUIT },
  terre_baoule: {
    ...VERT_NUIT,
    background: '#3A2810',
    background_end: '#20160A',
    tile_selected: '#E9B949',
    tile_text: '#1C1409',
    accent: '#E9B949',
    on_accent: '#1C1409',
    sommets_tint: '#E0AC5E',
  },
  abidjan_neon: {
    ...VERT_NUIT,
    background: '#2A1E4A',
    background_end: '#150F2B',
    tile: '#2FA39A',
    tile_edge: '#14524C',
    tile_selected: '#F0533B',
    tile_selected_edge: '#B5311F',
    tile_text: '#0B0816',
    accent: '#F0533B',
    on_accent: '#F4ECD8',
    path: '#35E0C8',
    sommets_tint: '#7A5CC4',
  },
  les_elephants: {
    ...VERT_NUIT,
    background: '#134A24',
    background_end: '#0A2A14',
    tile: '#E07B2E',
    tile_edge: '#7A3D10',
    tile_selected: '#F59E0B',
    tile_selected_edge: '#B5710A',
    tile_text: '#05130A',
    accent: '#F59E0B',
    on_accent: '#05130A',
    path: '#FF8A3D',
    sommets_tint: '#1F8A4C',
  },
};

/** Motif + forme de tuile par défaut de chaque preset (miroir `PackThemes`). */
export const THEME_PRESET_STRUCT = {
  vert_nuit: { motif: 'none', tile_shape: 'sculpted' },
  terre_baoule: { motif: 'adinkra', tile_shape: 'sculpted' },
  abidjan_neon: { motif: 'kita', tile_shape: 'rounded' },
  les_elephants: { motif: 'vagues', tile_shape: 'sculpted' },
};

/** Skin conventionnel par id de pack de lancement (miroir `_byPackId`). */
const PRESET_BY_PACK_ID = {
  culture_ci: 'terre_baoule',
  crack_nouchi: 'abidjan_neon',
  football_ci: 'les_elephants',
};

/** `#RRGGBB(AA)` valide → normalisé `#RRGGBB` ; sinon null. */
function normHex(hex) {
  if (typeof hex !== 'string') return null;
  let v = hex.trim().replace(/^#/, '');
  if (v.length === 8) v = v.slice(2); // ignore l'alpha en tête (#AARRGGBB)
  if (v.length !== 6 || /[^0-9a-fA-F]/.test(v)) return null;
  return `#${v.toUpperCase()}`;
}

/**
 * Résout les couleurs affichées d'un pack, comme le fait `PackThemes.resolve`
 * côté app : preset explicite `themeId`, sinon convention `packId`, sinon
 * défaut ; puis application des `overrides` couleur (hex valides uniquement).
 */
export function resolveThemeColors({
  themeId,
  packId,
  overrides,
  motif,
  tileShape,
} = {}) {
  const presetId =
    (themeId && THEME_PRESET_COLORS[themeId] ? themeId : null) ??
    (packId ? PRESET_BY_PACK_ID[packId] : null) ??
    'vert_nuit';
  const base = { ...THEME_PRESET_COLORS[presetId] };
  if (overrides) {
    for (const role of THEME_ROLES) {
      const h = normHex(overrides[role.key]);
      if (h) base[role.key] = h;
    }
  }
  const struct = THEME_PRESET_STRUCT[presetId];
  return {
    presetId,
    colors: base,
    // Motif/forme explicites priment ; vide = valeur du preset.
    motif: motif || struct.motif,
    tileShape: tileShape || struct.tile_shape,
  };
}
