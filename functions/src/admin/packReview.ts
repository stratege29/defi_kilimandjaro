import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";
import { normalize } from "../utils/normalize";
import {
  jobRef,
  candidatesRef,
  db,
  devinetteFromCandidate,
  estimatedTimeForDifficulty,
  isValidAnswer,
  riddleHidesAnswer,
  type CandidateData,
} from "./packJobsShared";

/**
 * Pack Creator — revue des candidats (édition incluse).
 *
 * - approveCandidate : copie le candidat dans `packs/{packId}/devinettes` en
 *   status=draft (id `<packId>_NNN` contigu), recalcule answer_normalized +
 *   letters_pool comme upsertDevinette. Le pack se publie ensuite via publishPack.
 * - rejectCandidate  : marque rejected (+ raison).
 * - updateCandidate  : édite un candidat (recompute serveur) et le repasse en
 *   pending pour re-revue.
 *
 * Guard : requireEditor.
 */

const OPTS = { region: "europe-west1" as const, enforceAppCheck: false, cors: true };
const CandRef = z.object({
  jobId: z.string().min(3).max(120),
  candId: z.string().min(3).max(60),
});

/** Calcule le prochain id `<packId>_NNN` (max existant + 1, padding 3). */
async function nextDevinetteId(packId: string): Promise<string> {
  const snap = await db()
    .collection("packs")
    .doc(packId)
    .collection("devinettes")
    .get();
  const re = new RegExp(`^${packId}_(\\d+)$`);
  let max = 0;
  for (const d of snap.docs) {
    const m = d.id.match(re);
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  const n = max + 1;
  return `${packId}_${String(n).padStart(3, "0")}`;
}

export const approveCandidate = onCall(
  OPTS,
  async (req): Promise<{ ok: true; deviId: string }> => {
    const uid = requireEditor(req.auth);
    const parsed = CandRef.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, candId } = parsed.data;
    const candDocRef = candidatesRef(jobId).doc(candId);
    const candSnap = await candDocRef.get();
    if (!candSnap.exists) throw new HttpsError("not-found", "Candidat introuvable.");
    const cand = candSnap.data() as CandidateData;
    if (cand.reviewStatus === "approved" && cand.promotedDeviId) {
      return { ok: true, deviId: cand.promotedDeviId };
    }

    const packId = cand.packId;
    const packRef = db().collection("packs").doc(packId);

    const metaSnap = await packRef.collection("meta").doc("doc").get();
    const nextDraftVersion =
      (metaSnap.data()?.next_draft_version as number | undefined) ?? 1;

    const deviId = await nextDevinetteId(packId);
    const now = FieldValue.serverTimestamp();
    const payload = devinetteFromCandidate(
      cand,
      deviId,
      uid,
      nextDraftVersion,
      now,
      null
    );

    await packRef.collection("devinettes").doc(deviId).set(payload, { merge: true });
    await packRef.collection("meta").doc("doc").set(
      {
        id: packId,
        pending_changes: FieldValue.increment(1),
        next_draft_version: nextDraftVersion,
        updated_at: now,
        updated_by: uid,
      },
      { merge: true }
    );
    await candDocRef.set(
      {
        reviewStatus: "approved",
        reviewedBy: uid,
        reviewedAt: now,
        promotedDeviId: deviId,
      },
      { merge: true }
    );

    logger.info("approveCandidate", { uid, jobId, candId, packId, deviId });
    return { ok: true, deviId };
  }
);

const RejectInput = z.object({
  jobId: z.string().min(3).max(120),
  candId: z.string().min(3).max(60),
  reason: z.string().max(500).optional(),
});

export const rejectCandidate = onCall(
  OPTS,
  async (req): Promise<{ ok: true }> => {
    const uid = requireEditor(req.auth);
    const parsed = RejectInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, candId, reason } = parsed.data;
    const ref = candidatesRef(jobId).doc(candId);
    if (!(await ref.get()).exists)
      throw new HttpsError("not-found", "Candidat introuvable.");
    await ref.set(
      {
        reviewStatus: "rejected",
        rejectionReason: reason ?? null,
        reviewedBy: uid,
        reviewedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { ok: true };
  }
);

const UpdateInput = z.object({
  jobId: z.string().min(3).max(120),
  candId: z.string().min(3).max(60),
  patch: z
    .object({
      answer: z.string().min(4).max(12).optional(),
      riddleFr: z.string().min(1).max(500).optional(),
      explanationFr: z.string().max(800).optional(),
      difficulty: z.number().int().min(1).max(4).optional(),
      country: z.string().length(2).optional(),
      tags: z.array(z.string()).max(10).optional(),
    })
    .strict(),
});

export const updateCandidate = onCall(
  OPTS,
  async (req): Promise<{ ok: true }> => {
    const uid = requireEditor(req.auth);
    const parsed = UpdateInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, candId, patch } = parsed.data;
    if (Object.keys(patch).length === 0) {
      throw new HttpsError("invalid-argument", "patch vide.");
    }
    const ref = candidatesRef(jobId).doc(candId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Candidat introuvable.");
    const cand = snap.data() as CandidateData;

    const update: Record<string, unknown> = {
      reviewStatus: "pending",
      reviewedBy: uid,
      reviewedAt: FieldValue.serverTimestamp(),
    };

    const nextAnswer =
      patch.answer !== undefined ? patch.answer.toUpperCase().trim() : cand.answer;
    const nextRiddle = patch.riddleFr ?? cand.riddleFr;
    if (patch.answer !== undefined) {
      if (!isValidAnswer(nextAnswer)) {
        throw new HttpsError("invalid-argument", `answer "${nextAnswer}" invalide.`);
      }
      update.answer = nextAnswer;
      update.answerNormalized = normalize(nextAnswer);
    }
    if (!riddleHidesAnswer(nextRiddle, nextAnswer)) {
      throw new HttpsError(
        "invalid-argument",
        "L'énigme ne doit pas contenir la réponse."
      );
    }
    if (patch.riddleFr !== undefined) update.riddleFr = patch.riddleFr;
    if (patch.explanationFr !== undefined)
      update.explanationFr = patch.explanationFr;
    if (patch.difficulty !== undefined) {
      update.difficulty = patch.difficulty;
      update.estimatedTimeS = estimatedTimeForDifficulty(patch.difficulty);
    }
    if (patch.country !== undefined) update.country = patch.country;
    if (patch.tags !== undefined) update.tags = patch.tags;

    await ref.set(update, { merge: true });
    logger.info("updateCandidate", { uid, jobId, candId, fields: Object.keys(patch) });
    return { ok: true };
  }
);
