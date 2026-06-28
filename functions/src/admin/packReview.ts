import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";
import { normalize, lettersPoolFromAnswer } from "../utils/normalize";
import {
  jobRef,
  candidatesRef,
  db,
  devinetteFromCandidate,
  ensurePackInCatalog,
  estimatedTimeForDifficulty,
  isValidAnswer,
  riddleHidesAnswer,
  PACK_ID_RE,
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
  // Réaffectation optionnelle : promeut la question dans un AUTRE pack
  // (qui la verra alors dans ses drafts / sa publication).
  targetPackId: z.string().regex(PACK_ID_RE, "targetPackId invalide").optional(),
});

/** Prochain id `<packId>_NNN` à partir des ids déjà présents (max + 1). */
function computeNextDeviId(packId: string, deviIds: string[]): string {
  const re = new RegExp(`^${packId}_(\\d+)$`);
  let max = 0;
  for (const id of deviIds) {
    const m = id.match(re);
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  return `${packId}_${String(max + 1).padStart(3, "0")}`;
}

export const approveCandidate = onCall(
  OPTS,
  async (req): Promise<{ ok: true; deviId: string }> => {
    const uid = requireEditor(req.auth);
    const parsed = CandRef.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, candId, targetPackId } = parsed.data;
    const candDocRef = candidatesRef(jobId).doc(candId);
    const candSnap = await candDocRef.get();
    if (!candSnap.exists) throw new HttpsError("not-found", "Candidat introuvable.");
    const cand = candSnap.data() as CandidateData;
    if (cand.reviewStatus === "approved" && cand.promotedDeviId) {
      return { ok: true, deviId: cand.promotedDeviId };
    }

    // Pack cible : explicite (param), sinon la destination déjà fixée par une
    // réaffectation (effectivePackId), sinon le pack du job. On s'assure que le
    // pack existe au catalogue s'il diffère du pack du job.
    const packId = targetPackId ?? cand.effectivePackId ?? cand.packId;
    if (packId !== cand.packId) {
      await ensurePackInCatalog(packId, uid);
    }
    const packRef = db().collection("packs").doc(packId);
    const metaRef = packRef.collection("meta").doc("doc");

    // Allocation de l'id + écritures dans UNE transaction : deux approbations
    // concurrentes ne peuvent pas attribuer le même `<packId>_NNN` (collision
    // → perte d'un candidat). Firestore re-tente la transaction en cas de conflit.
    const deviId = await db().runTransaction(async (tx) => {
      const candCur = await tx.get(candDocRef);
      const curData = candCur.data() as CandidateData | undefined;
      if (curData?.reviewStatus === "approved" && curData.promotedDeviId) {
        return curData.promotedDeviId; // déjà promu (idempotent)
      }
      // Contenu le plus frais lu dans la transaction (un updateCandidate
      // concurrent peut avoir édité la réponse entre la lecture initiale et ici).
      // `packId` forcé au pack cible pour le champ `pack` + le préfixe d'id.
      const source = { ...(curData ?? cand), packId };
      const deviSnap = await tx.get(
        packRef.collection("devinettes").select("answer_normalized")
      );
      const metaSnap = await tx.get(metaRef);
      const nextDraftVersion =
        (metaSnap.data()?.next_draft_version as number | undefined) ?? 1;

      // Déduplication contre le PACK CIBLE : refuse de promouvoir une réponse
      // déjà présente (évite les DUPLICATE_ANSWER bloquant la publication).
      const candNorm = normalize((source.answer || "").toUpperCase());
      const existing = deviSnap.docs.find(
        (d) => (d.data().answer_normalized as string | undefined) === candNorm
      );
      if (existing) {
        throw new HttpsError(
          "failed-precondition",
          `Réponse « ${source.answer} » déjà présente dans le pack ${packId} (${existing.id}) — doublon.`
        );
      }

      const id = computeNextDeviId(
        packId,
        deviSnap.docs.map((d) => d.id)
      );
      const now = FieldValue.serverTimestamp();

      tx.set(
        packRef.collection("devinettes").doc(id),
        devinetteFromCandidate(source, id, uid, nextDraftVersion, now, null),
        { merge: true }
      );
      tx.set(
        metaRef,
        {
          id: packId,
          pending_changes: FieldValue.increment(1),
          next_draft_version: nextDraftVersion,
          updated_at: now,
          updated_by: uid,
        },
        { merge: true }
      );
      tx.set(
        candDocRef,
        {
          reviewStatus: "approved",
          reviewedBy: uid,
          reviewedAt: now,
          promotedDeviId: id,
          promotedPackId: packId,
        },
        { merge: true }
      );
      return id;
    });

    logger.info("approveCandidate", { uid, jobId, candId, packId, deviId });
    return { ok: true, deviId };
  }
);

