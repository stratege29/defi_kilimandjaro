import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";

/**
 * `upsertPackMeta` — édite les métadonnées marketing/catalogue d'un pack.
 *
 * Met à jour l'élément correspondant dans `catalog/index.packs[]` (la liste lue
 * par l'app pour le store : visibilité, ordre, prix, couleur, tags…). Bump
 * `catalog_version` pour invalider le cache client.
 *
 * NE TOUCHE PAS aux champs gérés par publishPack (current_version, count,
 * hash…) : seuls les champs du patch fournis sont écrasés.
 *
 * Guard : requireAdmin (mutation catalogue = niveau admin, comme publishPack).
 */
/** Hex `#RRGGBB` ou `#AARRGGBB` (le `#` est optionnel, accepté par le client). */
const hexColor = z
  .string()
  .regex(/^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/, "couleur hex invalide");

/**
 * Overrides couleur du skin (`theme_overrides`). Les clés = rôles couleur du
 * `PackTheme` côté app (cf. `lib/domain/entities/pack_theme.dart`
 * `copyWithOverrides`). Toutes optionnelles ; une clé absente garde la valeur
 * du preset. `strict()` rejette toute clé inconnue (anti-typo).
 */
const ThemeOverrides = z
  .object({
    background: hexColor.optional(),
    background_end: hexColor.optional(),
    tile: hexColor.optional(),
    tile_edge: hexColor.optional(),
    tile_selected: hexColor.optional(),
    tile_selected_edge: hexColor.optional(),
    tile_text: hexColor.optional(),
    accent: hexColor.optional(),
    on_accent: hexColor.optional(),
    path: hexColor.optional(),
    validation: hexColor.optional(),
    sommets_tint: hexColor.optional(),
  })
  .strict();

/** Map localisée `{fr: ..., en: ...}` — clés = codes langue ISO. */
const LocalizedString = z
  .record(z.string().min(1).max(280))
  .refine((m) => Object.keys(m).length > 0, "map localisée vide");

const Patch = z
  .object({
    visible: z.boolean().optional(),
    ordering: z.number().int().min(0).max(100000).optional(),
    unlock_cost_cauris: z.number().int().min(0).max(1000000).optional(),
    theme_color_hex: z
      .string()
      .regex(/^#?[0-9a-fA-F]{6}$/, "couleur hex invalide")
      .optional(),
    // Id du preset de skin bundlé (cf. `PackThemes`). null = pas de preset
    // explicite (résolution par convention d'id de pack, sinon défaut).
    theme_id: z
      .string()
      .regex(/^[a-z][a-z0-9_]{1,31}$/, "theme_id invalide")
      .nullable()
      .optional(),
    // Overrides couleur distants. null/objet vide = aucun override.
    theme_overrides: ThemeOverrides.nullable().optional(),
    // Override du motif de fond. null = motif du preset.
    theme_motif: z
      .enum(["none", "adinkra", "kita", "bogolan", "kente", "vagues"])
      .nullable()
      .optional(),
    // Override de la forme des tuiles. null = forme du preset.
    theme_tile_shape: z
      .enum(["sculpted", "rounded", "hex", "diamond"])
      .nullable()
      .optional(),
    bundled: z.boolean().optional(),
    free_choice_eligible: z.boolean().optional(),
    min_app_version: z.string().max(20).optional(),
    tags: z.array(z.string()).max(20).optional(),
    // Libellés server-driven écrits dans catalog/index.packs[] : permettent de
    // nommer un pack OTA sans release app (le client préfère ces valeurs aux
    // clés i18n bundlées `pack.<id>.name`). Cf Pack.localizedName côté Flutter.
    name: LocalizedString.optional(),
    description: LocalizedString.optional(),
  })
  .strict();

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  patch: Patch,
});

export const upsertPackMeta = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req) => {
    const uid = requireAdmin(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, patch } = parsed.data;
    if (Object.keys(patch).length === 0) {
      throw new HttpsError("invalid-argument", "patch vide.");
    }
    // Normalise la couleur en #RRGGBB.
    if (patch.theme_color_hex && !patch.theme_color_hex.startsWith("#")) {
      patch.theme_color_hex = `#${patch.theme_color_hex}`;
    }
    // Normalise les overrides : préfixe `#`, et collapse l'objet vide en null
    // (= aucun override) pour que le client retombe proprement sur le preset.
    if (patch.theme_overrides) {
      const o = patch.theme_overrides as Record<string, string>;
      for (const k of Object.keys(o)) {
        if (o[k] && !o[k].startsWith("#")) o[k] = `#${o[k]}`;
      }
      if (Object.keys(o).length === 0) patch.theme_overrides = null;
    }

    const db = getFirestore();
    const ref = db.collection("catalog").doc("index");

    const catalogVersion = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() ?? {} : {};
      const packs: Array<Record<string, unknown>> = Array.isArray(data.packs)
        ? [...data.packs]
        : [];
      const idx = packs.findIndex((p) => p && p.id === packId);
      if (idx < 0) {
        throw new HttpsError(
          "not-found",
          `Pack ${packId} absent de catalog/index.packs[].`
        );
      }
      packs[idx] = { ...packs[idx], ...patch };
      const next = ((data.catalog_version as number | undefined) ?? 0) + 1;
      tx.set(
        ref,
        {
          packs,
          catalog_version: next,
          updated_at: FieldValue.serverTimestamp(),
          updated_by: uid,
        },
        { merge: true }
      );
      return next;
    });

    logger.info("upsertPackMeta", { uid, packId, fields: Object.keys(patch) });
    return { ok: true, packId, catalogVersion };
  }
);
