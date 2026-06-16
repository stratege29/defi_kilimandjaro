#!/usr/bin/env node
/**
 * Re-date les posts NON publiés de `instagram_queue` pour un rythme quotidien.
 * Conserve l'ordre actuel ; n'touche pas aux posts déjà publiés.
 * Lit/écrit Firestore via ADC (gcloud auth application-default login).
 *
 * Usage :
 *   node functions/scripts/redate_queue.js                 # dry-run, démarre demain
 *   node functions/scripts/redate_queue.js --start 2026-06-12
 *   node functions/scripts/redate_queue.js --commit        # applique
 */
const admin = require("firebase-admin");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const args = process.argv.slice(2);
const COMMIT = args.includes("--commit");
const startIdx = args.indexOf("--start");

function tomorrowISO() {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}
function isoPlus(startStr, i) {
  const d = new Date(`${startStr}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + i);
  return d.toISOString().slice(0, 10);
}

const START = startIdx >= 0 ? args[startIdx + 1] : tomorrowISO();

async function main() {
  admin.initializeApp({ projectId: PROJECT });
  const db = admin.firestore();

  const snap = await db.collection("instagram_queue")
    .where("posted", "==", false).orderBy("date", "asc").get();

  if (snap.empty) {
    console.log("Aucun post non publié à re-dater.");
    return;
  }
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · démarrage: ${START}\n`);

  let i = 0;
  for (const doc of snap.docs) {
    const newDate = isoPlus(START, i);
    console.log(`${doc.id.padEnd(5)} ${doc.data().date}  →  ${newDate}`);
    if (COMMIT) await doc.ref.update({ date: newDate });
    i += 1;
  }
  console.log(`\n${i} post(s) ${COMMIT ? "re-datés" : "à re-dater"}.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}

main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
