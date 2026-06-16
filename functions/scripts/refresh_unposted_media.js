#!/usr/bin/env node
/**
 * Rafraîchit les médias des posts NON PUBLIÉS avec les derniers visuels locaux
 * (patterns / thèmes crème-vert / accents). SÛR :
 *  - ne touche QUE les docs `posted == false`,
 *  - ne re-date rien, ne supprime rien,
 *  - laisse intact tout post `posted == true` (déjà publié).
 *
 * Auth : ADC (gcloud auth application-default login).
 * Usage :
 *   node functions/scripts/refresh_unposted_media.js            # dry-run
 *   node functions/scripts/refresh_unposted_media.js --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const ASSETS = path.join(REPO, "docs/instagram_assets");
const PLAN = path.join(__dirname, "instagram_master_plan.json");
const COMMIT = process.argv.includes("--commit");
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function main() {
  const plan = JSON.parse(fs.readFileSync(PLAN, "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  async function up(file, ct) {
    const local = path.join(ASSETS, file);
    if (!fs.existsSync(local)) throw new Error(`introuvable: ${local}`);
    const dest = `social/ig/${path.basename(file)}`, tok = crypto.randomUUID();
    if (COMMIT) await bucket.upload(local, { destination: dest, metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: tok } } });
    return urlOf(dest, tok);
  }
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"}\n`);
  let n = 0, skipped = 0;
  for (const p of plan) {
    const ref = db.collection("instagram_queue").doc(p.id);
    const snap = await ref.get();
    if (!snap.exists) continue;
    if (snap.data().posted === true) { console.log("· publié, intact:", p.id); skipped++; continue; }
    const upd = {};
    if (p.type === "reel") { upd.url = await up(p.video, "video/mp4"); if (p.cover) upd.cover = await up(p.cover, "image/png"); }
    else if (p.type === "carousel") { const u = []; for (const f of p.files) u.push(await up(f, "image/png")); upd.urls = u; }
    else { upd.url = await up(p.files[0], "image/png"); }
    if (COMMIT) await ref.update(upd);
    console.log("↻", p.id, `(${p.type})`); n++;
  }
  console.log(`\n${n} post(s) non publiés rafraîchis, ${skipped} publié(s) laissé(s) intacts.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
