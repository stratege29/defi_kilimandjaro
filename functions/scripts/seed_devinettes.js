#!/usr/bin/env node
/**
 * Seed des devinettes vers Firestore (collection `/devinettes/{id}`).
 *
 * Lit `assets/data/devinettes/starter/*.json` à la racine du repo et écrit
 * chaque devinette comme un document Firestore. Idempotent (set + merge).
 *
 * Sécurité: serveur-only (admin SDK bypass les rules). Les devinettes ne sont
 * JAMAIS lisibles par les clients — voir firestore.rules.
 *
 * Usage:
 *   # mode émulateur (recommandé pour dev)
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     GOOGLE_CLOUD_PROJECT=kilimandjaro-dev \
 *     node functions/scripts/seed_devinettes.js
 *
 *   # mode prod (nécessite GOOGLE_APPLICATION_CREDENTIALS)
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
 *     node functions/scripts/seed_devinettes.js
 *
 *   # dry-run (parse + valide, n'écrit pas)
 *   node functions/scripts/seed_devinettes.js --dry-run
 *
 * Règle difficulté (basée sur letter_count) :
 *   easy   : 4-5 lettres
 *   medium : 6-7 lettres
 *   hard   : 8+ lettres
 */

const fs = require("fs");
const path = require("path");
// firebase-admin requis seulement hors dry-run (chargé dans main())

const REPO_ROOT = path.resolve(__dirname, "../..");
const STARTER_DIR = path.join(REPO_ROOT, "assets/data/devinettes/starter");
const INDEX_FILE = path.join(STARTER_DIR, "_index.json");

const DRY_RUN = process.argv.includes("--dry-run");

function computeDifficulty(letterCount) {
  if (letterCount <= 5) return "easy";
  if (letterCount <= 7) return "medium";
  return "hard";
}

function extractFr(field) {
  if (field == null) return "";
  if (typeof field === "string") return field;
  if (typeof field === "object" && typeof field.fr === "string") return field.fr;
  return "";
}

function parseDevinette(raw, packId) {
  const id = raw.id;
  const answer = raw.answer;
  const lettersPool = Array.isArray(raw.letters_pool) ? raw.letters_pool : [];

  if (!id || !answer || lettersPool.length === 0) {
    return { error: `devinette invalide (id=${id ?? "?"}, pack=${packId})` };
  }

  const letterCount = lettersPool.length;
  return {
    devinette: {
      id,
      pack: packId,
      answer,
      letters_pool: lettersPool,
      riddle: extractFr(raw.riddle),
      explanation: extractFr(raw.explanation),
      proverb: extractFr(raw.proverb),
      difficulty: computeDifficulty(letterCount),
      letter_count: letterCount,
      enabled_for_duel: true,
      enabled_for_solo: true,
      status: "approved",
      times_played: 0,
      times_solved: 0,
      tags: Array.isArray(raw.tags) ? raw.tags : [],
      country: raw.country ?? "ci",
    },
  };
}

async function main() {
  if (!fs.existsSync(INDEX_FILE)) {
    console.error(`Index introuvable : ${INDEX_FILE}`);
    process.exit(1);
  }

  const indexJson = JSON.parse(fs.readFileSync(INDEX_FILE, "utf8"));
  const packs = indexJson.packs ?? {};

  const all = [];
  const errors = [];
  const stats = { total: 0, easy: 0, medium: 0, hard: 0, byPack: {} };

  for (const [packId] of Object.entries(packs)) {
    const file = path.join(STARTER_DIR, `${packId}.json`);
    if (!fs.existsSync(file)) {
      console.warn(`SKIP pack ${packId} (fichier absent: ${file})`);
      continue;
    }
    const list = JSON.parse(fs.readFileSync(file, "utf8"));
    stats.byPack[packId] = { total: 0, easy: 0, medium: 0, hard: 0 };

    for (const raw of list) {
      const parsed = parseDevinette(raw, packId);
      if (parsed.error) {
        errors.push(parsed.error);
        continue;
      }
      const d = parsed.devinette;
      all.push(d);
      stats.total++;
      stats[d.difficulty]++;
      stats.byPack[packId].total++;
      stats.byPack[packId][d.difficulty]++;
    }
  }

  console.log("=== Seed devinettes Firestore ===");
  console.log(`Mode    : ${DRY_RUN ? "DRY RUN" : "WRITE"}`);
  console.log(`Total   : ${stats.total} devinettes valides`);
  console.log(`  easy   (4-5) : ${stats.easy}`);
  console.log(`  medium (6-7) : ${stats.medium}`);
  console.log(`  hard   (8+)  : ${stats.hard}`);
  console.log("Par pack :");
  for (const [pack, s] of Object.entries(stats.byPack)) {
    console.log(`  ${pack}: ${s.total} (${s.easy}E / ${s.medium}M / ${s.hard}H)`);
  }
  if (errors.length > 0) {
    console.warn(`\n${errors.length} devinette(s) invalide(s) ignorée(s):`);
    errors.forEach((e) => console.warn(`  - ${e}`));
  }

  const minPerLevel = Math.min(stats.easy, stats.medium, stats.hard);
  if (minPerLevel < 10) {
    console.warn(
      `\n⚠  Distribution déséquilibrée : minimum ${minPerLevel}/niveau (recommandé ≥10).`,
    );
    console.warn(
      "   Le duel pourra fonctionner mais le pool de tirage sera limité.",
    );
  }

  if (DRY_RUN) {
    console.log("\n[DRY RUN] Aucune écriture Firestore. Fin.");
    return;
  }

  const admin = require("firebase-admin");
  const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT;
  console.log(
    `\nCible Firestore : ${
      usingEmulator
        ? `émulateur (${process.env.FIRESTORE_EMULATOR_HOST}, projet ${projectId ?? "?"})`
        : `PRODUCTION (projet ${projectId ?? "depuis credentials"})`
    }`,
  );

  admin.initializeApp({
    projectId: projectId ?? "kilimandjaro-dev",
  });
  const db = admin.firestore();

  // Batch write par paquets de 400 (limite Firestore = 500 ops/batch)
  const BATCH_SIZE = 400;
  const now = admin.firestore.FieldValue.serverTimestamp();
  let written = 0;

  for (let i = 0; i < all.length; i += BATCH_SIZE) {
    const slice = all.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const d of slice) {
      const ref = db.collection("devinettes").doc(d.id);
      batch.set(
        ref,
        {
          ...d,
          updated_at: now,
          created_at: now,
        },
        { merge: true },
      );
    }
    await batch.commit();
    written += slice.length;
    console.log(`  Écrit ${written}/${all.length}...`);
  }

  console.log(`\n✓ Seed terminé : ${written} devinettes dans /devinettes`);
}

main().catch((err) => {
  console.error("Erreur fatale :", err);
  process.exit(1);
});
