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
const Patch = z
  .object({
    visible: z.boolean().optional(),
    ordering: z.number().int().min(0).max(100000).optional(),
    unlock_cost_cauris: z.number().int().min(0).max(1000000).optional(),
    theme_color_hex: z
      .string()
      .regex(/^#?[0-9a-fA-F]{6}$/, "couleur hex invalide")
      .optional(),
    bundled: z.boolean().optional(),
    free_choice_eligible: z.boolean().optional(),
    min_app_version: z.string().max(20).optional(),
    tags: z.array(z.string()).max(20).optional(),
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
