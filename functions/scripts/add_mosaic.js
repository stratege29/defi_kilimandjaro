#!/usr/bin/env node
/**
 * Crée les posts d'une MOSAÏQUE dans `instagram_queue`, EN SÉCURITÉ :
 *  - n'ajoute que de NOUVEAUX docs (id `mosaic_<slug>_r{r}_c{c}`),
 *  - tag `mosaic:{group,word,col,row}` (exclus de l'autopilote côté fonction),
 *  - date la rangée du BAS en premier (publication bas→haut),
 *  - ne modifie / ne re-date / ne supprime JAMAIS un post existant.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/add_mosaic.js mosaic_attieke            # dry-run
 *   node functions/scripts/add_mosaic.js mosaic_attieke --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const ROOT = path.join(REPO, "docs/instagram_assets/mosaic");
const COMMIT = process.argv.includes("--commit");
const GROUP = process.argv.find((a) => a.startsWith("mosaic_"));
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;
const isoPlus = (s, i) => { const d = new Date(`${s}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + i); return d.toISOString().slice(0, 10); };

async function main() {
  if (!GROUP) { console.error("Usage: node functions/scripts/add_mosaic.js mosaic_<slug> [--commit]"); process.exit(1); }
  const dir = path.join(ROOT, GROUP);
  const plan = JSON.parse(fs.readFileSync(path.join(dir, "mosaic_plan.json"), "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();

  const snap = await db.collection("instagram_queue").get();
  let maxd = new Date().toISOString().slice(0, 10);
  const existing = new Set();
  snap.forEach((d) => { existing.add(d.id); const dt = d.data().date; if (dt && dt > maxd) maxd = dt; });
  const base = isoPlus(maxd, 1), L = plan.rows;
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · mot "${plan.word}" · colonne ${plan.col} · ${plan.posts.length} posts · base ${base}\n`);

  let added = 0, skip = 0, posted = 0;
  for (const p of plan.posts) {
    const id = `${plan.group}_r${p.row}_c${p.col}`;
    const ref = db.collection("instagram_queue").doc(id);
    if (existing.has(id)) {
      const cur = await ref.get();
      if (cur.exists && cur.data().posted === true) { console.log("· publié, intact:", id); posted++; }
      else { console.log("· existe déjà (non touché):", id); skip++; }
      continue;
    }
    // rangée du bas (row = L-1) -> date la plus tôt ; rangée du haut (row 0) -> la plus tard
    const date = isoPlus(base, (L - 1) - p.row);
    if (COMMIT) {
      const dest = `social/ig/mosaic/${p.file}`, tok = crypto.randomUUID();
      await bucket.upload(path.join(dir, p.file), { destination: dest, metadata: { contentType: "image/png", metadata: { firebaseStorageDownloadTokens: tok } } });
      await ref.set({
        date, type: "image", url: urlOf(dest, tok), caption: p.caption, posted: false,
        mosaic: { group: plan.group, word: plan.word, col: plan.col, row: p.row },
      });
    }
    console.log(`+ r${p.row} c${p.col}  ${date}  ${id}${p.isLetter ? `  [LETTRE ${p.letter}]` : ""}`);
    added++;
  }
  console.log(`\n${added} post(s) ${COMMIT ? "créés" : "à créer"}, ${skip} déjà présent(s), ${posted} publié(s) intact(s). Aucun post existant modifié.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
  console.log("\n⚠ Publication : onglet 🧩 Mosaïque, RANGÉE par RANGÉE (3 posts), du bas vers le haut.");
  console.log("  Mets l'autopilote en PAUSE pendant la campagne (bouton dans l'onglet) pour ne pas décaler la grille.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
