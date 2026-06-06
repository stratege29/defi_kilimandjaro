import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";

/**
 * `deleteDevinette` — supprime une devinette d'un pack.
 *
 * Deux comportements selon le statut (aligné sur le cycle de vie de
 * `publishPack`) :
 *  - draft jamais publiée (published_version == null) → hard delete (le doc
 *    n'existe dans aucune version publiée). pending_changes décrémenté.
 *  - sinon (déjà publiée, ou draft superposé à une publiée) → soft delete :
 *    status='archived' + deleted_at. Elle sera réellement retirée de
 *    l'artefact au prochain `publishPack` (qui exclut status≠draft/published
 *    et transitionne archived+deleted_at → deleted).
 *
 * Guard : requireEditor (admin ou editor).
 */
const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  deviId: z.string().min(1),
});

export const deleteDevinette = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req) => {
    const uid = requireEditor(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, deviId } = parsed.data;

    const db = getFirestore();
    const packRef = db.collection("packs").doc(packId);
    const deviRef = packRef.collection("devinettes").doc(deviId);
    const metaRef = packRef.collection("meta").doc("doc");

    const snap = await deviRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", `Devinette ${deviId} introuvable.`);
    }
    const data = snap.data() ?? {};
    const now = FieldValue.serverTimestamp();

    const neverPublished =
      data.status === "draft" && data.published_version == null;

    let mode: "hard" | "soft";
    if (neverPublished) {
      await deviRef.delete();
      await metaRef.set(
        {
          id: packId,
          pending_changes: FieldValue.increment(-1),
          updated_at: now,
          updated_by: uid,
        },
        { merge: true }
      );
      mode = "hard";
    } else {
      await deviRef.set(
        {
          status: "archived",
          deleted_at: now,
          updated_at: now,
          updated_by: uid,
        },
        { merge: true }
      );
      await metaRef.set(
        {
          id: packId,
          pending_changes: FieldValue.increment(1),
          updated_at: now,
          updated_by: uid,
        },
        { merge: true }
      );
      mode = "soft";
    }

    logger.info("deleteDevinette", { uid, packId, deviId, mode });
    return { ok: true, mode };
  }
);
