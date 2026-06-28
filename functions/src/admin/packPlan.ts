import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import {
  jobRef,
  loadTagsWhitelist,
  DEFAULT_BATCH_SIZE,
  type ResearchPlan,
} from "./packJobsShared";
import { generateStructured, AI_SECRETS } from "../ai/provider";
import { logUsage } from "../ai/usage";
import {
  packSystemPrefix,
  planSchema,
  planUserPrompt,
} from "../ai/prompts";

/**
 * Pack Creator — phase (a) : plan de recherche.
 *
 * - generateResearchPlan : Claude propose sous-thèmes + répartition difficulté
 *   → status `plan_review`.
 * - approveResearchPlan  : l'admin valide/édite → status `plan_approved`
 *   (le drainer enchaîne sur la génération).
 *
 * Guard : requireAdmin.
 */

const SECRET_OPTS = {
  region: "europe-west1" as const,
  enforceAppCheck: false,
  cors: true,
  secrets: AI_SECRETS,
  timeoutSeconds: 300,
  memory: "512MiB" as const,
};

const JobIdInput = z.object({ jobId: z.string().min(3).max(120) });

type PlanResult = {
  subThemes: Array<{ name: string; targetCount: number; tags: string[] }>;
  difficultyDistribution: Record<string, number>;
  rationale: string;
};

export const generateResearchPlan = onCall(
  SECRET_OPTS,
  async (req): Promise<{ ok: true; plan: ResearchPlan }> => {
    const uid = requireAdmin(req.auth);
    const parsed = JobIdInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const ref = jobRef(parsed.data.jobId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Job introuvable.");
    const job = snap.data() ?? {};
    const topic = job.topic as string;
    const targetTotal = (job.progress?.targetTotal as number) ?? 500;

    const tags = await loadTagsWhitelist();

    await ref.set(
      { status: "planning", updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );

    let result: PlanResult;
    let usage;
    try {
      const out = await generateStructured<PlanResult>({
        system: [{ text: packSystemPrefix(topic, tags), cache: true }],
        user: planUserPrompt(topic, targetTotal),
        schema: planSchema(),
        effort: "high",
      });
      result = out.data;
      usage = out.usage;
    } catch (e) {
      await ref.set(
        {
          status: "queued",
          progress: { lastError: (e as Error).message },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      throw new HttpsError("internal", `Plan Claude échoué: ${(e as Error).message}`);
    }

    logUsage("plan", usage);

    const plan: ResearchPlan = {
      subThemes: result.subThemes ?? [],
      difficultyDistribution: result.difficultyDistribution ?? {},
      targetTotal,
      rationale: result.rationale ?? "",
      approvedAt: null,
      approvedBy: null,
    };

    await ref.set(
      {
        status: "plan_review",
        plan,
        usage: {
          claudeCalls: FieldValue.increment(1),
          inputTokens: FieldValue.increment(usage.inputTokens),
          outputTokens: FieldValue.increment(usage.outputTokens),
          estUsd: FieldValue.increment(usage.estUsd),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("generateResearchPlan", { uid, jobId: ref.id, targetTotal });
    return { ok: true, plan };
  }
);

const ApproveInput = z.object({
  jobId: z.string().min(3).max(120),
  plan: z.object({
    subThemes: z
      .array(
        z.object({
          name: z.string().min(1),
          targetCount: z.number().int().min(0).max(1000),
          tags: z.array(z.string()).max(20),
        })
      )
      .min(1)
      .max(40),
    difficultyDistribution: z.object({
      "1": z.number().int().min(0).max(1000),
      "2": z.number().int().min(0).max(1000),
      "3": z.number().int().min(0).max(1000),
      "4": z.number().int().min(0).max(1000),
    }),
    targetTotal: z.number().int().min(50).max(1000),
  }),
});

export const approveResearchPlan = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true }> => {
    const uid = requireAdmin(req.auth);
    const parsed = ApproveInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { jobId, plan } = parsed.data;
    const ref = jobRef(jobId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Job introuvable.");

    const targetTotal = plan.targetTotal;
    // Conserve la taille de lot du job (50 en mode éco quota, sinon défaut).
    const batchSize =
      (snap.data()?.progress?.batchSize as number | undefined) ?? DEFAULT_BATCH_SIZE;
    const batchesTotal = Math.ceil(targetTotal / batchSize);

    await ref.set(
      {
        status: "plan_approved",
        phase: "generate",
        plan: {
          subThemes: plan.subThemes,
          difficultyDistribution: plan.difficultyDistribution,
          targetTotal,
          approvedAt: FieldValue.serverTimestamp(),
          approvedBy: uid,
        },
        progress: { targetTotal, batchesTotal },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("approveResearchPlan", { uid, jobId, targetTotal });
    return { ok: true };
  }
);
