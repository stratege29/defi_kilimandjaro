import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { gzipSync } from "zlib";
import { createHash } from "crypto";

const PACK_FORMAT_VERSION = 2;
const PACK_DEFAULT_LANG = "fr";
const PACK_LANGS = ["fr"];

/**
 * Reconstruit, par monde, le pack communautaire à partir des soumissions
 * `approved` non flaggées. Stocke le résultat sur Cloud Storage et met
 * à jour le doc `content_packs/{world}_community` dans Firestore.
 *
 * Schedule : toutes les heures. No-op pour les mondes sans nouvelles
 * approbations depuis le dernier build.
 */
export const rebuildCommunityPack = onSchedule(
  {
    schedule: "every 60 minutes",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const db = getFirestore();
    const storage = getStorage();

    // Liste des mondes avec au moins une soumission approuvée non flaggée.
    const approvedSnap = await db
      .collection("submissions")
      .where("status", "==", "approved")
      .get();
    if (approvedSnap.empty) {
      logger.info("rebuildCommunityPack: aucune approbation, no-op.");
      return;
    }

    const byWorld = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();
    for (const doc of approvedSnap.docs) {
      const w = doc.get("world") as string | undefined;
      if (!w) continue;
      const arr = byWorld.get(w) ?? [];
      arr.push(doc);
      byWorld.set(w, arr);
    }

    for (const [world, docs] of byWorld) {
      const packId = `${world}_community`;
      const stateRef = db.collection("content_packs").doc(packId);
      const state = (await stateRef.get()).data();
      const currentVersion = (state?.current_version as number | undefined) ?? 0;
      const latestApproval = docs.reduce<number>((max, d) => {
        const ts = d.get("reviewedAt") as FirebaseFirestore.Timestamp | undefined;
        return Math.max(max, ts?.toMillis() ?? 0);
      }, 0);
      const lastBuildAt =
        (state?.last_build_at as FirebaseFirestore.Timestamp | undefined)?.toMillis() ??
        0;

      if (latestApproval <= lastBuildAt && currentVersion > 0) {
        logger.debug(`rebuildCommunityPack[${packId}]: déjà à jour.`);
        continue;
      }

      const devinettes = docs.map((d) => ({
        id: d.id,
        world: d.get("world"),
        country: d.get("country"),
        answer: d.get("answer"),
        answer_normalized: d.get("answerNormalized"),
        letters_pool: d.get("lettersPool"),
        riddle: { [d.get("lang") || PACK_DEFAULT_LANG]: d.get("riddle") },
        explanation: { [d.get("lang") || PACK_DEFAULT_LANG]: d.get("explanation") },
        proverb: { [d.get("lang") || PACK_DEFAULT_LANG]: d.get("proverb") },
        difficulty: d.get("difficulty"),
        estimated_time_s: 30,
        tags: d.get("tags") ?? [],
        format_version: PACK_FORMAT_VERSION,
      }));

      const nextVersion = currentVersion + 1;
      const pack = {
        format_version: PACK_FORMAT_VERSION,
        pack_id: packId,
        pack_version: nextVersion,
        generated_at: new Date().toISOString(),
        langs: PACK_LANGS,
        default_lang: PACK_DEFAULT_LANG,
        min_app_version: "0.1.0",
        count: devinettes.length,
        devinettes,
      };

      const json = Buffer.from(JSON.stringify(pack), "utf8");
      const hash = createHash("sha256").update(json).digest("hex");
      const gz = gzipSync(json);

      const storagePath = `packs/v2/${packId}/${packId}-v${nextVersion}.json.gz`;
      const file = storage.bucket().file(storagePath);
      await file.save(gz, {
        contentType: "application/json",
        metadata: {
          contentEncoding: "gzip",
          cacheControl: "public, max-age=86400",
          metadata: { hashSha256: hash, packVersion: String(nextVersion) },
        },
      });
      // Public read URL via le format download v0 (le bucket doit être public
      // pour les chemins `packs/`, cf. `storage.rules`).
      const bucket = storage.bucket().name;
      const downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(
        storagePath
      )}?alt=media`;

      await stateRef.set(
        {
          world,
          current_version: nextVersion,
          format_version: PACK_FORMAT_VERSION,
          hash_sha256: hash,
          size_bytes: gz.length,
          count: devinettes.length,
          storage_path: storagePath,
          download_url: downloadUrl,
          min_app_version: "0.1.0",
          langs: PACK_LANGS,
          default_lang: PACK_DEFAULT_LANG,
          enabled: true,
          last_build_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Met à jour l'index global pour exposer le pack côté client.
      await db
        .collection("content_index")
        .doc("global")
        .set(
          { packs: FieldValue.arrayUnion(packId) },
          { merge: true }
        );

      logger.info(
        `rebuildCommunityPack[${packId}]: v${nextVersion} publié (${devinettes.length} entrées, ${gz.length}B).`
      );
    }
  }
);
