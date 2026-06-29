import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireEditor } from "../utils/auth";

/**
 * `addTagsToWhitelist` — ajoute des tags à `catalog/tags_whitelist.tags`.
 *
 * Utilisé par les correctifs rapides de l'écran de publication (« Autoriser ce
 * tag » sur une erreur TAGS_NOT_WHITELISTED). Les tags sont ajoutés tels quels
 * (pour matcher la valeur stockée sur la devinette) via arrayUnion (idempotent).
 *
 * Guard : requireEditor.
 */
const Input = z.object({
  tags: z.array(z.string().min(1).max(40)).min(1).max(50),
});

export const addTagsToWhitelist = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; added: string[] }> => {
    const uid = requireEditor(req.auth);
    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const tags = Array.from(
      new Set(parsed.data.tags.map((t) => t.trim()).filter(Boolean))
    );
    if (tags.length === 0) {
      throw new HttpsError("invalid-argument", "Aucun tag valide.");
    }
    await getFirestore()
      .collection("catalog")
      .doc("tags_whitelist")
      .set(
        {
          tags: FieldValue.arrayUnion(...tags),
          updated_at: FieldValue.serverTimestamp(),
          updated_by: uid,
        },
        { merge: true }
      );
    logger.info("addTagsToWhitelist", { uid, tags });
    return { ok: true, added: tags };
  }
);
