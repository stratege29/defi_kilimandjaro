/**
 * Pack Creator — drainer planifié (génération + vérification par lot).
 *
 * Toutes les 2 min : prend le job actif le plus ancien
 * (status ∈ plan_approved|generating), traite UN lot (25 questions) :
 *   1. génération structurée (quota par niveau + dédup) via Claude
 *   2. checks mécaniques serveur (longueur/charset/énigme≠réponse) + dédup
 *   3. vérification/sourcing via Claude + recherche web
 *   4. écrit les candidats en staging, met à jour progress/registre
 * Quand tous les lots sont faits → status `review`.
 *
 * Idempotence : registre `batches/{batchIndex}` + curseur progress.nextIndex.
 * Reprise : un tick qui échoue laisse batchesDone inchangé (rejoue l'index).
 * Caps coût + circuit breaker (consecutiveErrors >= 5 → failed).
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import {
  generateStructured,
  verifyBatch,
  AI_SECRETS,
  type VerifyResult,
} from "./provider";
import { logUsage, type AiUsage } from "./usage";
import { packSystemPrefix, batchSchema, batchUserPrompt } from "./prompts";
import {
  jobRef,
  db,
  batchRef,
  candidatesRef,
  loadPackAnswerSet,
  loadTagsWhitelist,
  isValidAnswer,
  riddleHidesAnswer,
  estimatedTimeForDifficulty,
  type ResearchPlan,
} from "../admin/packJobsShared";
import { normalize } from "../utils/normalize";

type GenQuestion = {
  answer: string;
  country: string;
  riddleFr: string;
  explanationFr: string;
  difficulty: number;
  subTheme: string;
  tags: string[];
};

// Le lease DOIT dépasser le timeout de la fonction (540 s) pour qu'un lot
// encore en cours ne soit pas re-réclamé par le tick suivant (sinon double
// écriture des candidats avec un curseur `generated` périmé).
const LEASE_MS = 12 * 60 * 1000;
const CRITICAL_ERRORS = 5;

/** Tente de réserver le lot batchIndex (lease transactionnel). */
async function claimBatch(jobId: string, batchIndex: number): Promise<boolean> {
  const ref = batchRef(jobId, batchIndex);
  return db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const d = s.exists ? s.data() : null;
    if (d?.state === "done") return false;
    const now = Date.now();
    const lease = (d?.leaseUntil as Timestamp | undefined)?.toMillis?.() ?? 0;
    if (d?.state === "running" && lease > now) return false;
    tx.set(
      ref,
      {
        batchIndex,
        state: "running",
        attempts: FieldValue.increment(1),
        leaseUntil: Timestamp.fromMillis(now + LEASE_MS),
        error: null,
      },
      { merge: true }
    );
    return true;
  });
}

function remainingByDifficulty(
  plan: ResearchPlan,
  gen: Record<string, number>
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const d of ["1", "2", "3", "4"]) {
    const target = plan.difficultyDistribution?.[d] ?? 0;
    out[d] = Math.max(0, target - (gen[d] ?? 0));
  }
  return out;
}

