// ignore_for_file: n/a (Node script)
//
// Répare les accents corrompus (mojibake « √â / √© ») des devinettes du pack
// football_ci dans Firestore.
//
// CONTEXTE
//   Le fichier source `content/ota_packs/football_ci.json` est 100% propre
//   (UTF-8 correct). La corruption vit uniquement dans les docs Firestore
//   `packs/football_ci/devinettes/<id>` — entrée historiquement via un
//   copier-coller (texte passé par un outil Mac → UTF-8 lu comme MacRoman
//   puis ré-encodé). publishPack a ensuite gzippé fidèlement ce mojibake.
//
// CE QUE FAIT CE SCRIPT
//   Lit le fichier source DIRECTEMENT en utf8 (jamais via presse-papier, pour
//   ne pas réintroduire la corruption), puis réécrit UNIQUEMENT les champs
//   texte accentués `riddle` et `explanation` de chaque doc, matché par `id`.
//   Tout le reste (status, draft_version, published_version, answer_normalized,
//   letters_pool, timestamps…) est PRÉSERVÉ — set({merge:true}) ciblé.
//
//   Il ne publie PAS. Après exécution, relancer `publishPack({packId:
//   'football_ci'})` depuis l'admin console pour régénérer le .gz propre et
//   bumper la version (les clients re-téléchargent).
//
// AUTH
//   Utilise Application Default Credentials (comme seed_firestore_devinettes).
//   Prérequis : `gcloud auth application-default login` (le fichier ADC doit
//   exister dans ~/.config/gcloud/).
//
// USAGE
//   cd tools/scripts && npm install   # si firebase-admin pas encore installé
//   # 1. Inspection (par défaut, n'écrit RIEN) :
//   node tools/scripts/reimport_football_ci.mjs --project kilimandjaro-dev
//   # 2. Appliquer réellement :
//   node tools/scripts/reimport_football_ci.mjs --project kilimandjaro-dev --apply

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import process from 'node:process';

import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    apply: { type: 'boolean', default: false },
  },
});

if (!values.project) {
  console.error(
    'usage: node tools/scripts/reimport_football_ci.mjs --project <id> [--apply]',
  );
  process.exit(64);
}

const PACK_ID = 'football_ci';
const BATCH_SIZE = 400; // limite Firestore 500 ops/batch, marge de sécurité
const APPLY = values.apply === true;

// --- Localise le fichier source relativement au repo (script dans tools/scripts) ---
const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..', '..');
const sourcePath = join(repoRoot, 'content', 'ota_packs', `${PACK_ID}.json`);

// --- Détecteur de mojibake (caractères typiques du double-encodage MacRoman) ---
function looksCorrupted(s) {
  return typeof s === 'string' && /√|Ã|â€|Â/.test(s);
}

function frOf(field) {
  if (typeof field === 'string') return field;
  if (field && typeof field === 'object') return field.fr ?? null;
  return null;
}

// --- 1. Charge la source propre (utf8 explicite) ---
const rawText = readFileSync(sourcePath, { encoding: 'utf8' });
const sourceJson = JSON.parse(rawText);
const sourceArr = Array.isArray(sourceJson)
  ? sourceJson
  : sourceJson.devinettes;
if (!Array.isArray(sourceArr)) {
  console.error(`Format inattendu dans ${sourcePath}`);
  process.exit(1);
}

// Sanity : le fichier source NE doit PAS contenir de mojibake.
const corruptInSource = sourceArr.filter(
  (d) => looksCorrupted(frOf(d.riddle)) || looksCorrupted(frOf(d.explanation)),
);
if (corruptInSource.length > 0) {
  console.error(
    `ABORT: ${corruptInSource.length} entrée(s) du fichier source semblent ` +
      `déjà corrompues — corrige ${sourcePath} d'abord.`,
  );
  console.error('  ex:', corruptInSource[0].id, frOf(corruptInSource[0].riddle));
  process.exit(1);
}

const cleanById = new Map();
for (const d of sourceArr) {
  if (d && typeof d.id === 'string') {
    cleanById.set(d.id, { riddle: d.riddle ?? {}, explanation: d.explanation ?? {} });
  }
}
console.log(`Source : ${cleanById.size} devinettes propres lues depuis ${sourcePath}`);

