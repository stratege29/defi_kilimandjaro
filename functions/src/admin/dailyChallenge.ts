import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";
import { normalize, lettersPoolFromAnswer } from "../utils/normalize";

/**
 * Gestion des "devinettes du jour" (collection `daily_challenges/{yyyy-MM-dd}`).
 *
 * Le doc du jour EST une Devinette sérialisée complète (contenu embarqué, pas
 * une référence). L'app lit `daily_challenges/{cléDateLocale}` directement.
 *
 * `upsertDailyChallenge` : assigne soit une devinette existante d'un pack
 * (source), soit un contenu 100% custom (custom). Dans les deux cas le doc
 * écrit est une Devinette format v3 complète (overwrite, comme le seed).
 * `deleteDailyChallenge` : retire le doc du jour (l'app retombe sur le bundle).
 *
 * Guard : requireEditor.
 */
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const CustomDevinette = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*$/).optional(),
  pack: z.string().min(2).optional(),
  country: z.string().length(2).optional(),
  answer: z.string().min(4).max(12),
  riddle: z.record(z.string(), z.string()).optional(),
  explanation: z.record(z.string(), z.string()).optional(),
  difficulty: z.number().int().min(1).max(4),
  estimated_time_s: z.number().int().min(5).max(300).optional(),
  tags: z.array(z.string()).max(10).optional(),
});

const UpsertInput = z.object({
  date: z.string().regex(DATE_RE, "date attendue au format yyyy-MM-dd"),
  // Option A : depuis un pack existant
  sourcePackId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/).optional(),
  sourceDeviId: z.string().min(1).optional(),
  // Option B : contenu 100% custom
  custom: CustomDevinette.optional(),
});

export const upsertDailyChallenge = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req) => {
    const uid = requireEditor(req.auth);

    const parsed = UpsertInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { date, sourcePackId, sourceDeviId, custom } = parsed.data;

    const db = getFirestore();
    const now = FieldValue.serverTimestamp();
    let daily: Record<string, unknown>;

    if (custom) {
      // --- Contenu custom : recompute serveur-side comme upsertDevinette ---
      const answerUpper = custom.answer.toUpperCase();
      const answerNormalized = normalize(answerUpper);
      const lettersPool = lettersPoolFromAnswer(answerNormalized.toUpperCase());
      const id = custom.id ?? `daily_${date.replace(/-/g, "")}`;
      daily = {
        id,
        pack: custom.pack ?? "daily",
        country: custom.country ?? "ci",
        answer: answerUpper,
        answer_normalized: answerNormalized,
        letters_pool: lettersPool,
        riddle: custom.riddle ?? {},
        explanation: custom.explanation ?? {},
        difficulty: custom.difficulty,
        estimated_time_s: custom.estimated_time_s ?? 30,
        tags: custom.tags ?? [],
        format_version: 3,
        source: "remotePack",
        assigned_at: now,
        assigned_by: uid,
        custom: true,
      };
    } else if (sourcePackId && sourceDeviId) {
      // --- Depuis un pack existant ---
      const srcSnap = await db
        .collection("packs")
        .doc(sourcePackId)
        .collection("devinettes")
        .doc(sourceDeviId)
        .get();
      if (!srcSnap.exists) {
        throw new HttpsError(
          "not-found",
          `Devinette ${sourceDeviId} introuvable dans ${sourcePackId}.`
        );
      }
      const d = srcSnap.data() ?? {};
      daily = {
        id: d.id,
        pack: d.pack,
        country: d.country,
        answer: d.answer,
        answer_normalized: d.answer_normalized,
        letters_pool: d.letters_pool,
        riddle: d.riddle ?? {},
        explanation: d.explanation ?? {},
        difficulty: d.difficulty,
        estimated_time_s: d.estimated_time_s ?? 30,
        tags: d.tags ?? [],
        format_version: 3,
        source: "remotePack",
        assigned_at: now,
        assigned_by: uid,
        source_pack: sourcePackId,
        source_devi_id: sourceDeviId,
      };
      if (d.image_svg) daily.image_svg = d.image_svg;
      if (d.image_url) daily.image_url = d.image_url;
    } else {
      throw new HttpsError(
        "invalid-argument",
        "Fournir soit {sourcePackId, sourceDeviId}, soit {custom}."
      );
    }

    await db.collection("daily_challenges").doc(date).set(daily);

    logger.info("upsertDailyChallenge", {
      uid,
      date,
      mode: custom ? "custom" : "source",
    });
    return { ok: true, date, deviId: daily.id };
  }
);

const DeleteInput = z.object({
  date: z.string().regex(DATE_RE, "date attendue au format yyyy-MM-dd"),
});

export const deleteDailyChallenge = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req) => {
    const uid = requireEditor(req.auth);

    const parsed = DeleteInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { date } = parsed.data;

    await getFirestore().collection("daily_challenges").doc(date).delete();
    logger.info("deleteDailyChallenge", { uid, date });
    return { ok: true, date };
  }
);