/** Traite un lot de génération+vérification pour un job. Retourne true si avancé. */
async function processBatch(jobId: string): Promise<string> {
  const ref = jobRef(jobId);
  const snap = await ref.get();
  if (!snap.exists) return "gone";
  const job = snap.data() ?? {};
  const status = job.status as string;
  if (status !== "plan_approved" && status !== "generating") return "inactive";

  const caps = job.caps ?? {};
  const usage = job.usage ?? {};
  if (
    (usage.claudeCalls ?? 0) >= (caps.maxClaudeCallsPerJob ?? 80) ||
    (usage.estUsd ?? 0) >= (caps.maxUsd ?? 25)
  ) {
    await ref.set(
      {
        status: "failed",
        progress: { lastError: "cap_exceeded" },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return "cap";
  }

  const plan = job.plan as ResearchPlan | undefined;
  if (!plan) {
    await ref.set(
      { status: "failed", progress: { lastError: "no_plan" } },
      { merge: true }
    );
    return "noplan";
  }

  const progress = job.progress ?? {};
  const batchesDone: number = progress.batchesDone ?? 0;
  const batchesTotal: number = progress.batchesTotal ?? 1;
  const targetTotal: number = progress.targetTotal ?? 500;
  const generated: number = progress.generated ?? 0;
  const batchSize: number = progress.batchSize ?? 25;

  // Fin de génération → bascule en revue.
  if (batchesDone >= batchesTotal || generated >= targetTotal) {
    await ref.set(
      { status: "review", updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return "review";
  }

  if (status === "plan_approved") {
    await ref.set({ status: "generating" }, { merge: true });
  }

  const batchIndex = batchesDone;
  const claimed = await claimBatch(jobId, batchIndex);
  if (!claimed) return "leased";

  const packId = job.packId as string;
  const topic = job.topic as string;
  const count = Math.min(batchSize, targetTotal - generated);

  try {
    const tags = await loadTagsWhitelist();
    // Réponses interdites = devinettes déjà publiées du pack + réponses déjà
    // générées dans ce job (suivies sur le job, pas de re-scan des candidats).
    const packAnswers = await loadPackAnswerSet(packId);
    const usedAnswers: string[] = Array.isArray(progress.usedAnswers)
      ? progress.usedAnswers
      : [];
    const forbidden = new Set<string>([...packAnswers, ...usedAnswers]);
    const forbiddenSample = Array.from(forbidden).slice(-400);
    const genStat: Record<string, number> = progress.genByDifficulty ?? {};

    // 1. Génération structurée.
    const gen = await generateStructured<{ questions: GenQuestion[] }>({
      system: [{ text: packSystemPrefix(topic, tags), cache: true }],
      user: batchUserPrompt({
        count,
        remainingByDifficulty: remainingByDifficulty(plan, genStat),
        forbiddenAnswers: forbiddenSample,
        subThemes: plan.subThemes.map((s) => ({ name: s.name, tags: s.tags })),
      }),
      schema: batchSchema(),
      effort: "high",
      maxTokens: 16000,
    });
    logUsage(`gen:${jobId}:${batchIndex}`, gen.usage);

    // 2. Checks mécaniques + dédup.
    const accepted: GenQuestion[] = [];
    let rejectedAuto = 0;
    let duplicatesDropped = 0;
    const seen = new Set(forbidden);
    for (const q of gen.data.questions ?? []) {
      const answer = (q.answer ?? "").toUpperCase().trim();
      const norm = normalize(answer);
      if (!isValidAnswer(answer) || !riddleHidesAnswer(q.riddleFr, answer)) {
        rejectedAuto++;
        continue;
      }
      if (![1, 2, 3, 4].includes(q.difficulty)) {
        rejectedAuto++;
        continue;
      }
      if (seen.has(norm)) {
        duplicatesDropped++;
        continue;
      }
      seen.add(norm);
      accepted.push({ ...q, answer });
    }

    // 3. Vérification / sourcing (Wikipedia → grounding).
    let verifications: VerifyResult[] = [];
    let verifyUsage: AiUsage | null = null;
    let verifyCalls = 0;
    if (accepted.length > 0) {
      const items = accepted.map((q, i) => ({
        index: i,
        answer: q.answer,
        riddleFr: q.riddleFr,
        explanationFr: q.explanationFr,
      }));
      const v = await verifyBatch(items);
      verifications = v.results;
      verifyUsage = v.usage;
      verifyCalls = v.calls;
      logUsage(`verify:${jobId}:${batchIndex}`, v.usage);
    }
    const verdictByIndex = new Map<number, VerifyResult>();
    for (const r of verifications) verdictByIndex.set(r.index, r);

    // 4. Écriture des candidats (staging).
    const writer = db().batch();
    const genDelta: Record<string, number> = { "1": 0, "2": 0, "3": 0, "4": 0 };
    let verifiedPass = 0;
    accepted.forEach((q, i) => {
      const globalIndex = generated + i;
      const candId = `cand_${String(globalIndex).padStart(4, "0")}`;
      const v = verdictByIndex.get(i);
      if (v?.verdict === "pass") verifiedPass++;
      genDelta[String(q.difficulty)] = (genDelta[String(q.difficulty)] ?? 0) + 1;
      writer.set(candidatesRef(jobId).doc(candId), {
        candId,
        jobId,
        packId,
        effectivePackId: packId, // pack de destination (modifiable par réaffectation)
        batchIndex,
        country: q.country || "ci",
        answer: q.answer,
        answerNormalized: normalize(q.answer),
        riddleFr: q.riddleFr,
        explanationFr: q.explanationFr,
        difficulty: q.difficulty,
        estimatedTimeS: estimatedTimeForDifficulty(q.difficulty),
        tags: Array.isArray(q.tags) ? q.tags.slice(0, 10) : [],
        subTheme: q.subTheme ?? "",
        verification: {
          verdict: v?.verdict ?? "uncertain",
          confidence: v?.confidence ?? 0,
          sources: v?.sources ?? [],
          notes: v?.notes ?? "",
        },
        reviewStatus: "pending",
        reviewedBy: null,
        reviewedAt: null,
        rejectionReason: null,
        promotedDeviId: null,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    await writer.commit();

    // Progress + usage + registre.
    const newGenByDifficulty: Record<string, number> = { ...genStat };
    for (const d of ["1", "2", "3", "4"]) {
      newGenByDifficulty[d] = (newGenByDifficulty[d] ?? 0) + (genDelta[d] ?? 0);
    }
    const newGenerated = generated + accepted.length;
    const acceptedNorms = accepted.map((q) => normalize(q.answer));
    const totalUsd =
      gen.usage.estUsd + (verifyUsage?.estUsd ?? 0);
    const totalIn = gen.usage.inputTokens + (verifyUsage?.inputTokens ?? 0);
    const totalOut = gen.usage.outputTokens + (verifyUsage?.outputTokens ?? 0);
    // 1 appel génération + N appels vérification (verifyHybrid peut en faire 2
    // : structuré + repli grounding).
    const callCount = 1 + verifyCalls;

    const progressUpdate: Record<string, unknown> = {
      batchesDone: batchesDone + 1,
      generated: newGenerated,
      nextIndex: newGenerated,
      verified: FieldValue.increment(verifiedPass),
      rejectedAuto: FieldValue.increment(rejectedAuto),
      duplicatesDropped: FieldValue.increment(duplicatesDropped),
      genByDifficulty: newGenByDifficulty,
      lastBatchAt: FieldValue.serverTimestamp(),
      lastError: null,
      consecutiveErrors: 0,
    };
    if (acceptedNorms.length > 0) {
      progressUpdate.usedAnswers = FieldValue.arrayUnion(...acceptedNorms);
    }

    await ref.set(
      {
        status: "generating",
        progress: progressUpdate,
        usage: {
          claudeCalls: FieldValue.increment(callCount),
          inputTokens: FieldValue.increment(totalIn),
          outputTokens: FieldValue.increment(totalOut),
          estUsd: FieldValue.increment(totalUsd),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await batchRef(jobId, batchIndex).set(
      { state: "done", finishedAt: FieldValue.serverTimestamp(), error: null },
      { merge: true }
    );

    // Dernier lot → revue.
    if (batchesDone + 1 >= batchesTotal || newGenerated >= targetTotal) {
      await ref.set(
        { status: "review", updatedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
    }
    return "ok";
  } catch (e) {
    const msg = (e as Error).message;
    // Erreur de quota / rate-limit IA : « douce ». On NE déclenche PAS le circuit
    // breaker — le quota se libère (par minute ou par jour) et le tick suivant
    // rejoue le même lot. Le job reste en génération au lieu d'échouer.
    const isRate = /429|resource_exhausted|quota|rate.?limit/i.test(msg);
    await batchRef(jobId, batchIndex).set(
      { state: isRate ? "pending" : "failed", leaseUntil: null, error: msg },
      { merge: true }
    );
    if (isRate) {
      await ref.set(
        {
          status: "generating",
          progress: {
            lastError: `Quota IA atteint — reprise auto. ${msg.slice(0, 160)}`,
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.warn("drainPackJobs:rate-limited", { jobId, batchIndex });
      return "rate-limited";
    }
    const errors = (progress.consecutiveErrors ?? 0) + 1;
    await ref.set(
      {
        status: errors >= CRITICAL_ERRORS ? "failed" : "generating",
        progress: {
          consecutiveErrors: FieldValue.increment(1),
          lastError: msg,
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logger.error("drainPackJobs:batch", { jobId, batchIndex, error: msg });
    return "error";
  }
}

/** Choisit le job actif le plus ancien (tri en code, index-free). */
async function pickActiveJob(): Promise<string | null> {
  const snap = await db()
    .collection("pack_jobs")
    .where("status", "in", ["plan_approved", "generating"])
    .get();
  if (snap.empty) return null;
  const docs = snap.docs
    .map((d) => ({
      id: d.id,
      at:
        (d.data().updatedAt as { toMillis?: () => number })?.toMillis?.() ?? 0,
    }))
    .sort((a, b) => a.at - b.at);
  return docs[0]?.id ?? null;
}

export const drainPackJobs = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "Africa/Abidjan",
    region: "europe-west1",
    secrets: AI_SECRETS,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const jobId = await pickActiveJob();
    if (!jobId) {
      logger.debug("drainPackJobs: aucun job actif.");
      return;
    }
    const result = await processBatch(jobId);
    logger.info("drainPackJobs", { jobId, result });
  }
);
