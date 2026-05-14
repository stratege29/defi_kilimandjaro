import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { checkAndIncrement } from "../utils/rateLimiter";

const ReportInput = z.object({
  devinetteId: z.string().min(1).max(64),
  world: z.string().min(2).max(64),
  reason: z.enum(["offensive", "incorrect", "duplicate", "spam", "other"]),
  details: z.string().max(280).optional(),
});

const AUTO_FLAG_THRESHOLD = 3;

/**
 * Signalement d'une devinette communautaire en jeu.
 *
 * Quota : 20 reports / utilisateur / jour. Au-delà de [AUTO_FLAG_THRESHOLD]
 * reports en 24h sur la même devinette, la soumission correspondante est
 * automatiquement passée en `flagged` et exclue du prochain rebuild du
 * pack communautaire (cf. `rebuildCommunityPack`).
 */
export const reportDevinette = onCall(
  {
    region: "europe-west1",
    // App Check enforcement deferred until feature/app-check is merged and
    // App Check is configured in Firebase Console. Flip back to true once
    // that's done.
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    const auth = req.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }

    const parsed = ReportInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const input = parsed.data;

    const quota = await checkAndIncrement("users_quota", `${auth.uid}_reports`, 20);
    if (!quota.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        "Trop de signalements aujourd'hui."
      );
    }

    const ref = getFirestore().collection("reports").doc();
    await ref.set({
      reporterUid: auth.uid,
      devinetteId: input.devinetteId,
      world: input.world,
      reason: input.reason,
      details: input.details ?? null,
      status: "open",
      createdAt: FieldValue.serverTimestamp(),
    });

    // Auto-flag si seuil dépassé sur 24h.
    const dayAgo = new Date(Date.now() - 24 * 3600 * 1000);
    const recentReports = await getFirestore()
      .collection("reports")
      .where("devinetteId", "==", input.devinetteId)
      .where("createdAt", ">=", dayAgo)
      .get();

    if (recentReports.size >= AUTO_FLAG_THRESHOLD) {
      const subSnap = await getFirestore()
        .collection("submissions")
        .where("world", "==", input.world)
        .where("__name__", "==", input.devinetteId)
        .limit(1)
        .get();
      if (!subSnap.empty) {
        await subSnap.docs[0].ref.update({
          status: "flagged",
          flaggedAt: FieldValue.serverTimestamp(),
          autoFlagReason: `${recentReports.size} reports / 24h`,
        });
        logger.warn("Auto-flag soumission après reports", {
          devinetteId: input.devinetteId,
          reportCount: recentReports.size,
        });
      }
    }

    return { reportId: ref.id };
  }
);
