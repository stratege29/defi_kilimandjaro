/**
 * igRenderCard — rendu serveur d'une carte (template Vert Nuit) pour le composer admin.
 * Rend l'image (canvas), l'upload sur Storage, et (si docId) met à jour le doc
 * `instagram_queue` — JAMAIS un post déjà publié.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getStorage } from "firebase-admin/storage";
import { getFirestore } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { renderCard, type CardSpec } from "./cardRenderer";

function assertOwner(auth?: { token?: Record<string, unknown> }): void {
  const t = auth?.token ?? {};
  const ok = t["role"] === "admin" || (t["email"] === "arnaudkossea@gmail.com" && t["email_verified"] === true);
  if (!ok) throw new HttpsError("permission-denied", "Accès réservé au propriétaire.");
}

export const igRenderCard = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true, memory: "512MiB", timeoutSeconds: 60 },
  async (req): Promise<{ ok: true; url: string }> => {
    assertOwner(req.auth);
    const spec = req.data?.spec as CardSpec | undefined;
    const docId = (req.data?.docId as string) || "";
    const caption = req.data?.caption as string | undefined;
    if (!spec || !spec.template) throw new HttpsError("invalid-argument", "spec (template + champs) requis.");

    const bucket = getStorage().bucket();
    let photoPath: string | undefined;
    if (spec.template === "medaillon") {
      const key = (spec.photo || "").replace(/[^a-z0-9_]/gi, "");
      if (!key) throw new HttpsError("invalid-argument", "photo (clé) requise pour le médaillon.");
      const file = bucket.file(`social/ai/${key}.png`);
      const [exists] = await file.exists();
      if (!exists) throw new HttpsError("not-found", `Photo introuvable: social/ai/${key}.png`);
      const [buf] = await file.download();
      photoPath = path.join(os.tmpdir(), `${randomUUID()}.png`);
      fs.writeFileSync(photoPath, buf);
    }

    let buffer: Buffer;
    try {
      buffer = await renderCard(spec, photoPath);
    } catch (e) {
      throw new HttpsError("internal", `Rendu échoué: ${(e as Error).message}`);
    } finally {
      if (photoPath) { try { fs.unlinkSync(photoPath); } catch { /* ignore */ } }
    }

    const dest = `social/ig/edited/${docId || "card"}_${randomUUID()}.png`;
    const token = randomUUID();
    await bucket.file(dest).save(buffer, {
      metadata: { contentType: "image/png", metadata: { firebaseStorageDownloadTokens: token } },
    });
    const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;

    if (docId) {
      const ref = getFirestore().collection("instagram_queue").doc(docId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError("not-found", `Doc ${docId} introuvable.`);
      if (snap.data()?.posted === true) throw new HttpsError("failed-precondition", "Post déjà publié : édition refusée.");
      const upd: Record<string, unknown> = { url, type: "image", cardSpec: spec };
      if (typeof caption === "string" && caption.length) upd.caption = caption;
      await ref.update(upd);
    }
    return { ok: true, url };
  },
);
