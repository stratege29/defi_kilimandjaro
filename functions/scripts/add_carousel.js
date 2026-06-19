#!/usr/bin/env node
/**
 * Met en file un carrousel généré (gen_carousel.py) dans `instagram_queue`
 * (type:"carousel", urls[]) — publié par l'autopilote feed à sa date.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/add_carousel.js carousel_nouchi --date 2026-06-20            # dry-run
 *   node functions/scripts/add_carousel.js carousel_nouchi --date 2026-06-20 --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const COMMIT = process.argv.includes("--commit");
const GROUP = process.argv.find((a) => a.startsWith("carousel_") || a.startsWith("pack_"));
const di = process.argv.indexOf("--date");
const DATE = di >= 0 ? process.argv[di + 1] : new Date(Date.now() + 864e5).toISOString().slice(0, 10);
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function up(bucket, local, dest) {
  const tok = crypto.randomUUID();
  await bucket.upload(local, { destination: dest, metadata: { contentType: "image/png", metadata: { firebaseStorageDownloadTokens: tok } } });
  return urlOf(dest, tok);
}

async function main() {
  if (!GROUP) { console.error("Usage: add_carousel.js carousel_<theme> --date YYYY-MM-DD [--commit]"); process.exit(1); }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(DATE)) { console.error("--date YYYY-MM-DD requis."); process.exit(1); }
  const dir = path.join(REPO, "docs/instagram_assets/carousels", GROUP);
  const plan = JSON.parse(fs.readFileSync(path.join(dir, "carousel_plan.json"), "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · ${GROUP} · ${plan.slides.length} slides · date ${DATE}\n`);

  const ref = db.collection("instagram_queue").doc(GROUP);
  const snap = await ref.get();
  if (snap.exists && snap.data().posted === true) { console.log("· déjà publié, intact:", GROUP); return; }

  console.log(`+ ${GROUP}  ${DATE}  [carousel ${plan.slides.length} slides]`);
  plan.slides.forEach((s) => console.log("   ·", s));
  if (COMMIT) {
    const urls = [];
    for (const s of plan.slides) {
      if (!fs.existsSync(path.join(dir, s))) { console.log("  média manquant:", s); continue; }
      urls.push(await up(bucket, path.join(dir, s), `social/ig/carousels/${GROUP}/${s}`));
    }
    await ref.set({ type: "carousel", urls, caption: plan.caption, date: DATE, posted: false, theme: plan.theme }, { merge: true });
    console.log(`\n✅ Carrousel en file (${urls.length} images) pour le ${DATE}.`);
  } else {
    console.log("\nRelance avec --commit pour appliquer.");
  }
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
