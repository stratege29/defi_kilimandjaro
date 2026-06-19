#!/usr/bin/env node
/**
 * Met en file les STORIES « Coupe du Monde 2026 » (gen_reels_theme.py cdm N) dans
 * `instagram_stories`, à 13:30 (Abidjan) chaque jour — une touche Mondial quotidienne,
 * UNIQUEMENT en story. Publiées par le cron stories (créneau midi).
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/add_stories_cdm.js --start 2026-06-20            # dry-run
 *   node functions/scripts/add_stories_cdm.js --start 2026-06-20 --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const COMMIT = process.argv.includes("--commit");
const si = process.argv.indexOf("--start");
const START = si >= 0 ? process.argv[si + 1] : new Date(Date.now() + 864e5).toISOString().slice(0, 10);
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function up(bucket, local, dest, ct) {
  const tok = crypto.randomUUID();
  await bucket.upload(local, { destination: dest, metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: tok } } });
  return urlOf(dest, tok);
}
function at(start, off, h, m) { const d = new Date(start + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + off); d.setUTCHours(h, m, 0, 0); return d; }

async function main() {
  const dir = path.join(REPO, "docs/instagram_assets/reels/theme");
  const plan = JSON.parse(fs.readFileSync(path.join(dir, "reels_theme_cdm_plan.json"), "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  const Ts = admin.firestore.Timestamp;
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · ${plan.items.length} stories CDM · 13:30/jour dès ${START}\n`);

  let done = 0, posted = 0;
  for (const it of plan.items) {
    const id = `story_cdm_${it.i}`;
    const local = path.join(dir, it.reel);
    if (!fs.existsSync(local)) { console.log("· média manquant, ignoré:", id); continue; }
    const ref = db.collection("instagram_stories").doc(id);
    const snap = await ref.get();
    if (snap.exists && snap.data().posted === true) { console.log("· publié, intact:", id); posted++; continue; }
    const when = at(START, it.i, 13, 30);
    console.log(`+ ${id}  ${when.toISOString().slice(0, 16).replace("T", " ")}  [CDM ${it.answer}]`);
    if (COMMIT) {
      const url = await up(bucket, local, `social/ig/stories/cdm/${it.reel}`, "video/mp4");
      await ref.set({ kind: "cdm", mediaType: "video", url, storyAt: Ts.fromDate(when), posted: false,
        label: `Coupe du Monde · ${it.answer}`, group: "cdm2026", answer: it.answer }, { merge: true });
    }
    done++;
  }
  console.log(`\n${done} story(ies) CDM ${COMMIT ? "mises en file" : "à créer"}, ${posted} publiée(s) intacte(s).`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
  console.log("\n⚠ Le cron stories doit inclure le créneau 13:30 (déjà mis à jour : 07:30, 13:30, 20:30).");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
