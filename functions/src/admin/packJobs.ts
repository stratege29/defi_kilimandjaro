import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import {
  jobRef,
  ensurePackInCatalog,
  PACK_ID_RE,
  DEFAULT_TARGET_TOTAL,
  DEFAULT_BATCH_SIZE,
  DEFAULT_CAPS,
} from "./packJobsShared";

/**
 * Pack Creator — gestion de la file de jobs (création / annulation / reprise).
 *
 * - createPackJob : enfile un pack à créer, s'assure qu'il existe dans
 *   `catalog/index.packs[]` (visible:false), prêt pour le plan de recherche.
 * - cancelPackJob : passe le job en `cancelled` (le drainer l'ignore).
 * - retryPackJob  : réinitialise le circuit breaker après un `failed`.
 *
 * Guard : requireAdmin.
 */

/** Lots plus gros + vérif Wikipedia-only en mode éco (tient dans 20 req/jour). */
const ECO_BATCH_SIZE = 50;

const CreateInput = z.object({
  packId: z.string().regex(PACK_ID_RE, "packId invalide"),
  topic: z.string().min(3).max(160),
  targetTotal: z.number().int().min(50).max(1000).optional(),
  ecoQuota: z.boolean().optional(),
  langs: z.array(z.string().length(2)).optional(),
  caps: z
    .object({
      maxCandidates: z.number().int().min(50).max(2000).optional(),
      maxClaudeCallsPerJob: z.number().int().min(5).max(500).optional(),
      maxUsd: z.number().min(1).max(500).optional(),
    })
    .optional(),
});

export const createPackJob = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; jobId: string }> => {
    const uid = requireAdmin(req.auth);

    const parsed = CreateInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, topic } = parsed.data;
    const targetTotal = parsed.data.targetTotal ?? DEFAULT_TARGET_TOTAL;
    const ecoQuota = parsed.data.ecoQuota === true;
    const batchSize = ecoQuota ? ECO_BATCH_SIZE : DEFAULT_BATCH_SIZE;
    const langs = parsed.data.langs ?? ["fr"];
    const caps = { ...DEFAULT_CAPS, ...(parsed.data.caps ?? {}) };

    await ensurePackInCatalog(packId, uid);

    const batchesTotal = Math.ceil(targetTotal / batchSize);
    const now = FieldValue.serverTimestamp();
    const ref = jobRef(`${packId}_${Date.now()}`);

    await ref.set({
      packId,
      topic,
      langs,
      ecoQuota,
      status: "queued",
      phase: "plan",
      plan: null,
      progress: {
        targetTotal,
        batchSize,
        nextIndex: 0,
        generated: 0,
        verified: 0,
        rejectedAuto: 0,
        duplicatesDropped: 0,
        batchesDone: 0,
        batchesTotal,
        lastBatchAt: null,
        lastError: null,
        consecutiveErrors: 0,
      },
      caps,
      usage: { claudeCalls: 0, inputTokens: 0, outputTokens: 0, estUsd: 0 },
      topupEnabled: false,
      topupPerWeek: 10,
      lastTopupAt: null,
      createdAt: now,
      createdBy: uid,
      updatedAt: now,
    });

    logger.info("createPackJob", { uid, jobId: ref.id, packId, targetTotal });
    return { ok: true, jobId: ref.id };
  }
);

const JobIdInput = z.object({ jobId: z.string().min(3).max(120) });

export const cancelPackJob = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true }> => {
    const uid = requireAdmin(req.auth);
    const parsed = JobIdInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const ref = jobRef(parsed.data.jobId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Job introuvable.");
    await ref.set(
      { status: "cancelled", updatedAt: FieldValue.serverTimestamp(), updatedBy: uid },
      { merge: true }
    );
    return { ok: true };
  }
);

export const retryPackJob = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; status: string }> => {
    const uid = requireAdmin(req.auth);
    const parsed = JobIdInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const ref = jobRef(parsed.data.jobId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Job introuvable.");
    const data = snap.data() ?? {};
    const hasPlan = !!data.plan;
    const status = hasPlan ? "plan_approved" : "queued";
    await ref.set(
      {
        status,
        progress: { consecutiveErrors: 0, lastError: null },
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      },
      { merge: true }
    );
    return { ok: true, status };
  }
);
