import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { lettersPoolFromAnswer, normalize } from "../utils/normalize";
import { checkAndIncrement } from "../utils/rateLimiter";
import { checkProfanity } from "../utils/profanity";

/**
 * Schéma de validation des soumissions UGC.
 *
 * - `answer` recalculé serveur-side (uppercase, ASCII).
 * - `lettersPool` ignoré du client → recomputed serveur.
 * - `riddle/explanation/proverb` mono-langue à la soumission ; mods
 *   complètent les autres langues plus tard.
 */
const SubmissionInput = z.object({
  world: z.string().min(2).max(64),
  country: z.string().length(2),
  lang: z.string().min(2).max(8),
  answer: z.string().min(3).max(20),
  riddle: z.string().min(20).max(280),
  explanation: z.string().min(30).max(500),
  proverb: z.string().min(5).max(140),
  difficulty: z.number().int().min(1).max(5),
  tags: z.array(z.string().min(1).max(24)).max(5),
  authorDisplayName: z.string().max(40).optional(),
});

export const submitDevinette = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: true,
    cors: true,
  },
  async (req) => {
    const auth = req.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }

    const parsed = SubmissionInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const input = parsed.data;

    const isAnon = !auth.token.firebase?.sign_in_provider ||
      auth.token.firebase.sign_in_provider === "anonymous";
    const dailyLimit = isAnon ? 1 : 5;

    const quota = await checkAndIncrement(
      "users_quota",
      auth.uid,
      dailyLimit
    );
    if (!quota.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        `Quota journalier atteint (${dailyLimit}/jour). Réessayez demain.`
      );
    }

    // Profanity
    const corpus = `${input.riddle}\n${input.explanation}\n${input.proverb}`;
    const prof = checkProfanity(corpus);
    if (prof.flagged) {
      logger.warn("Soumission rejetée (profanité)", {
        uid: auth.uid,
        hits: prof.hits,
      });
      throw new HttpsError(
        "invalid-argument",
        "Termes inappropriés détectés."
      );
    }

    // Recompute serveur — on ne fait JAMAIS confiance au client.
    const answer = input.answer.toUpperCase();
    const answerNormalized = normalize(answer);
    const lettersPool = lettersPoolFromAnswer(answer);

    // Duplicate check (stricte = même monde + même answerNormalized).
    const dup = await getFirestore()
      .collection("submissions")
      .where("world", "==", input.world)
      .where("answerNormalized", "==", answerNormalized)
      .where("status", "in", ["approved", "pending", "pre_approved"])
      .limit(1)
      .get();
    if (!dup.empty) {
      throw new HttpsError(
        "already-exists",
        "Cette réponse existe déjà pour ce monde."
      );
    }

    const ref = getFirestore().collection("submissions").doc();
    const now = FieldValue.serverTimestamp();
    await ref.set({
      authorUid: auth.uid,
      authorDisplayName: input.authorDisplayName ?? null,
      status: "pending",
      lang: input.lang,
      world: input.world,
      country: input.country,
      answer,
      answerNormalized,
      lettersPool,
      riddle: input.riddle,
      explanation: input.explanation,
      proverb: input.proverb,
      difficulty: input.difficulty,
      tags: input.tags,
      createdAt: now,
      reviewedAt: null,
      reviewedBy: null,
    });

    logger.info("Soumission enregistrée", {
      submissionId: ref.id,
      uid: auth.uid,
      world: input.world,
      remainingQuota: quota.remaining,
    });

    return {
      submissionId: ref.id,
      status: "pending" as const,
      remainingQuota: quota.remaining,
    };
  }
);
