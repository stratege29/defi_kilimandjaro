#!/usr/bin/env node
/**
 * Met à jour le visuel des posts IA (`ai_*`) avec les cartes sobres (médaillon),
 * EN TOUTE SÉCURITÉ :
 *  - ne touche QUE les docs `ai_*` existants et `posted == false`,
 *  - laisse intact tout post `posted == true` (déjà publié),
 *  - ne re-date rien, n'ajoute / ne supprime aucun doc.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/update_ai_media.js            # dry-run
 *   node functions/scripts/update_ai_media.js --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const CARDS = path.join(REPO, "docs/instagram_assets/ai/cards");
const SPEC = path.join(__dirname, "ai_posts.json");
const COMMIT = process.argv.includes("--commit");
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function main() {
  const spec = JSON.parse(fs.readFileSync(SPEC, "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"}\n`);
  let n = 0, skipped = 0, missing = 0;
  for (const p of spec) {
    const card = path.join(CARDS, p.file);
    if (!fs.existsSync(card)) { console.log("· carte absente, ignoré:", p.id); missing++; continue; }
    const ref = db.collection("instagram_queue").doc(p.id);
    const snap = await ref.get();
    if (!snap.exists) { console.log("· doc absent, ignoré:", p.id); continue; }
    if (snap.data().posted === true) { console.log("· publié, intact:", p.id); skipped++; continue; }
    if (COMMIT) {
      const dest = `social/ig/${p.file}`, tok = crypto.randomUUID();
      await bucket.upload(card, { destination: dest, metadata: { contentType: "image/png", metadata: { firebaseStorageDownloadTokens: tok } } });
      await ref.update({ url: urlOf(dest, tok) });
    }
    console.log("↻", p.id);
    n++;
  }
  console.log(`\n${n} visuel(s) ${COMMIT ? "mis à jour" : "à mettre à jour"}, ${skipped} publié(s) intact(s)${missing ? `, ${missing} carte(s) absente(s)` : ""}.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
