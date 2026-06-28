import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireModerator } from "../utils/auth";

/**
 * `moderateSubmission` — approuve / rejette une devinette UGC (`submissions`).
 *
 * Les règles Firestore interdisent l'écriture client sur `submissions`
 * (`allow update, delete: if false`) : la modération DOIT passer par cette CF
 * (Admin SDK). Statuts canoniques `approved` / `rejected` (cohérents avec
 * `rebuildCommunityPack` qui ne reprend que `status == 'approved'`).
 *
 * Guard : requireModerator (moderator ou admin).
 */
const Input = z.object({
  submissionId: z.string().min(1).max(200),
  status: z.enum(["approved", "rejected"]),
});

export const moderateSubmission = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; status: string }> => {
    const uid = requireModerator(req.auth);
    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { submissionId, status } = parsed.data;
    const ref = getFirestore().collection("submissions").doc(submissionId);
    if (!(await ref.get()).exists) {
      throw new HttpsError("not-found", "Soumission introuvable.");
    }
    const now = FieldValue.serverTimestamp();
    await ref.set(
      {
        status,
        reviewedAt: now,
        reviewedBy: uid,
        moderatedAt: now,
        moderatedBy: uid,
      },
      { merge: true }
    );
    logger.info("moderateSubmission", { uid, submissionId, status });
    return { ok: true, status };
  }
);
