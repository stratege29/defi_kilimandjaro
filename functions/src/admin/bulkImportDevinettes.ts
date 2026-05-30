import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";
import { normalize, lettersPoolFromAnswer } from "../utils/normalize";

/**
 * `bulkImportDevinettes` — import en masse de devinettes en draft.
 *
 * Use case principal : intégrer un batch Gemini ou un export JSON sans
 * passer par le CLI `tool/seed_content_packs.dart`. L'UI admin colle un
 * tableau JSON, on l'importe.
 *
 * Modes :
 *  - `append`  : ajoute les devinettes ; remplace celles avec le même id en
 *                draft. Les published existantes non-touchées restent.
 *  - `replace` : marque tous les drafts existants en deleted, puis insert.
 *                (Les published restent published — elles seront archivées
 *                au prochain publish si non-réinsérées.)
 *
 * Validation : minimaliste (juste la forme Zod). La validation strict
 * format v3 est faite par `publishPack` à la publication. Cela permet
 * d'importer des drafts partiels et de les corriger ensuite dans l'UI.
 *
 * Performance : batches Firestore de 400 (limite 500 ops/batch). Pour 500
 * devinettes ~2 batches, ~1-2 sec end-to-end.
 *
 * Guard : `requireEditor` (admin ou editor).
 */

const DevinetteInput = z.object({
  id: z.string().regex(/^[a-z][a-z0-9_]*_\d{3,4}$/, "id invalide"),
  pack: z.string().min(2).optional(),
  country: z.string().length(2).optional(),
  answer: z.string().min(4).max(12),
  riddle: z.record(z.string(), z.string()).optional(),
  explanation: z.record(z.string(), z.string()).optional(),
  difficulty: z.number().int().min(1).max(4),
  estimated_time_s: z.number().int().min(5).max(300).optional(),
  tags: z.array(z.string()).max(10).optional(),
  // letters_pool et answer_normalized sont ignorés (recalculés serveur)
});

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  mode: z.enum(["append", "replace"]).default("append"),
  devinettes: z.array(z.unknown()).min(1).max(1000),
});

export type BulkImportRejection = {
  index: number;
  id?: string;
  error: string;
};

export type BulkImportOutput = {
  packId: string;
  mode: "append" | "replace";
  accepted: number;
  rejected: BulkImportRejection[];
  draftVersion: number;
};

const BATCH_SIZE = 400;

export const bulkImportDevinettes = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (req): Promise<BulkImportOutput> => {
    const uid = requireEditor(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, mode, devinettes } = parsed.data;

    const db = getFirestore();
    const packRef = db.collection("packs").doc(packId);

    // Charge meta pour next_draft_version
    const metaSnap = await packRef.collection("meta").doc("doc").get();
    const draftVersion =
      (metaSnap.data()?.next_draft_version as number | undefined) ?? 1;

    // Pré-traite + valide forme
    const valid: Record<string, unknown>[] = [];
    const rejected: BulkImportRejection[] = [];
    const idsSeenInBatch = new Set<string>();

    devinettes.forEach((d, index) => {
      const v = DevinetteInput.safeParse(d);
      if (!v.success) {
        rejected.push({ index, error: v.error.issues[0]?.message ?? "shape invalide" });
        return;
      }
      const devi = v.data;
      if (devi.pack && devi.pack !== packId) {
        rejected.push({
          index,
          id: devi.id,
          error: `pack "${devi.pack}" ≠ packId "${packId}"`,
        });
        return;
      }
      if (!devi.id.startsWith(`${packId}_`)) {
        rejected.push({
          index,
          id: devi.id,
          error: `id "${devi.id}" doit commencer par "${packId}_"`,
        });
        return;
      }
      if (idsSeenInBatch.has(devi.id)) {
        rejected.push({
          index,
          id: devi.id,
          error: `doublon d'id dans le batch`,
        });
        return;
      }
      idsSeenInBatch.add(devi.id);

      const answerUpper = devi.answer.toUpperCase();
      const answerNormalized = normalize(answerUpper);
      const lettersPool = lettersPoolFromAnswer(answerNormalized.toUpperCase());

      valid.push({
        id: devi.id,
        pack: packId,
        country: devi.country ?? "ci",
        answer: answerUpper,
        answer_normalized: answerNormalized,
        letters_pool: lettersPool,
        riddle: devi.riddle ?? {},
        explanation: devi.explanation ?? {},
        difficulty: devi.difficulty,
        estimated_time_s: devi.estimated_time_s ?? 30,
        tags: devi.tags ?? [],
        format_version: 3,
        status: "draft",
        draft_version: draftVersion,
        published_version: null,
        deleted_at: null,
      });
    });

    if (valid.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        `Aucune devinette valide à importer (${rejected.length} rejets).`
      );
    }

    // Mode "replace" : soft-delete les drafts existants
    if (mode === "replace") {
      const draftsSnap = await packRef
        .collection("devinettes")
        .where("status", "==", "draft")
        .get();
      for (let i = 0; i < draftsSnap.docs.length; i += BATCH_SIZE) {
        const batch = db.batch();
        for (const doc of draftsSnap.docs.slice(i, i + BATCH_SIZE)) {
          // Hard delete pour les drafts (ils n'ont jamais été publiés)
          batch.delete(doc.ref);
        }
        await batch.commit();
      }
      logger.info("bulkImport: cleared drafts", {
        packId,
        cleared: draftsSnap.size,
      });
    }

    // Insère les valides par batches
    const now = FieldValue.serverTimestamp();
    let written = 0;
    for (let i = 0; i < valid.length; i += BATCH_SIZE) {
      const batch = db.batch();
      const chunk = valid.slice(i, i + BATCH_SIZE);
      for (const v of chunk) {
        const ref = packRef.collection("devinettes").doc(v.id as string);
        batch.set(
          ref,
          {
            ...v,
            updated_at: now,
            updated_by: uid,
            created_at: now, // sera ignoré au prochain set merge si déjà existant
            created_by: uid,
          },
          { merge: true }
        );
      }
      await batch.commit();
      written += chunk.length;
    }

    // Update meta
    await packRef.collection("meta").doc("doc").set(
      {
        id: packId,
        next_draft_version: draftVersion,
        pending_changes: FieldValue.increment(written),
        updated_at: now,
        updated_by: uid,
      },
      { merge: true }
    );

    // Audit log
    await packRef.collection("audit").add({
      type: "bulk_import",
      actor_uid: uid,
      timestamp: now,
      details: {
        mode,
        accepted: written,
        rejected_count: rejected.length,
        draft_version: draftVersion,
      },
    });

    logger.info("bulkImportDevinettes", {
      uid,
      packId,
      mode,
      accepted: written,
      rejected: rejected.length,
    });

    return {
      packId,
      mode,
      accepted: written,
      rejected,
      draftVersion,
    };
  }
);
