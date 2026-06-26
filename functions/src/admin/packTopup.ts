import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import { db } from "./packJobsShared";

/**
 * Pack Creator — réglage du ré-approvisionnement hebdomadaire par pack.
 *
 * Config stockée dans `pack_topup/{packId}` (OFF par défaut), lue par le cron
 * weeklyPackTopup. Topic requis à l'activation (sujet des nouvelles questions).
 *
 * Guard : requireAdmin.
 */

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  enabled: z.boolean(),
  perWeek: z.number().int().min(1).max(50).optional(),
  topic: z.string().min(3).max(160).optional(),
});

export const setPackTopup = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; enabled: boolean }> => {
    const uid = requireAdmin(req.auth);
    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, enabled, perWeek, topic } = parsed.data;
    const ref = db().collection("pack_topup").doc(packId);
    const existing = (await ref.get()).data() ?? {};

    const finalTopic = topic ?? (existing.topic as string | undefined);
    if (enabled && !finalTopic) {
      throw new HttpsError(
        "invalid-argument",
        "topic requis pour activer le ré-approvisionnement."
      );
    }

    await ref.set(
      {
        packId,
        enabled,
        perWeek: perWeek ?? (existing.perWeek as number | undefined) ?? 10,
        topic: finalTopic ?? null,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      },
      { merge: true }
    );
    logger.info("setPackTopup", { uid, packId, enabled });
    return { ok: true, enabled };
  }
);
