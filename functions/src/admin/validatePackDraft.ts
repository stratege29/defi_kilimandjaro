import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";
import { normalize, lettersPoolFromAnswer } from "../utils/normalize";

/**
 * `validatePackDraft` — vérifie qu'un pack en édition est prêt à être publié.
 *
 * Lit `packs/{packId}/devinettes` (status ∈ {draft, published}, deleted_at null)
 * et applique les 13 règles strictes du format v3 documentées dans
 * `docs/backoffice_schema.md` §8.
 *
 * N'écrit rien. Pas de side effect. Idempotent.
 *
 * Appelée :
 *  - par `publishPack` avant tout upload (bloque si valid=false)
 *  - par l'UI admin (bouton "Valider" dans l'éditeur, pour pré-checker)
 *
 * Guard : `requireEditor` (admin ou editor).
 *
 * @param packId - identifiant du pack (ex: "culture_ci")
 * @returns       structure detaillee des erreurs/warnings
 */

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
});

export type ValidationIssue = {
  deviId: string;
  code: string;
  message: string;
};

export type ValidatePackDraftOutput = {
  valid: boolean;
  total: number;
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
};

/**
 * Tags whitelistés — chargés depuis Firestore `catalog/tags_whitelist.tags`.
 * Mis en cache 60s pour éviter une lecture Firestore par validation.
 */
let _tagsCache: { tags: Set<string>; expiresAt: number } | null = null;
const TAGS_CACHE_TTL_MS = 60_000;

async function loadTagsWhitelist(): Promise<Set<string>> {
  const now = Date.now();
  if (_tagsCache && _tagsCache.expiresAt > now) {
    return _tagsCache.tags;
  }
  const snap = await getFirestore()
    .collection("catalog")
    .doc("tags_whitelist")
    .get();
  const raw = snap.exists ? snap.data() : null;
  const list = Array.isArray(raw?.tags) ? raw!.tags : [];
  const set = new Set<string>(list.filter((t: unknown) => typeof t === "string"));
  _tagsCache = { tags: set, expiresAt: now + TAGS_CACHE_TTL_MS };
  return set;
}

/** Réinitialise le cache (exposé pour les tests). */
export function _resetTagsCacheForTest(): void {
  _tagsCache = null;
}

// ---------------------------------------------------------------------------
// Règles de validation unitaire
// ---------------------------------------------------------------------------

type Devinette = {
  id?: unknown;
  pack?: unknown;
  country?: unknown;
  answer?: unknown;
  answer_normalized?: unknown;
  letters_pool?: unknown;
  riddle?: unknown;
  explanation?: unknown;
  difficulty?: unknown;
  estimated_time_s?: unknown;
  tags?: unknown;
  format_version?: unknown;
  status?: unknown;
  deleted_at?: unknown;
};

/**
 * Applique les 13 règles à une devinette unique.
 * Retourne (errors, warnings). Ne mute pas l'input.
 */
