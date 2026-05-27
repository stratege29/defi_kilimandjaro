#!/usr/bin/env node
/**
 * Seed des défis du jour vers Firestore (collection `/daily_challenges/{yyyy-MM-dd}`).
 *
 * Trois modes d'usage :
 *
 *   1. **seed-range** : pré-remplit Firestore pour une période donnée, en
 *      respectant le shuffle annuel déterministe (mirroir exact de la
 *      logique `BundleDailyChallengeRepository` côté client). Utile pour
 *      pousser un trimestre d'avance.
 *
 *      node functions/scripts/seed_daily_challenges.js \
 *        --seed-range 2026-06-01 2026-08-31
 *
 *   2. **push-date** : override single pour une date précise (ex. mot
 *      événementiel pour la fête nationale, lancement d'un nouveau pack).
 *      L'id de la devinette à pousser est résolu depuis le bundle seed
 *      par son champ `id`.
 *
 *      node functions/scripts/seed_daily_challenges.js \
 *        --push-date 2026-08-07 --id daily_013
 *
 *   3. **--dry-run** : pas d'écriture, log uniquement ce qui aurait été
 *      poussé. Composable avec les 2 autres modes.
 *
 * Le bundle source est `assets/data/daily_challenges_seed.json` à la racine
 * du repo (15 entrées au lancement, à étendre à 90 via devinette-curator).
 *
 * Sécurité : firestore.rules autorisent la lecture publique mais bloquent
 * l'écriture client-side. Ce script utilise l'admin SDK (bypass des rules).
 *
 * Idempotent : `set` sans merge → un push d'override ré-écrit complètement
 * le doc, garantissant un état déterministe.
 *
 * Usage env vars (identique à seed_devinettes.js) :
 *   # mode émulateur (recommandé pour dev)
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     GOOGLE_CLOUD_PROJECT=kilimandjaro-dev \
 *     node functions/scripts/seed_daily_challenges.js --seed-range 2026-06-01 2026-06-30
 *
 *   # mode prod (nécessite GOOGLE_APPLICATION_CREDENTIALS)
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
 *     node functions/scripts/seed_daily_challenges.js --push-date 2026-08-07 --id daily_013
 */

"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "../..");
const SEED_FILE = path.join(REPO_ROOT, "assets/data/daily_challenges_seed.json");
const COLLECTION = "daily_challenges";

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = { dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") {
      args.dryRun = true;
    } else if (a === "--seed-range") {
      args.mode = "seed-range";
      args.from = argv[++i];
      args.to = argv[++i];
    } else if (a === "--push-date") {
      args.mode = args.mode || "push-date";
      args.pushDate = argv[++i];
    } else if (a === "--id") {
      args.devinetteId = argv[++i];
    }
  }
  return args;
}

function usage() {
  console.error("Usage :");
  console.error(
    "  --seed-range YYYY-MM-DD YYYY-MM-DD   pré-remplit une plage de dates"
  );
  console.error(
    "  --push-date YYYY-MM-DD --id daily_NNN  override single pour une date"
  );
  console.error("  --dry-run                            n'écrit pas, log uniquement");
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Helpers — clés calendaires & shuffle annuel (mirroir Dart)
// ---------------------------------------------------------------------------

function isoDate(d) {
  const y = String(d.getUTCFullYear()).padStart(4, "0");
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function parseIsoDate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) throw new Error(`Date invalide (attendu YYYY-MM-DD) : ${s}`);
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
}

function dayOfYear(date) {
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const diff = date.getTime() - yearStart.getTime();
  return Math.floor(diff / 86400000) + 1; // 1..366
}

function fnv1a32(input) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/**
 * Permutation déterministe Fisher-Yates seedée sur l'année — algorithme
 * **bit-identique** au `BundleDailyChallengeRepository._permutationForYear`
 * côté Dart. Si la logique Dart change, il faut mirrorer ici sinon les
 * docs Firestore et le fallback bundle ne pointeront plus sur la même
 * devinette pour une date donnée.
 */
function permutationForYear(year, poolLen) {
  const perm = Array.from({ length: poolLen }, (_, i) => i);
  let hash = fnv1a32(String(year));
  for (let i = poolLen - 1; i > 0; i--) {
    hash = (Math.imul(hash, 1664525) + 1013904223) >>> 0;
    const j = hash % (i + 1);
    const tmp = perm[i];
    perm[i] = perm[j];
    perm[j] = tmp;
  }
  return perm;
}

function pickForDate(pool, date) {
  if (pool.length === 0) return null;
  const perm = permutationForYear(date.getUTCFullYear(), pool.length);
  const idx = perm[(dayOfYear(date) - 1) % perm.length];
  return pool[idx];
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.mode) usage();

  const raw = fs.readFileSync(SEED_FILE, "utf8");
  const pool = JSON.parse(raw);
  if (!Array.isArray(pool) || pool.length === 0) {
    console.error(`Seed bundle vide ou invalide : ${SEED_FILE}`);
    process.exit(1);
  }
  console.log(`📦 Bundle chargé : ${pool.length} entrées depuis ${path.relative(REPO_ROOT, SEED_FILE)}`);

  let db = null;
  if (!args.dryRun) {
    const admin = require("firebase-admin");
    admin.initializeApp({
      projectId:
        process.env.GOOGLE_CLOUD_PROJECT ||
        process.env.GCLOUD_PROJECT ||
        "kilimandjaro-dev",
    });
    db = admin.firestore();
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      console.log(`🔧 Mode émulateur : ${process.env.FIRESTORE_EMULATOR_HOST}`);
    }
  } else {
    console.log("🧪 Mode dry-run — aucune écriture Firestore");
  }

  if (args.mode === "seed-range") {
    if (!args.from || !args.to) usage();
    const from = parseIsoDate(args.from);
    const to = parseIsoDate(args.to);
    if (from > to) {
      console.error("--seed-range : la date `from` doit être ≤ `to`");
      process.exit(2);
    }

    let count = 0;
    for (let d = new Date(from); d <= to; d.setUTCDate(d.getUTCDate() + 1)) {
      const docId = isoDate(d);
      const devinette = pickForDate(pool, d);
      if (!devinette) continue;
      console.log(`  ${docId} → ${devinette.id} (${devinette.answer})`);
      if (!args.dryRun) {
        await db.collection(COLLECTION).doc(docId).set(devinette);
      }
      count++;
    }
    console.log(`✅ ${count} doc(s) ${args.dryRun ? "à écrire" : "écrits"}`);
  } else if (args.mode === "push-date") {
    if (!args.pushDate || !args.devinetteId) {
      console.error("--push-date nécessite aussi --id daily_NNN");
      usage();
    }
    const docId = isoDate(parseIsoDate(args.pushDate));
    const devinette = pool.find((d) => d.id === args.devinetteId);
    if (!devinette) {
      console.error(
        `Aucune entrée bundle avec id="${args.devinetteId}". ` +
          `Ids disponibles : ${pool.map((d) => d.id).join(", ")}`
      );
      process.exit(1);
    }
    console.log(`  ${docId} ← ${devinette.id} (${devinette.answer}) [override]`);
    if (!args.dryRun) {
      await db.collection(COLLECTION).doc(docId).set(devinette);
    }
    console.log(`✅ override ${args.dryRun ? "à écrire" : "écrit"} pour ${docId}`);
  } else {
    usage();
  }
}

main().catch((err) => {
  console.error("❌ Erreur :", err);
  process.exit(1);
});
