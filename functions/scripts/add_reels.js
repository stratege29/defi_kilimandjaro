#!/usr/bin/env node
/**
 * Met en file les reels thématiques (gen_reels_theme.py) dans `instagram_queue`
 * (type:"reel", url + cover) — publiés par l'autopilote feed, espacés de `--every` jours.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/add_reels.js nouchi --start 2026-06-20            # dry-run
 *   node functions/scripts/add_reels.js nouchi --start 2026-06-20 --every 2 --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const COMMIT = process.argv.includes("--commit");
const THEME = process.argv[2];
const si = process.argv.indexOf("--start");
const START = si >= 0 ? process.argv[si + 1] : new Date(Date.now() + 864e5).toISOString().slice(0, 10);
const ei = process.argv.indexOf("--every");
const EVERY = ei >= 0 ? Math.max(1, parseInt(process.argv[ei + 1], 10)) : 2;
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function up(bucket, local, dest, ct) {
  const tok = crypto.randomUUID();
  await bucket.upload(local, { destination: dest, metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: tok } } });
  return urlOf(dest, tok);
}
function dateOf(start, off) { const d = new Date(start + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + off); return d.toISOString().slice(0, 10); }

async function main() {
  if (!THEME || THEME.startsWith("--")) { console.error("Usage: add_reels.js <theme> --start YYYY-MM-DD [--every N] [--commit]"); process.exit(1); }
  const dir = path.join(REPO, "docs/instagram_assets/reels/theme");
  const plan = JSON.parse(fs.readFileSync(path.join(dir, `reels_theme_${THEME}_plan.json`), "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · ${THEME} · ${plan.items.length} reels · à partir du ${START} (tous les ${EVERY} j)\n`);

  let done = 0, posted = 0;
  for (const it of plan.items) {
    const id = `reel_${THEME}_${it.i}`;
    const date = dateOf(START, it.i * EVERY);
    const reel = path.join(dir, it.reel), cover = path.join(dir, it.cover);
    if (!fs.existsSync(reel) || !fs.existsSync(cover)) { console.log("· média manquant, ignoré:", id); continue; }
    const ref = db.collection("instagram_queue").doc(id);
    const snap = await ref.get();
    if (snap.exists && snap.data().posted === true) { console.log("· publié, intact:", id); posted++; continue; }
    console.log(`+ ${id}  ${date}  [${it.answer}]`);
    if (COMMIT) {
      const url = await up(bucket, reel, `social/ig/reels/theme/${it.reel}`, "video/mp4");
      const cov = await up(bucket, cover, `social/ig/reels/theme/${it.cover}`, "image/png");
      await ref.set({ type: "reel", url, cover: cov, caption: it.caption, date, posted: false, theme: THEME }, { merge: true });
    }
    done++;
  }
  console.log(`\n${done} reel(s) ${COMMIT ? "mis en file" : "à créer"}, ${posted} publié(s) intact(s).`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
