import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";

/**
 * Gestion des "devinettes du jour" (collection `daily_challenges/{yyyy-MM-dd}`).
 *
 * Le doc du jour EST une Devinette sérialisée complète (contenu embarqué, pas
 * une référence). L'app lit `daily_challenges/{cléDateLocale}` directement.
 *
 * `upsertDailyChallenge` : assigne une devinette existante (d'un pack) à une
 * date → copie son contenu dans daily_challenges/{date} (overwrite, comme le
 * script de seed).
 * `deleteDailyChallenge` : retire le doc du jour (l'app retombe sur le bundle).
 *
 * Guard : requireEditor.
 */
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const UpsertInput = z.object({
  date: z.string().regex(DATE_RE, "date attendue au format yyyy-MM-dd"),
  sourcePackId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/),
  sourceDeviId: z.string().min(1),
});

export const upsertDailyChallenge = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req) => {
    const uid = requireEditor(req.auth);

    const parsed = UpsertInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { date, sourcePackId, sourceDeviId } = parsed.data;

    const db = getFirestore();
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

    // Reconstruit une Devinette propre (format v3), telle que l'app la parse.
    const daily: Record<string, unknown> = {
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
      assigned_at: FieldValue.serverTimestamp(),
      assigned_by: uid,
      source_pack: sourcePackId,
      source_devi_id: sourceDeviId,
    };
    if (d.image_svg) daily.image_svg = d.image_svg;
    if (d.image_url) daily.image_url = d.image_url;

    await db.collection("daily_challenges").doc(date).set(daily);

    logger.info("upsertDailyChallenge", { uid, date, sourcePackId, sourceDeviId });
    return { ok: true, date, deviId: d.id };
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
