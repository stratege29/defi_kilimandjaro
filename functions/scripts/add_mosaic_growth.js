#!/usr/bin/env node
/**
 * Met en file une mosaïque « croissance » (gen_mosaic_growth.py) — tous les posts
 * sont des reels (milieu = lettres, côtés = gameplay), avec `mosaic.{group,row,col}`
 * pour que l'autopilote campagne publie 1 rangée (3 reels) / jour, du bas vers le haut.
 *
 * Auth : ADC. Usage :
 *   node functions/scripts/add_mosaic_growth.js mosaic_growth_akwaba --base 2026-06-22            # dry-run
 *   node functions/scripts/add_mosaic_growth.js mosaic_growth_akwaba --base 2026-06-22 --commit
 */
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const REPO = path.resolve(__dirname, "..", "..");
const COMMIT = process.argv.includes("--commit");
const GROUP = process.argv.find((a) => a.startsWith("mosaic_growth_"));
const bi = process.argv.indexOf("--base");
const BASE = bi >= 0 ? process.argv[bi + 1] : new Date(Date.now() + 864e5).toISOString().slice(0, 10);
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const urlOf = (d, t) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(d)}?alt=media&token=${t}`;

async function up(bucket, local, dest, ct) {
  const tok = crypto.randomUUID();
  await bucket.upload(local, { destination: dest, metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: tok } } });
  return urlOf(dest, tok);
}
function dateOf(base, off) { const d = new Date(base + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + off); return d.toISOString().slice(0, 10); }

async function main() {
  if (!GROUP) { console.error("Usage: add_mosaic_growth.js mosaic_growth_<slug> --base YYYY-MM-DD [--commit]"); process.exit(1); }
  const dir = path.join(REPO, "docs/instagram_assets/mosaic", GROUP);
  const plan = JSON.parse(fs.readFileSync(path.join(dir, "growth_plan.json"), "utf8"));
  const media = path.join(dir, "media");
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore(), bucket = admin.storage().bucket();
  const N = plan.rows;
  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"} · ${GROUP} · ${plan.posts.length} reels · ${N} rangées · base ${BASE} (bas→haut)\n`);

  let done = 0, posted = 0, missing = 0;
  for (const p of plan.posts) {
    const id = `${GROUP}_r${p.row}_c${p.col}`;
    const date = dateOf(BASE, N - 1 - p.row); // bas (row N-1) = base = publié en 1er
    const files = p.type === "reel" ? [p.reel, p.cover] : [p.img];
    if (files.some((f) => !fs.existsSync(path.join(media, f)))) { console.log("· média manquant, ignoré:", id); missing++; continue; }
    const ref = db.collection("instagram_queue").doc(id);
    const snap = await ref.get();
    if (snap.exists && snap.data().posted === true) { console.log("· publié, intact:", id); posted++; continue; }
    const tag = p.col === 1 ? "LETTRE" : (p.type === "reel" ? "gameplay" : "varié");
    console.log(`+ ${id}  ${date}  [r${p.row} c${p.col} · ${tag}]`);
    if (COMMIT) {
      const doc = { caption: p.caption, date, posted: false, mosaic: { group: GROUP, row: p.row, col: p.col } };
      if (p.type === "reel") {
        doc.type = "reel";
        doc.url = await up(bucket, path.join(media, p.reel), `social/ig/mosaic/${GROUP}/${p.reel}`, "video/mp4");
        doc.cover = await up(bucket, path.join(media, p.cover), `social/ig/mosaic/${GROUP}/${p.cover}`, "image/png");
      } else {
        doc.type = "image";
        doc.url = await up(bucket, path.join(media, p.img), `social/ig/mosaic/${GROUP}/${p.img}`, "image/png");
      }
      await ref.set(doc);
    }
    done++;
  }
  console.log(`\n${done} reel(s) ${COMMIT ? "mis en file" : "à créer"}, ${posted} publié(s) intact(s)${missing ? `, ${missing} manquant(s)` : ""}.`);
  if (!COMMIT) console.log("Relance avec --commit pour appliquer.");
  else console.log("\n⚠ Lance la campagne dans l'onglet 🧩 Mosaïque (« Démarrer la campagne ») → 1 rangée (3 reels)/jour, bas→haut.");
}
main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
