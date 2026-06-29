/**
 * Pack Creator — cron hebdomadaire de ré-approvisionnement.
 *
 * Chaque lundi 06:00 (Abidjan) : pour chaque pack `pack_topup` activé, enfile un
 * job `phase=topup` de `perWeek` questions (statut plan_approved, plan synthétisé
 * à partir du topic). Le drainer génère + vérifie ces questions et les place en
 * revue (dédupliquées contre les réponses existantes du pack). Après validation,
 * republier le pack via publishPack pour les diffuser.
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";

import { db, jobRef, type ResearchPlan } from "../admin/packJobsShared";

/** Répartit `total` sur les 4 niveaux selon ~30/30/25/15. */
function spreadDifficulty(total: number): Record<string, number> {
  const d1 = Math.round(total * 0.3);
  const d2 = Math.round(total * 0.3);
  const d3 = Math.round(total * 0.25);
  const d4 = Math.max(0, total - d1 - d2 - d3);
  return { "1": d1, "2": d2, "3": d3, "4": d4 };
}

async function enqueueTopupJob(
  packId: string,
  topic: string,
  perWeek: number
): Promise<string> {
  const plan: ResearchPlan = {
    subThemes: [{ name: topic, targetCount: perWeek, tags: [] }],
    difficultyDistribution: spreadDifficulty(perWeek),
    targetTotal: perWeek,
    approvedAt: FieldValue.serverTimestamp(),
    approvedBy: "weeklyPackTopup",
  };
  const now = FieldValue.serverTimestamp();
  const ref = jobRef(`${packId}_topup_${Date.now()}`);
  await ref.set({
    packId,
    topic,
    langs: ["fr"],
    status: "plan_approved",
    phase: "topup",
    plan,
    progress: {
      targetTotal: perWeek,
      batchSize: perWeek,
      nextIndex: 0,
      generated: 0,
      verified: 0,
      rejectedAuto: 0,
      duplicatesDropped: 0,
      batchesDone: 0,
      batchesTotal: 1,
      genByDifficulty: {},
      lastBatchAt: null,
      lastError: null,
      consecutiveErrors: 0,
    },
    caps: { maxCandidates: perWeek + 10, maxClaudeCallsPerJob: 5, maxUsd: 3 },
    usage: { claudeCalls: 0, inputTokens: 0, outputTokens: 0, estUsd: 0 },
    topupEnabled: false,
    topupPerWeek: perWeek,
    lastTopupAt: null,
    createdAt: now,
    createdBy: "weeklyPackTopup",
    updatedAt: now,
  });
  return ref.id;
}

export const weeklyPackTopup = onSchedule(
  {
    schedule: "0 6 * * 1",
    timeZone: "Africa/Abidjan",
    region: "europe-west1",
    timeoutSeconds: 120,
  },
  async () => {
    const snap = await db()
      .collection("pack_topup")
      .where("enabled", "==", true)
      .get();
    if (snap.empty) {
      logger.info("weeklyPackTopup: aucun pack activé.");
      return;
    }
    let count = 0;
    for (const doc of snap.docs) {
      const d = doc.data();
      const packId = d.packId as string;
      const topic = d.topic as string | undefined;
      const perWeek = (d.perWeek as number | undefined) ?? 10;
      if (!packId || !topic) continue;
      const jobId = await enqueueTopupJob(packId, topic, perWeek);
      await doc.ref.set(
        { lastTopupAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
      logger.info("weeklyPackTopup: job créé", { packId, jobId, perWeek });
      count++;
    }
    logger.info("weeklyPackTopup", { packsTopuped: count });
  }
);
