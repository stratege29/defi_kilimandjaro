#!/usr/bin/env node
/**
 * Ajoute les posts images IA à la file `instagram_queue`, EN TOUTE SÉCURITÉ :
 *  - n'ajoute que de NOUVEAUX documents (id `ai_*`),
 *  - les date APRÈS le dernier post programmé (1/jour),
 *  - ne modifie/ne supprime/ne re-date JAMAIS un post existant (donc rien de publié).
 *
 * Prérequis : cartes habillées dans docs/instagram_assets/ai/cards/ (CARD_<key>.png).
 * Auth : ADC (gcloud auth application-default login).
 *
 * Usage :
 *   node functions/scripts/add_ai_posts.js            # dry-run
 *   node functions/scripts/add_ai_posts.js --commit   # applique
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
// Cartes IA habillées (voile + texte de marque), produites par apply_ai_overlay.py.
const CARDS = path.join(REPO, "docs/instagram_assets/ai/cards");
const SPEC = path.join(__dirname, "ai_posts.json");
const COMMIT = process.argv.includes("--commit");
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;

function isoPlus(s, i) { const d = new Date(`${s}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + i); return d.toISOString().slice(0, 10); }
function urlOf(dest, t) { return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${t}`; }

async function main() {
  const spec = JSON.parse(fs.readFileSync(SPEC, "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();

  const snap = await db.collection("instagram_queue").get();
  let maxd = new Date().toISOString().slice(0, 10);
  const existing = new Set();
  snap.forEach((d) => { existing.add(d.id); const dt = d.data().date; if (dt && dt > maxd) maxd = dt; });
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · dernière date programmée: ${maxd}\n`);

  let i = 1, added = 0;
  for (const p of spec) {
    const card = path.join(CARDS, p.file);
    if (!fs.existsSync(card)) { console.log("· carte absente, ignoré:", p.id); continue; }
    if (existing.has(p.id)) { console.log("· existe déjà (non touché):", p.id); continue; }
    const date = isoPlus(maxd, i); i += 1;
    if (COMMIT) {
      const dest = `social/ig/${p.file}`, tok = crypto.randomUUID();
      await bucket.upload(card, { destination: dest, metadata: { contentType: "image/png", metadata: { firebaseStorageDownloadTokens: tok } } });
      await db.collection("instagram_queue").doc(p.id).set({ date, type: "image", url: urlOf(dest, tok), caption: p.caption, posted: false });
    }
    console.log(`+ ${date}  ${p.id}`); added += 1;
  }
  console.log(`\n${added} post(s) ${COMMIT ? "ajoutés" : "à ajouter"} (après ${maxd}). Aucun post existant modifié.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