function validateDevinette(
  d: Devinette,
  packId: string,
  tagsWhitelist: Set<string>,
  answersSeenInPack: Map<string, string> // answer -> first deviId
): { errors: ValidationIssue[]; warnings: ValidationIssue[] } {
  const deviId = typeof d.id === "string" ? d.id : "<unknown>";
  const errors: ValidationIssue[] = [];
  const warnings: ValidationIssue[] = [];

  const push = (
    bucket: ValidationIssue[],
    code: string,
    message: string
  ): void => {
    bucket.push({ deviId, code, message });
  };

  // 1. format_version === 3
  if (d.format_version !== 3) {
    push(errors, "BAD_FORMAT_VERSION", "format_version doit être 3.");
  }

  // 2. id : format <packId>_NNN (3 ou 4 chiffres)
  if (typeof d.id !== "string") {
    push(errors, "MISSING_ID", "id absent ou non string.");
  } else {
    const idRe = new RegExp(`^${escapeRegex(packId)}_\\d{3,4}$`);
    if (!idRe.test(d.id)) {
      push(
        errors,
        "BAD_ID_FORMAT",
        `id "${d.id}" ne respecte pas le format ${packId}_NNN.`
      );
    }
  }

  // 3. pack === packId
  if (d.pack !== packId) {
    push(
      errors,
      "WRONG_PACK",
      `pack "${String(d.pack)}" ≠ contexte "${packId}".`
    );
  }

  // 4. country : 2 lettres
  if (typeof d.country !== "string" || !/^[a-z]{2}$/.test(d.country)) {
    push(errors, "BAD_COUNTRY", "country doit être un code ISO 2 lettres.");
  }

  // 5. answer : 4-12 chars, lettres A-Z + caractères tolérés (é, è, à, ï, ç…)
  if (typeof d.answer !== "string") {
    push(errors, "MISSING_ANSWER", "answer absent.");
  } else {
    const a = d.answer;
    if (a.length < 4 || a.length > 12) {
      push(
        errors,
        "ANSWER_LENGTH",
        `answer "${a}" doit faire 4-12 caractères (actuel: ${a.length}).`
      );
    }
    // Caractères : majuscules ASCII + accents tolérés (NFD-aware)
    if (!/^[A-ZÀÁÂÄÇÈÉÊËÌÍÎÏÒÓÔÖÙÚÛÜÑŸ]+$/.test(a)) {
      push(
        errors,
        "ANSWER_CHARS",
        `answer "${a}" contient des caractères non autorisés (lettres majuscules + accents uniquement).`
      );
    }

    // 6. answer_normalized doit matcher normalize(answer)
    const expectedNorm = normalize(a);
    if (d.answer_normalized !== expectedNorm) {
      push(
        errors,
        "BAD_NORMALIZED",
        `answer_normalized "${String(d.answer_normalized)}" ≠ "${expectedNorm}".`
      );
    }

    // 7. letters_pool : multiset des lettres ASCII de answer
    const expectedPool = lettersPoolFromAnswer(normalize(a).toUpperCase());
    if (!arraysEqualUnordered(d.letters_pool, expectedPool)) {
      push(
        errors,
        "BAD_LETTERS_POOL",
        `letters_pool ne correspond pas aux lettres de answer (attendu: [${expectedPool.join(",")}]).`
      );
    }

    // 11. doublons answer dans le pack
    const norm = normalize(a);
    const existing = answersSeenInPack.get(norm);
    if (existing && existing !== deviId) {
      push(
        errors,
        "DUPLICATE_ANSWER",
        `answer "${a}" déjà utilisée par ${existing}.`
      );
    } else {
      answersSeenInPack.set(norm, deviId);
    }
  }

  // 8. riddle.fr : non vide, ne contient pas la réponse
  const riddle = d.riddle as Record<string, unknown> | undefined;
  const riddleFr = typeof riddle?.fr === "string" ? riddle.fr : "";
  if (!riddleFr.trim()) {
    push(errors, "MISSING_RIDDLE_FR", "riddle.fr absent ou vide.");
  } else if (typeof d.answer === "string") {
    const normRiddle = normalize(riddleFr);
    const normAnswer = normalize(d.answer);
    if (normAnswer.length >= 4 && normRiddle.includes(normAnswer)) {
      push(
        errors,
        "ANSWER_IN_RIDDLE",
        `riddle.fr contient la réponse "${d.answer}".`
      );
    }
  }

  // 9. explanation.fr : non vide (warning si vide)
  const explanation = d.explanation as Record<string, unknown> | undefined;
  const explanationFr =
    typeof explanation?.fr === "string" ? explanation.fr : "";
  if (!explanationFr.trim()) {
    push(warnings, "MISSING_EXPLANATION_FR", "explanation.fr vide.");
  }

  // 10. tags : tous dans la whitelist
  if (!Array.isArray(d.tags)) {
    push(errors, "MISSING_TAGS", "tags doit être un tableau.");
  } else if (tagsWhitelist.size > 0) {
    const invalid = d.tags.filter(
      (t: unknown) => typeof t !== "string" || !tagsWhitelist.has(t)
    );
    if (invalid.length > 0) {
      push(
        errors,
        "TAGS_NOT_WHITELISTED",
        `tags hors whitelist: [${invalid.join(",")}].`
      );
    }
  }

  // 12. difficulty ∈ {1,2,3,4}
  if (typeof d.difficulty !== "number" || ![1, 2, 3, 4].includes(d.difficulty)) {
    push(
      errors,
      "BAD_DIFFICULTY",
      `difficulty "${String(d.difficulty)}" doit être 1, 2, 3 ou 4.`
    );
  }

  // 13. estimated_time_s : 10-120 (warning hors range)
  if (typeof d.estimated_time_s !== "number") {
    push(warnings, "MISSING_TIME", "estimated_time_s absent.");
  } else if (d.estimated_time_s < 10 || d.estimated_time_s > 120) {
    push(
      warnings,
      "TIME_OUT_OF_RANGE",
      `estimated_time_s=${d.estimated_time_s} hors range [10-120].`
    );
  }

  // Bonus : si status=draft, deleted_at doit être null
  if (d.status === "draft" && d.deleted_at != null) {
    push(
      errors,
      "DRAFT_DELETED",
      "Une devinette en draft ne peut pas être deleted_at."
    );
  }

  return { errors, warnings };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function arraysEqualUnordered(a: unknown, b: string[]): boolean {
  if (!Array.isArray(a)) return false;
  if (a.length !== b.length) return false;
  const aCopy = [...a].sort();
  const bCopy = [...b].sort();
  for (let i = 0; i < aCopy.length; i++) {
    if (aCopy[i] !== bCopy[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------

/**
 * Logique pure de validation — exposée pour les tests unitaires.
 * Prend une liste de devinettes en mémoire + tags whitelist, retourne le rapport.
 */
export function validatePackDraftPure(
  packId: string,
  devinettes: Devinette[],
  tagsWhitelist: Set<string>
): ValidatePackDraftOutput {
  const errors: ValidationIssue[] = [];
  const warnings: ValidationIssue[] = [];
  const answersSeenInPack = new Map<string, string>();

  for (const d of devinettes) {
    const res = validateDevinette(d, packId, tagsWhitelist, answersSeenInPack);
    errors.push(...res.errors);
    warnings.push(...res.warnings);
  }

  return {
    valid: errors.length === 0,
    total: devinettes.length,
    errors,
    warnings,
  };
}

export const validatePackDraft = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    const uid = requireEditor(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId } = parsed.data;

    // Lit toutes les devinettes du pack en draft ou published, non supprimées.
    // À 500 devinettes par pack, 1 query Firestore tient en <500 ms.
    const snap = await getFirestore()
      .collection("packs")
      .doc(packId)
      .collection("devinettes")
      .where("status", "in", ["draft", "published"])
      .get();

    const devinettes: Devinette[] = [];
    for (const doc of snap.docs) {
      const data = doc.data();
      if (data.deleted_at != null) continue;
      devinettes.push(data as Devinette);
    }

    if (devinettes.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        `Pack "${packId}" vide — rien à valider.`
      );
    }

    const tagsWhitelist = await loadTagsWhitelist();

    const result = validatePackDraftPure(packId, devinettes, tagsWhitelist);

    logger.info("validatePackDraft", {
      uid,
      packId,
      total: result.total,
      valid: result.valid,
      errorCount: result.errors.length,
      warningCount: result.warnings.length,
    });

    return result;
  }
);
