import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import { PACK_FORMAT_VERSION_V3 } from "./packArtifact";

/**
 * `rollbackPack` — repointe la version active d'un pack sur une version
 * archivée (sans ré-uploader d'artefact Storage).
 *
 * Use case : un bug est détecté dans la v5, on veut revenir à v4 le temps
 * de fixer. Les `.json.gz` archivés restent sur Storage (politique GCS
 * lifecycle), donc le rollback est instantané : on change juste où
 * pointe `content_packs/{packId}` + on bump le `catalog_version` pour
 * invalider les caches clients.
 *
 * Séquence :
 *  1. Guard requireAdmin
 *  2. Lit packs/<id>/versions/<toVersion>, doit exister et status='archived'
 *  3. Lit la version courante depuis content_packs/<id>.current_version
 *  4. Update content_packs/<id> avec les valeurs du doc version cible
 *  5. Marque versions/<toVersion>.status = 'active' (was 'archived')
 *  6. Marque versions/<currentVersion>.status = 'archived' (was 'active')
 *  7. Update packs/<id>/meta.latest_published_version = toVersion
 *  8. Bump catalog/index.catalog_version
 *  9. Audit log type='rollback'
 *
 * NB : on ne touche PAS aux devinettes (leurs status restent published).
 * Si une devinette a été ajoutée entre v_target et v_current, elle restera
 * "published" en Firestore mais ne sera pas dans le .json.gz pointé. C'est
 * acceptable : la prochaine publish la ré-inclura.
 */

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  toVersion: z.number().int().min(1).max(9999),
});

export type RollbackPackOutput = {
  packId: string;
  fromVersion: number;
  toVersion: number;
  catalogVersion: number;
  hashSha256: string;
};

export const rollbackPack = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<RollbackPackOutput> => {
    const uid = requireAdmin(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, toVersion } = parsed.data;

    const db = getFirestore();
    const packRef = db.collection("packs").doc(packId);

    // 1. Vérifie la version cible
    const targetSnap = await packRef
      .collection("versions")
      .doc(String(toVersion))
      .get();
    if (!targetSnap.exists) {
      throw new HttpsError(
        "not-found",
        `Version ${toVersion} du pack "${packId}" introuvable.`
      );
    }
    const target = targetSnap.data()!;
    if (target.status !== "archived") {
      throw new HttpsError(
        "failed-precondition",
        `Version ${toVersion} a le status "${target.status}" — seules les versions archivées peuvent être restaurées.`
      );
    }

    // 2. Lit la version active courante (depuis content_packs/<id>)
    const manifestSnap = await db
      .collection("content_packs")
      .doc(packId)
      .get();
    const currentVersion =
      (manifestSnap.data()?.current_version as number | undefined) ?? 0;

    if (currentVersion === toVersion) {
      throw new HttpsError(
        "failed-precondition",
        `Version ${toVersion} est déjà active — rien à faire.`
      );
    }

    // 3. Update content_packs/<id> avec les valeurs du doc cible
    await db.collection("content_packs").doc(packId).set(
      {
        pack: packId,
        current_version: toVersion,
        format_version: target.format_version ?? PACK_FORMAT_VERSION_V3,
        hash_sha256: target.hash_sha256,
        size_bytes: target.size_bytes,
        count: target.count,
        storage_path: target.storage_path,
        download_url: target.download_url,
        min_app_version: target.min_app_version ?? "0.1.0",
        langs: target.langs,
        default_lang: target.default_lang ?? "fr",
        enabled: true,
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // 4. Bascule des status des versions
    await packRef
      .collection("versions")
      .doc(String(toVersion))
      .set(
        {
          status: "active",
          restored_at: FieldValue.serverTimestamp(),
          restored_by: uid,
        },
        { merge: true }
      );

    if (currentVersion > 0) {
      await packRef
        .collection("versions")
        .doc(String(currentVersion))
        .set(
          {
            status: "archived",
            archived_at: FieldValue.serverTimestamp(),
            archived_by: uid,
          },
          { merge: true }
        );
    }

    // 5. Update meta
    await packRef.collection("meta").doc("doc").set(
      {
        latest_published_version: toVersion,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: uid,
      },
      { merge: true }
    );

    // 6. Bump catalog version
    const catalogVersion = await bumpCatalogVersion();

    // 7. Audit
    await packRef.collection("audit").add({
      type: "rollback",
      actor_uid: uid,
      timestamp: FieldValue.serverTimestamp(),
      details: {
        from_version: currentVersion,
        to_version: toVersion,
        hash_sha256: target.hash_sha256,
      },
    });

    logger.info("rollbackPack: success", {
      uid,
      packId,
      fromVersion: currentVersion,
      toVersion,
      hash: target.hash_sha256,
    });

    return {
      packId,
      fromVersion: currentVersion,
      toVersion,
      catalogVersion,
      hashSha256: target.hash_sha256 as string,
    };
  }
);

async function bumpCatalogVersion(): Promise<number> {
  const db = getFirestore();
  const ref = db.collection("catalog").doc("index");
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists
      ? ((snap.data()?.catalog_version as number | undefined) ?? 0)
      : 0;
    const next = current + 1;
    tx.set(
      ref,
      {
        catalog_version: next,
        schema_version: 4,
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return next;
  });
}
