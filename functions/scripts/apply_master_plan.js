#!/usr/bin/env node
/**
 * Applique le plan maître `instagram_master_plan.json` :
 *  - téléverse tous les visuels (lancement + Mondial + lot 2) sur Storage (URLs à jeton),
 *  - écrit/maj un document par post dans `instagram_queue` avec une date séquentielle
 *    (un post par jour à partir de --start, demain par défaut),
 *  - supprime le post `j10` (doublon Canada, couvert par la série Mondial).
 *
 * Ne touche PAS aux posts déjà publiés (ex. j01).
 *
 * Usage :
 *   node functions/scripts/apply_master_plan.js                 # dry-run, démarre demain
 *   node functions/scripts/apply_master_plan.js --start 2026-06-12
 *   node functions/scripts/apply_master_plan.js --commit
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const REPO_ROOT = path.resolve(__dirname, "../..");
const PLAN = path.join(__dirname, "instagram_master_plan.json");
const ASSETS = path.join(REPO_ROOT, "docs/instagram_assets");
const PREFIX = "social/ig";
const COLLECTION = "instagram_queue";

const args = process.argv.slice(2);
const COMMIT = args.includes("--commit");
const startIdx = args.indexOf("--start");
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;

function tomorrowISO() {
  const d = new Date(); d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}
function isoPlus(startStr, i) {
  const d = new Date(`${startStr}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + i);
  return d.toISOString().slice(0, 10);
}
function downloadUrl(dest, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
}

const START = startIdx >= 0 ? args[startIdx + 1] : tomorrowISO();

async function main() {
  const plan = JSON.parse(fs.readFileSync(PLAN, "utf8"));
  console.log(`Projet ${PROJECT} · bucket ${BUCKET}`);
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · démarrage: ${START} · ${plan.length} posts\n`);

  let bucket = null; let db = null;
  if (COMMIT) {
    const admin = require("firebase-admin");
    admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
    bucket = admin.storage().bucket();
    db = admin.firestore();
  }

  async function uploadFile(file, contentType) {
    const local = path.join(ASSETS, file);
    if (!fs.existsSync(local)) throw new Error(`Fichier introuvable: ${local}`);
    const dest = `${PREFIX}/${path.basename(file)}`;
    const token = crypto.randomUUID();
    if (COMMIT) {
      await bucket.upload(local, {
        destination: dest,
        metadata: { contentType, metadata: { firebaseStorageDownloadTokens: token } },
      });
    }
    return downloadUrl(dest, token);
  }

  for (let i = 0; i < plan.length; i += 1) {
    const post = plan[i];
    const date = isoPlus(START, i);
    const doc = { date, type: post.type, caption: post.caption, posted: false };
    let count;
    if (post.type === "reel") {
      doc.url = await uploadFile(post.video, "video/mp4");
      if (post.cover) doc.cover = await uploadFile(post.cover, "image/png");
      count = 1;
    } else {
      const urls = [];
      for (const file of post.files) urls.push(await uploadFile(file, "image/png"));
      if (post.type === "carousel") doc.urls = urls; else doc.url = urls[0];
      count = urls.length;
    }
    if (COMMIT) await db.collection(COLLECTION).doc(post.id).set(doc, { merge: true });
    console.log(`${date}  ${post.id.padEnd(12)} ${post.type.padEnd(9)} ${count} média(s)`);
  }

  // Supprime le doublon Canada (j10)
  if (COMMIT) {
    await db.collection(COLLECTION).doc("j10").delete().catch(() => {});
  }
  console.log(`\nDoublon j10 supprimé. ${plan.length} posts ${COMMIT ? "programmés" : "à programmer"} (${START} → ${isoPlus(START, plan.length - 1)}).`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}

main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
