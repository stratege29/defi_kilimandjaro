#!/usr/bin/env node
/**
 * Seed de la file Instagram (`instagram_queue`) + upload des visuels sur Storage.
 *
 * Lit `functions/scripts/instagram_seed_data.json`, téléverse les PNG depuis
 * `docs/instagram_assets/` vers Storage (`social/ig/`), les rend publics, puis
 * crée un document par post dans `instagram_queue` (posted: false). Idempotent.
 *
 * Les entrées marquées `"skip": true` (Reels sans vidéo) sont ignorées.
 *
 * Usage :
 *   # dry-run (n'écrit rien, montre ce qui serait fait)
 *   node functions/scripts/seed_instagram_queue.js
 *
 *   # réel (upload + écriture Firestore) — nécessite des identifiants Firebase
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
 *     GOOGLE_CLOUD_PROJECT=kilimandjaro-dev \
 *     node functions/scripts/seed_instagram_queue.js --commit
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const REPO_ROOT = path.resolve(__dirname, "../..");
const DATA_FILE = path.join(__dirname, "instagram_seed_data.json");
const ASSETS_DIR = path.join(REPO_ROOT, "docs/instagram_assets");
const STORAGE_PREFIX = "social/ig";
const COLLECTION = "instagram_queue";

const COMMIT = process.argv.includes("--commit");
const PROJECT_ID =
  process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT_ID}.firebasestorage.app`;

function downloadUrl(destination, token) {
  const enc = encodeURIComponent(destination);
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${enc}?alt=media&token=${token}`;
}

async function main() {
  const posts = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
  console.log(`Projet: ${PROJECT_ID} · bucket: ${BUCKET}`);
  console.log(`Mode: ${COMMIT ? "COMMIT (réel)" : "DRY-RUN (aucune écriture)"}\n`);

  let bucket = null;
  let db = null;
  if (COMMIT) {
    const admin = require("firebase-admin");
    admin.initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET });
    bucket = admin.storage().bucket();
    db = admin.firestore();
  }

  let created = 0;
  let skipped = 0;

  for (const post of posts) {
    if (post.skip) {
      console.log(`⏭️  ${post.id} (${post.type}) — ignoré (vidéo manquante).`);
      skipped += 1;
      continue;
    }

    // 1) Upload des fichiers -> URLs publiques
    const urls = [];
    for (const file of post.files) {
      const local = path.join(ASSETS_DIR, file);
      if (!fs.existsSync(local)) {
        throw new Error(`Fichier introuvable: ${local}`);
      }
      const destination = `${STORAGE_PREFIX}/${file}`;
      const token = crypto.randomUUID();
      if (COMMIT) {
        await bucket.upload(local, {
          destination,
          metadata: {
            contentType: "image/png",
            metadata: { firebaseStorageDownloadTokens: token },
          },
        });
      }
      urls.push(downloadUrl(destination, token));
    }

    // 2) Construction du document file d'attente
    const doc = {
      date: post.date,
      type: post.type,
      caption: post.caption,
      posted: false,
    };
    if (post.type === "carousel") {
      doc.urls = urls;
    } else if (post.type === "reel") {
      doc.url = post.video; // vidéo à fournir
      if (urls[0]) doc.cover = urls[0];
    } else {
      doc.url = urls[0];
    }

    if (COMMIT) {
      await db.collection(COLLECTION).doc(post.id).set(doc, { merge: true });
    }
    console.log(`✅ ${post.id} · ${post.date} · ${post.type} · ${urls.length} média(s)`);
    created += 1;
  }

  console.log(`\nTerminé — ${created} post(s) ${COMMIT ? "créés" : "à créer"}, ${skipped} ignoré(s).`);
  if (!COMMIT) {
    console.log("Relance avec --commit (et des identifiants Firebase) pour appliquer.");
  }
}

main().catch((e) => {
  console.error("Erreur:", e.message);
  process.exit(1);
});