const ReassignInput = z.object({
  jobId: z.string().min(3).max(120),
  candId: z.string().min(3).max(60),
  targetPackId: z.string().regex(PACK_ID_RE, "targetPackId invalide"),
});

/**
 * Réaffecte une question EN ATTENTE vers un autre pack (sans l'approuver) :
 * la question reste `pending` mais apparaît désormais dans la revue du pack
 * cible (`effectivePackId`). Elle n'entre dans aucun draft publiable tant
 * qu'elle n'est pas approuvée.
 */
export const reassignCandidate = onCall(
  OPTS,
  async (req): Promise<{ ok: true; effectivePackId: string }> => {
    const uid = requireEditor(req.auth);
    const parsed = ReassignInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, candId, targetPackId } = parsed.data;
    const ref = candidatesRef(jobId).doc(candId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Candidat introuvable.");
    const cand = snap.data() as CandidateData;
    if (cand.reviewStatus === "approved") {
      throw new HttpsError(
        "failed-precondition",
        "Question déjà approuvée — réaffectation impossible."
      );
    }
    if (targetPackId !== cand.packId) {
      await ensurePackInCatalog(targetPackId, uid);
    }
    await ref.set(
      {
        targetPackId,
        effectivePackId: targetPackId,
        reviewStatus: "pending",
        reviewedBy: uid,
        reviewedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logger.info("reassignCandidate", { uid, jobId, candId, targetPackId });
    return { ok: true, effectivePackId: targetPackId };
  }
);

const DailyInput = z.object({
  jobId: z.string().min(3).max(120),
  candId: z.string().min(3).max(60),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date attendue yyyy-MM-dd"),
});

/**
 * Affecte une question (candidat) comme **devinette du jour** d'une date donnée
 * (`daily_challenges/{date}`), et marque le candidat traité. Le doc du jour est
 * une Devinette v3 complète embarquée (même format que upsertDailyChallenge).
 *
 * Guard : requireEditor.
 */
export const assignCandidateToDaily = onCall(
  OPTS,
  async (req): Promise<{ ok: true; date: string; deviId: string }> => {
    const uid = requireEditor(req.auth);
    const parsed = DailyInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, candId, date } = parsed.data;
    const candRef = candidatesRef(jobId).doc(candId);
    const snap = await candRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Candidat introuvable.");
    const cand = snap.data() as CandidateData;

    const answerUpper = (cand.answer || "").toUpperCase();
    if (!isValidAnswer(answerUpper)) {
      throw new HttpsError("failed-precondition", `Réponse « ${cand.answer} » invalide.`);
    }
    const answerNormalized = normalize(answerUpper);
    const lettersPool = lettersPoolFromAnswer(answerNormalized.toUpperCase());
    const deviId = `daily_${date.replace(/-/g, "")}`;
    const now = FieldValue.serverTimestamp();

    await db().collection("daily_challenges").doc(date).set({
      id: deviId,
      pack: "daily",
      country: cand.country || "ci",
      answer: answerUpper,
      answer_normalized: answerNormalized,
      letters_pool: lettersPool,
      riddle: { fr: cand.riddleFr },
      explanation: { fr: cand.explanationFr },
      difficulty: cand.difficulty,
      estimated_time_s: cand.estimatedTimeS,
      tags: (cand.tags ?? []).map((t) => String(t).toLowerCase()),
      format_version: 3,
      source: "remotePack",
      assigned_at: now,
      assigned_by: uid,
      custom: true,
      source_job: cand.jobId,
    });

    await candRef.set(
      {
        reviewStatus: "approved",
        reviewedBy: uid,
        reviewedAt: now,
        promotedDeviId: deviId,
        promotedPackId: "daily",
        promotedDailyDate: date,
      },
      { merge: true }
    );

    logger.info("assignCandidateToDaily", { uid, jobId, candId, date });
    return { ok: true, date, deviId };
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
