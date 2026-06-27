/**
 * Pack Creator — types & helpers Firestore partagés.
 *
 * Collections :
 *   pack_jobs/{jobId}                       — file + état d'un job de création
 *   pack_jobs/{jobId}/candidates/{candId}   — questions générées (staging)
 *   pack_jobs/{jobId}/batches/{batchIndex}  — registre d'idempotence des lots
 *
 * Les questions générées N'ATTERRISSENT PAS directement dans
 * `packs/{packId}/devinettes` : le staging garde le chemin publishPack intact
 * et découple l'id mutable de l'id final `<packId>_NNN`.
 */
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { normalize, lettersPoolFromAnswer } from "../utils/normalize";

export const PACK_ID_RE = /^[a-z][a-z0-9_]{1,31}$/;

export const JOBS = "pack_jobs";
export const CANDIDATES = "candidates";
export const BATCHES = "batches";

export const DEFAULT_TARGET_TOTAL = 500;
export const DEFAULT_BATCH_SIZE = 25;
export const TOPUP_PER_WEEK = 10;

export const DEFAULT_CAPS = {
  maxCandidates: 600,
  maxClaudeCallsPerJob: 80,
  maxUsd: 25,
};

export type JobStatus =
  | "queued"
  | "planning"
  | "plan_review"
  | "plan_approved"
  | "generating"
  | "review"
  | "ready"
  | "published"
  | "failed"
  | "cancelled";

export type SubTheme = { name: string; targetCount: number; tags: string[] };

export type ResearchPlan = {
  subThemes: SubTheme[];
  difficultyDistribution: Record<string, number>; // clés "1".."4"
  targetTotal: number;
  rationale?: string;
  approvedAt?: unknown;
  approvedBy?: string | null;
};

export type CandidateData = {
  candId: string;
  jobId: string;
  packId: string;
  batchIndex: number;
  country: string;
  answer: string;
  answerNormalized: string;
  riddleFr: string;
  explanationFr: string;
  difficulty: number;
  estimatedTimeS: number;
  tags: string[];
  subTheme: string;
  verification: {
    verdict: "pass" | "uncertain" | "fail" | "pending";
    confidence: number;
    sources: Array<{ title: string; url: string }>;
    notes: string;
  };
  reviewStatus: "pending" | "approved" | "rejected";
  /** Pack de destination courant (= packId, ou autre pack si réaffectée). */
  effectivePackId?: string;
  targetPackId?: string | null;
  promotedDeviId?: string | null;
  promotedPackId?: string | null;
  rejectionReason?: string | null;
  reviewedBy?: string | null;
};

export function db() {
  return getFirestore();
}

export function jobRef(jobId: string) {
  return db().collection(JOBS).doc(jobId);
}

export function candidatesRef(jobId: string) {
  return jobRef(jobId).collection(CANDIDATES);
}

export function batchRef(jobId: string, batchIndex: number) {
  return jobRef(jobId).collection(BATCHES).doc(String(batchIndex));
}

/** estimated_time_s par défaut selon la difficulté (1→25 … 4→55). */
export function estimatedTimeForDifficulty(difficulty: number): number {
  switch (difficulty) {
    case 1:
      return 25;
    case 2:
      return 30;
    case 3:
      return 40;
    default:
      return 55;
  }
}

/** Validation mécanique d'un mot-réponse (mêmes règles que validatePackDraft). */
export function isValidAnswer(answer: string): boolean {
  if (typeof answer !== "string") return false;
  if (answer.length < 4 || answer.length > 12) return false;
  return /^[A-ZÀÁÂÄÇÈÉÊËÌÍÎÏÒÓÔÖÙÚÛÜÑŸ]+$/.test(answer);
}

/** Vérifie que l'énigme ne contient pas la réponse (normalisée). */
export function riddleHidesAnswer(riddleFr: string, answer: string): boolean {
  if (!riddleFr || !riddleFr.trim()) return false;
  const na = normalize(answer);
  if (na.length < 4) return true;
  return !normalize(riddleFr).includes(na);
}

/**
 * Réponses (normalisées) déjà publiées/en draft pour un pack
 * (`packs/{packId}/devinettes`). Les réponses déjà générées dans le job sont
 * suivies à part dans `progress.usedAnswers` (évite de re-scanner la collection
 * de candidats à chaque lot — cf drainPackJobs).
 */
export async function loadPackAnswerSet(packId: string): Promise<Set<string>> {
  const set = new Set<string>();
  const deviSnap = await db()
    .collection("packs")
    .doc(packId)
    .collection("devinettes")
    .select("answer_normalized")
    .get();
  for (const d of deviSnap.docs) {
    const norm = d.data().answer_normalized as string | undefined;
    if (norm) set.add(norm);
  }
  return set;
}

/** Garantit la présence d'une entrée pack (cachée) dans catalog/index.packs[]. */
export async function ensurePackInCatalog(
  packId: string,
  uid: string
): Promise<void> {
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

/** Tags whitelistés (`catalog/tags_whitelist.tags`), cache mémoire 60 s. */
let _tagsCache: { tags: string[]; expiresAt: number } | null = null;
export async function loadTagsWhitelist(): Promise<string[]> {
  const now = Date.now();
  if (_tagsCache && _tagsCache.expiresAt > now) return _tagsCache.tags;
  const snap = await db().collection("catalog").doc("tags_whitelist").get();
  const raw = snap.exists ? snap.data() : null;
  const list = Array.isArray(raw?.tags) ? raw!.tags : [];
  const tags = list.filter((t: unknown): t is string => typeof t === "string");
  _tagsCache = { tags, expiresAt: now + 60_000 };
  return tags;
}

/** Construit le payload devinette v3 (status=draft) à partir d'un candidat. */
export function devinetteFromCandidate(
  cand: CandidateData,
  deviId: string,
  uid: string,
  nextDraftVersion: number,
  now: unknown,
  existingPublishedVersion: number | null
): Record<string, unknown> {
  const answerUpper = cand.answer.toUpperCase();
  const answerNormalized = normalize(answerUpper);
  const lettersPool = lettersPoolFromAnswer(answerNormalized.toUpperCase());
  return {
    id: deviId,
    pack: cand.packId,
    country: cand.country || "ci",
    answer: answerUpper,
    answer_normalized: answerNormalized,
    letters_pool: lettersPool,
    riddle: { fr: cand.riddleFr },
    explanation: { fr: cand.explanationFr },
    difficulty: cand.difficulty,
    estimated_time_s: cand.estimatedTimeS,
    tags: cand.tags ?? [],
    format_version: 3,
    status: "draft",
    draft_version: nextDraftVersion,
    published_version: existingPublishedVersion,
    deleted_at: null,
    updated_at: now,
    updated_by: uid,
    created_at: now,
    created_by: uid,
    source_job: cand.jobId,
  };
}