// --- 2. Init Firestore (ADC) ---
admin.initializeApp({ projectId: values.project });
const db = admin.firestore();

const devsRef = db.collection('packs').doc(PACK_ID).collection('devinettes');

const snap = await devsRef.get();
console.log(`Firestore : ${snap.size} docs dans packs/${PACK_ID}/devinettes\n`);

// --- 3. Diff ---
const toUpdate = []; // { id, ref, before, after }
const missingInFirestore = [];
const notInSource = [];
let corruptedCount = 0;
let alreadyCleanCount = 0;

const firestoreIds = new Set();
for (const doc of snap.docs) {
  firestoreIds.add(doc.id);
  const data = doc.data();
  const clean = cleanById.get(doc.id);
  if (!clean) {
    notInSource.push(doc.id);
    continue;
  }
  const curRiddle = frOf(data.riddle);
  const curExpl = frOf(data.explanation);
  const newRiddle = frOf(clean.riddle);
  const newExpl = frOf(clean.explanation);

  const riddleDiffers = curRiddle !== newRiddle;
  const explDiffers = curExpl !== newExpl;
  if (looksCorrupted(curRiddle) || looksCorrupted(curExpl)) corruptedCount += 1;

  if (riddleDiffers || explDiffers) {
    toUpdate.push({
      id: doc.id,
      ref: doc.ref,
      before: { riddle: curRiddle, explanation: curExpl },
      after: { riddle: clean.riddle, explanation: clean.explanation },
    });
  } else {
    alreadyCleanCount += 1;
  }
}
for (const id of cleanById.keys()) {
  if (!firestoreIds.has(id)) missingInFirestore.push(id);
}

// --- 4. Rapport ---
console.log('=== RAPPORT ===');
console.log(`  docs déjà identiques à la source : ${alreadyCleanCount}`);
console.log(`  docs avec mojibake détecté       : ${corruptedCount}`);
console.log(`  docs à mettre à jour (diff)      : ${toUpdate.length}`);
console.log(`  ids dans source absents Firestore: ${missingInFirestore.length}`);
console.log(`  ids Firestore absents de source  : ${notInSource.length}`);
if (missingInFirestore.length) {
  console.log('    (missing)', missingInFirestore.slice(0, 10).join(', '),
    missingInFirestore.length > 10 ? '…' : '');
}
if (notInSource.length) {
  console.log('    (orphelins)', notInSource.slice(0, 10).join(', '),
    notInSource.length > 10 ? '…' : '');
}
console.log('');
for (const u of toUpdate.slice(0, 3)) {
  console.log(`  ex ${u.id}:`);
  console.log(`    avant  riddle: ${JSON.stringify(u.before.riddle)}`);
  console.log(`    après  riddle: ${JSON.stringify(frOf(u.after.riddle))}`);
}
console.log('');

if (!APPLY) {
  console.log('DRY-RUN (aucune écriture). Relance avec --apply pour appliquer.');
  process.exit(0);
}

if (toUpdate.length === 0) {
  console.log('Rien à mettre à jour. Terminé.');
  process.exit(0);
}

// --- 5. Écriture par batches (merge ciblé : riddle + explanation seulement) ---
const now = admin.firestore.FieldValue.serverTimestamp();
let written = 0;
for (let i = 0; i < toUpdate.length; i += BATCH_SIZE) {
  const batch = db.batch();
  for (const u of toUpdate.slice(i, i + BATCH_SIZE)) {
    batch.set(
      u.ref,
      {
        riddle: u.after.riddle,
        explanation: u.after.explanation,
        updated_at: now,
        updated_by: 'reimport_football_ci.mjs',
      },
      { merge: true },
    );
  }
  await batch.commit();
  written += Math.min(BATCH_SIZE, toUpdate.length - i);
  console.log(`  …${written}/${toUpdate.length} écrits`);
}

console.log(`\nOK : ${written} devinettes réparées.`);
console.log(
  'PROCHAINE ÉTAPE : republier le pack pour régénérer le .gz propre →\n' +
    '  admin console → pack football_ci → Publier  (ou appeler publishPack({packId:"football_ci"}))',
);
process.exit(0);
