import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";
import { normalize, lettersPoolFromAnswer } from "../utils/normalize";

/**
 * `upsertDevinette` — créer ou éditer une devinette unitaire.
 *
 * Pas de validation strict (laissée à `publishPack` qui agrège). Permet de
 * sauver des drafts en cours de rédaction (champ riddle non finalisé,
 * tags incomplets, etc.).
 *
 * - Si le doc n'existe pas → create avec status='draft'.
 * - Si le doc existe avec status='published' → on n'écrase pas, on crée un
 *   draft superposé : status='draft', draft_version=meta.next_draft_version,
 *   published_version reste l'ancienne valeur. Au prochain publishPack,
 *   le draft remplacera la published.
 * - Si le doc existe déjà en draft → update simple.
 *
 * Auto-calcul : `answer`, `answer_normalized` et `letters_pool` sont toujours
 * recalculés serveur-side (jamais confiance au client). `answer` est stocké
 * SANS accent (= `answer_normalized` en majuscules) pour matcher les lettres
 * de `letters_pool`, elles-mêmes générées depuis la forme normalisée — sinon
 * un mot accentué (ex. « FÊTE ») devient impossible à valider côté client.
 *
 * Guard : `requireEditor` (admin ou editor).
 */

const DevinetteInput = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*_\d{3,4}$/, "id invalide (format: <pack>_NNN)"),
  pack: z.string().min(2),
  country: z.string().length(2),
  answer: z.string().min(4).max(12),
  riddle: z.record(z.string(), z.string()).optional(),
  explanation: z.record(z.string(), z.string()).optional(),
  difficulty: z.number().int().min(1).max(4),
  estimated_time_s: z.number().int().min(5).max(300).optional(),
  tags: z.array(z.string()).max(10).optional(),
});

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  devinette: DevinetteInput,
});

export type UpsertDevinetteOutput = {
  packId: string;
  deviId: string;
  created: boolean;
  status: "draft" | "published";
};

export const upsertDevinette = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<UpsertDevinetteOutput> => {
    const uid = requireEditor(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, devinette } = parsed.data;

    if (devinette.pack !== packId) {
      throw new HttpsError(
        "invalid-argument",
        `devinette.pack "${devinette.pack}" ≠ packId "${packId}".`
      );
    }
    if (!devinette.id.startsWith(`${packId}_`)) {
      throw new HttpsError(
        "invalid-argument",
        `devinette.id "${devinette.id}" doit commencer par "${packId}_".`
      );
    }

    const db = getFirestore();
    const packRef = db.collection("packs").doc(packId);
    const deviRef = packRef.collection("devinettes").doc(devinette.id);

    // Lire l'éventuel doc existant pour décider create vs update
    const existing = await deviRef.get();
    const existingData = existing.exists ? existing.data() : null;

    // Charge meta pour récupérer next_draft_version
    const metaSnap = await packRef.collection("meta").doc("doc").get();
    const nextDraftVersion =
      (metaSnap.data()?.next_draft_version as number | undefined) ?? 1;

    // Recompute serveur-side
    const answerUpper = devinette.answer.toUpperCase();
    const answerNormalized = normalize(answerUpper);
    const lettersPool = lettersPoolFromAnswer(answerNormalized.toUpperCase());

    const now = FieldValue.serverTimestamp();
    const docPayload: Record<string, unknown> = {
      id: devinette.id,
      pack: devinette.pack,
      country: devinette.country,
      answer: answerNormalized.toUpperCase(),
      answer_normalized: answerNormalized,
      letters_pool: lettersPool,
      riddle: devinette.riddle ?? {},
      explanation: devinette.explanation ?? {},
      difficulty: devinette.difficulty,
      estimated_time_s: devinette.estimated_time_s ?? 30,
      tags: devinette.tags ?? [],
      format_version: 3,
      status: "draft",
      draft_version: nextDraftVersion,
      published_version:
        (existingData?.published_version as number | null | undefined) ?? null,
      deleted_at: null,
      updated_at: now,
      updated_by: uid,
    };
    if (!existing.exists) {
      docPayload.created_at = now;
      docPayload.created_by = uid;
    }

    await deviRef.set(docPayload, { merge: true });

    // Bump compteur pending_changes du meta (pour UI)
    await packRef.collection("meta").doc("doc").set(
      {
        id: packId,
        pending_changes: FieldValue.increment(existing.exists ? 0 : 1),
        next_draft_version: nextDraftVersion, // explicite pour cas 1er upsert
        updated_at: now,
        updated_by: uid,
      },
      { merge: true }
    );

    // Audit log léger (pas pour chaque save — on bulk via le compteur)
    // À ré-activer si besoin d'historique fin. Pour l'instant on log au console.
    logger.info("upsertDevinette", {
      uid,
      packId,
      deviId: devinette.id,
      created: !existing.exists,
      draftVersion: nextDraftVersion,
    });

    return {
      packId,
      deviId: devinette.id,
      created: !existing.exists,
      status: "draft",
    };
  }
);
