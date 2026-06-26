import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import {
  jobRef,
  db,
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

const PACK_ID_RE = /^[a-z][a-z0-9_]{1,31}$/;

const CreateInput = z.object({
  packId: z.string().regex(PACK_ID_RE, "packId invalide"),
  topic: z.string().min(3).max(160),
  targetTotal: z.number().int().min(50).max(1000).optional(),
  langs: z.array(z.string().length(2)).optional(),
  caps: z
    .object({
      maxCandidates: z.number().int().min(50).max(2000).optional(),
      maxClaudeCallsPerJob: z.number().int().min(5).max(500).optional(),
      maxUsd: z.number().min(1).max(500).optional(),
    })
    .optional(),
});

/** Garantit la présence d'une entrée pack (cachée) dans catalog/index.packs[]. */
async function ensurePackInCatalog(packId: string, uid: string): Promise<void> {
  const ref = db().collection("catalog").doc("index");
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() ?? {} : {};
    const packs: Array<Record<string, unknown>> = Array.isArray(data.packs)
      ? [...data.packs]
      : [];
    if (packs.some((p) => p && p.id === packId)) return;
    packs.push({
      id: packId,
      visible: false,
      bundled: false,
      ordering: packs.length + 100,
      free_choice_eligible: false,
      unlock_cost_cauris: 0,
    });
    tx.set(
      ref,
      {
        packs,
        catalog_version: ((data.catalog_version as number | undefined) ?? 0) + 1,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: uid,
      },
      { merge: true }
    );
  });
}

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
    const langs = parsed.data.langs ?? ["fr"];
    const caps = { ...DEFAULT_CAPS, ...(parsed.data.caps ?? {}) };

    await ensurePackInCatalog(packId, uid);

    const batchesTotal = Math.ceil(targetTotal / DEFAULT_BATCH_SIZE);
    const now = FieldValue.serverTimestamp();
    const ref = jobRef(`${packId}_${Date.now()}`);

    await ref.set({
      packId,
      topic,
      langs,
      status: "queued",
      phase: "plan",
      plan: null,
      progress: {
        targetTotal,
        batchSize: DEFAULT_BATCH_SIZE,
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
