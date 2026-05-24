#!/usr/bin/env node
/**
 * Seed la collection Firestore `devinettes` consommee par les CF
 * matchmaking (requestMatch / requestRematch via devinettesCache.ts).
 *
 * Source : assets/data/devinettes/starter/<packId>.json (frozen, bundled).
 *
 * Mapping :
 *   - difficulty asset 1 → "easy"
 *   - difficulty asset 2 → "medium"
 *   - difficulty asset 3 → "hard"
 *   - difficulty asset 4 → "hard"
 *
 * Format Firestore doc (id = devinette id type "culture_ci_001") :
 *   {
 *     answer: string,
 *     letters_pool: string[],
 *     riddle: string,        // FR uniquement
 *     explanation: string,   // FR uniquement
 *     proverb: string,       // vide en v3 (champ obsolete cote asset)
 *     difficulty: "easy" | "medium" | "hard",
 *     pack: string,          // packId source (audit & filtre Phase B)
 *     country: string,       // ex "ci"
 *     enabled_for_duel: true,
 *     status: "approved"
 *   }
 *
 * Modes :
 *   --audit         : compte ce qui est en Firestore (par difficulte/pack).
 *   --seed          : upsert (set merge) toutes les devinettes assets.
 *   --dry-run       : affiche ce qui serait ecrit sans le faire.
 *
 * Usage :
 *   node tools/scripts/seed_firestore_devinettes.mjs --project kilimandjaro-dev --audit
 *   node tools/scripts/seed_firestore_devinettes.mjs --project kilimandjaro-dev --seed
 *   node tools/scripts/seed_firestore_devinettes.mjs --project kilimandjaro-dev --seed --dry-run
 *
 * Auth : Application Default Credentials.
 *   gcloud auth application-default login
 *   gcloud config set project kilimandjaro-dev
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import process from 'node:process';

import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    'starter-dir': {
      type: 'string',
      default: 'assets/data/devinettes/starter',
    },
    audit: { type: 'boolean', default: false },
    seed: { type: 'boolean', default: false },
    'dry-run': { type: 'boolean', default: false },
  },
});

if (!values.project) {
  console.error(
    'usage: node tools/scripts/seed_firestore_devinettes.mjs --project <id> [--audit|--seed] [--dry-run]',
  );
  process.exit(64);
}
if (!values.audit && !values.seed) {
  console.error('Specifie --audit ou --seed (ou les deux).');
  process.exit(64);
}

admin.initializeApp({ projectId: values.project });
const db = admin.firestore();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mapDifficulty(n) {
  if (n === 1) return 'easy';
  if (n === 2) return 'medium';
  if (n === 3) return 'hard';
  if (n === 4) return 'hard';
  return 'medium'; // fallback defensif
}

function pickFrenchString(field) {
  if (typeof field === 'string') return field;
  if (field && typeof field === 'object' && typeof field.fr === 'string') {
    return field.fr;
  }
  return '';
}

function loadStarterDevinettes(starterDir) {
  const indexFile = join(starterDir, '_index.json');
  const index = JSON.parse(readFileSync(indexFile, 'utf8'));
  const packs = index.packs ?? {};
  const out = [];
  for (const [packId, meta] of Object.entries(packs)) {
    const packFile = join(starterDir, meta.file ?? `${packId}.json`);
    const arr = JSON.parse(readFileSync(packFile, 'utf8'));
    if (!Array.isArray(arr)) continue;
    for (const d of arr) {
      out.push({
        id: d.id,
        pack: d.pack ?? packId,
        country: d.country ?? '',
        answer: d.answer,
        letters_pool: d.letters_pool ?? [],
        riddle: pickFrenchString(d.riddle),
        explanation: pickFrenchString(d.explanation),
        proverb: pickFrenchString(d.proverb), // souvent absent en v3
        difficulty: mapDifficulty(d.difficulty),
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

async function audit() {
  console.log(`\n=== AUDIT Firestore collection 'devinettes' (project ${values.project}) ===\n`);

  const snap = await db
    .collection('devinettes')
    .where('enabled_for_duel', '==', true)
    .where('status', '==', 'approved')
    .get();

  const byDiff = { easy: 0, medium: 0, hard: 0, other: 0 };
  const byPack = {};
  for (const doc of snap.docs) {
    const data = doc.data();
    const d = data.difficulty ?? 'other';
    byDiff[d] = (byDiff[d] ?? 0) + 1;
    const p = data.pack ?? '(no pack)';
    byPack[p] = (byPack[p] ?? 0) + 1;
  }

  console.log(`Total docs enabled_for_duel + approved : ${snap.size}`);
  console.log('Par difficulte :');
  for (const [k, v] of Object.entries(byDiff)) {
    console.log(`  - ${k.padEnd(8)} : ${v}`);
  }
  console.log('Par pack :');
  for (const [k, v] of Object.entries(byPack)) {
    console.log(`  - ${k.padEnd(20)} : ${v}`);
  }
  console.log('');

  const seuil = 10;
  for (const diff of ['easy', 'medium', 'hard']) {
    if ((byDiff[diff] ?? 0) < seuil) {
      console.log(
        `⚠️  ${diff} < ${seuil} → la CF tirera souvent dans SAMPLE_DEVINETTES hardcodees.`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

async function seed() {
  const starterDir = resolve(values['starter-dir']);
  console.log(`\n=== SEED depuis ${starterDir} ===\n`);
  const devinettes = loadStarterDevinettes(starterDir);
  console.log(`Devinettes a upserter : ${devinettes.length}`);

  const byDiff = devinettes.reduce((acc, d) => {
    acc[d.difficulty] = (acc[d.difficulty] ?? 0) + 1;
    return acc;
  }, {});
  console.log('Distribution apres mapping :');
  for (const [k, v] of Object.entries(byDiff)) {
    console.log(`  - ${k.padEnd(8)} : ${v}`);
  }

  if (values['dry-run']) {
    console.log('\n[DRY RUN] Aucune ecriture. Exemple :');
    console.log(JSON.stringify(devinettes[0], null, 2));
    return;
  }

  // Batch 500 max par commit Firestore.
  let written = 0;
  for (let i = 0; i < devinettes.length; i += 400) {
    const batch = db.batch();
    const chunk = devinettes.slice(i, i + 400);
    for (const d of chunk) {
      const ref = db.collection('devinettes').doc(d.id);
      batch.set(
        ref,
        {
          answer: d.answer,
          letters_pool: d.letters_pool,
          riddle: d.riddle,
          explanation: d.explanation,
          proverb: d.proverb ?? '',
          difficulty: d.difficulty,
          pack: d.pack,
          country: d.country,
          enabled_for_duel: true,
          status: 'approved',
        },
        { merge: true },
      );
    }
    await batch.commit();
    written += chunk.length;
    console.log(`  → batch commit OK (${written}/${devinettes.length})`);
  }
  console.log(`\n✓ ${written} devinettes seedees.`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

(async () => {
  if (values.audit) await audit();
  if (values.seed) await seed();
  process.exit(0);
})().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
