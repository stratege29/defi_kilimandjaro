#!/usr/bin/env node
/**
 * Met en file les stories générées (gen_stories.py) dans `instagram_stories`.
 * Cadence : pour chaque jour i (à partir de demain), ÉNIGME à 07:30 et
 * RÉPONSE à 20:30 (heure d'Abidjan = UTC). Idempotent (ids déterministes),
 * ne touche jamais une story déjà publiée.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/add_stories.js            # dry-run
 *   node functions/scripts/add_stories.js --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const COMMIT = process.argv.includes("--commit");
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const COLL = "instagram_stories";
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function up(bucket, local, dest, ct) {
  const tok = crypto.randomUUID();
  await bucket.upload(local, { destination: dest, metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: tok } } });
  return urlOf(dest, tok);
}

function startTomorrowUtc() { const d = new Date(); d.setUTCHours(0, 0, 0, 0); d.setUTCDate(d.getUTCDate() + 1); return d; }
function at(start, dayOffset, h, m) { const d = new Date(start); d.setUTCDate(d.getUTCDate() + dayOffset); d.setUTCHours(h, m, 0, 0); return d; }

async function main() {
  const dir = path.join(REPO, "docs/instagram_assets/stories");
  const plan = JSON.parse(fs.readFileSync(path.join(dir, "stories_plan.json"), "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  const Ts = admin.firestore.Timestamp;
  const start = startTomorrowUtc();
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · ${plan.items.length} jours · ${plan.items.length * 2} stories\n`);

  let created = 0, posted = 0;
  for (const it of plan.items) {
    const frames = [
      { kind: "enigme", file: it.enigme, when: at(start, it.i, 7, 30), cap: `ÉNIGME ${it.cat}` },
      { kind: "reponse", file: it.reponse, when: at(start, it.i, 20, 30), cap: `RÉPONSE ${it.answer}` },
    ];
    for (const f of frames) {
      const id = `story_${it.i}_${f.kind}`;
      const local = path.join(dir, f.file);
      if (!fs.existsSync(local)) { console.log("· média manquant, ignoré:", id); continue; }
      const ref = db.collection(COLL).doc(id);
      const snap = await ref.get();
      if (snap.exists && snap.data().posted === true) { console.log("· publié, intact:", id); posted++; continue; }
      const isVid = f.file.endsWith(".mp4");
      const when = f.when.toISOString().slice(0, 16).replace("T", " ");
      console.log(`+ ${id}  ${when}  [${f.cap}] ${isVid ? "🎬" : "🖼"}`);
      if (COMMIT) {
        const url = await up(bucket, local, `social/ig/stories/${f.file}`, isVid ? "video/mp4" : "image/png");
        await ref.set({ kind: f.kind, mediaType: isVid ? "video" : "image", url, storyAt: Ts.fromDate(f.when), posted: false, label: f.cap, group: "daily", answer: it.answer }, { merge: true });
      }
      created++;
    }
  }
  console.log(`\n${created} story(ies) ${COMMIT ? "mises en file" : "à créer"}, ${posted} publiée(s) intacte(s).`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
  console.log("\n⚠ Active l'autopilote stories dans le dashboard (onglet Stories) pour publier 07:30 + 20:30 (Abidjan).");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
