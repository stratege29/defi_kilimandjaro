#!/usr/bin/env node
/**
 * Convertit les docs-lettres d'une mosaïque en REELS, EN SÉCURITÉ :
 *  - ne touche QUE les docs `<group>_r<r>_c<col>` existants et `posted == false`,
 *  - passe type -> "reel", ajoute url(vidéo) + cover(carré), garde caption/date/mosaic,
 *  - laisse intact tout post publié, ne touche pas les côtés ni les séparateurs.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/update_mosaic_reels.js mosaic_phrase_akwaba            # dry-run
 *   node functions/scripts/update_mosaic_reels.js mosaic_phrase_akwaba --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const COMMIT = process.argv.includes("--commit");
const GROUP = process.argv.find((a) => a.startsWith("mosaic_"));
const COL = 1;
const _ri = process.argv.indexOf("--rows");
const ONLY = _ri >= 0 ? new Set(process.argv[_ri + 1].split(",").map(Number)) : null;
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function up(bucket, local, dest, ct) {
  const tok = crypto.randomUUID();
  await bucket.upload(local, { destination: dest, metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: tok } } });
  return urlOf(dest, tok);
}

async function main() {
  if (!GROUP) { console.error("Usage: node functions/scripts/update_mosaic_reels.js mosaic_<slug> [--commit]"); process.exit(1); }
  const dir = path.join(REPO, "docs/instagram_assets/mosaic", GROUP, "reels");
  const plan = JSON.parse(fs.readFileSync(path.join(dir, "reels_plan.json"), "utf8"));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · ${plan.letters.length} lettres\n`);
  let done = 0, skip = 0, posted = 0, missing = 0;
  for (const it of plan.letters) {
    if (ONLY && !ONLY.has(it.row)) continue;
    const id = `${GROUP}_r${it.row}_c${COL}`;
    const reel = path.join(dir, it.reel), cover = path.join(dir, it.cover);
    if (!fs.existsSync(reel) || !fs.existsSync(cover)) { console.log("· média manquant, ignoré:", id); missing++; continue; }
    const ref = db.collection("instagram_queue").doc(id);
    const snap = await ref.get();
    if (!snap.exists) { console.log("· doc absent, ignoré:", id); continue; }
    if (snap.data().posted === true) { console.log("· publié, intact:", id); posted++; continue; }
    if (COMMIT) {
      const vurl = await up(bucket, reel, `social/ig/mosaic/${GROUP}/${it.reel}`, "video/mp4");
      const curl = await up(bucket, cover, `social/ig/mosaic/${GROUP}/${it.cover}`, "image/png");
      await ref.update({ type: "reel", url: vurl, cover: curl });
    }
    console.log(`↻ ${id}  [${it.char}]  -> reel`);
    done++;
  }
  console.log(`\n${done} lettre(s) ${COMMIT ? "converties en reels" : "à convertir"}, ${posted} publiée(s) intacte(s)${missing ? `, ${missing} média(s) manquant(s)` : ""}. Côtés/séparateurs non touchés.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
