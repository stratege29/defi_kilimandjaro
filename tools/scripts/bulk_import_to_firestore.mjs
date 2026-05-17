#!/usr/bin/env node
/**
 * Bulk import questions vers Firestore subcollections.
 *
 * Lit un fichier JSON (tableau de questions format v3), pour chaque entrée
 * écrit `content_packs/{packId}/questions/{questionId}` via `set(..., merge:true)`.
 * Idempotent : ré-exécuter ne crée pas de doublon.
 *
 * Usage :
 *   node tools/scripts/bulk_import_to_firestore.mjs \
 *     --project kilimandjaro-dev \
 *     --pack culture_ci \
 *     --file content/round_3/culture_ci.json \
 *     [--dry-run]
 *
 * Auth : ADC (gcloud auth application-default login).
 */

import { readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import process from 'node:process';
import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    pack: { type: 'string' },
    file: { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
  },
});

if (!values.project || !values.pack || !values.file) {
  console.error(
    'usage: node bulk_import_to_firestore.mjs --project <id> --pack <packId> --file <path> [--dry-run]',
  );
  process.exit(64);
}

admin.initializeApp({ projectId: values.project });
const db = admin.firestore();

const raw = JSON.parse(readFileSync(values.file, 'utf8'));
if (!Array.isArray(raw)) {
  console.error(`${values.file} doit contenir un tableau JSON.`);
  process.exit(1);
}

// Filtre les entrées appartenant au pack ciblé (au cas où le fichier en contient
// plusieurs ou est mélangé avec un starter).
const entries = raw.filter((q) => q.pack === values.pack);
if (entries.length === 0) {
  console.error(`Aucune entrée avec pack="${values.pack}" dans ${values.file}.`);
  process.exit(1);
}

console.log(`Project : ${values.project}`);
console.log(`Pack    : ${values.pack}`);
console.log(`Source  : ${values.file}`);
console.log(`Match   : ${entries.length} questions (sur ${raw.length} totales)`);
console.log(`Dry run : ${values['dry-run'] ? 'OUI' : 'non'}\n`);

// Validation rapide côté script (le backoffice valide aussi côté UI).
const errors = [];
for (const q of entries) {
  if (!q.id) errors.push('id manquant');
  if (!q.answer) errors.push(`${q.id}: answer manquant`);
  if (q.answer && (q.answer.length < 4 || q.answer.length > 8)) {
    errors.push(`${q.id}: answer "${q.answer}" longueur ${q.answer.length} hors [4,8]`);
  }
  if (q.format_version !== 3) {
    errors.push(`${q.id}: format_version=${q.format_version} attendu 3`);
  }
}
if (errors.length) {
  console.error('Erreurs de validation :');
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

const ref = db.collection('content_packs').doc(values.pack).collection('questions');

if (values['dry-run']) {
  for (const q of entries) console.log(`  [dry] ${q.id} (${q.answer})`);
  console.log(`\n[DRY RUN] ${entries.length} questions seraient écrites.`);
  process.exit(0);
}

// Batches de 400 (limite Firestore = 500 writes par batch).
const now = admin.firestore.FieldValue.serverTimestamp();
const chunkSize = 400;
let written = 0;
for (let i = 0; i < entries.length; i += chunkSize) {
  const slice = entries.slice(i, i + chunkSize);
  const batch = db.batch();
  for (const q of slice) {
    const docRef = ref.doc(q.id);
    batch.set(docRef, { ...q, updated_at: now, created_at: now }, { merge: true });
  }
  await batch.commit();
  written += slice.length;
  console.log(`  ✓ batch ${Math.ceil(i / chunkSize) + 1} commit : ${slice.length} questions`);
}

console.log(`\nTerminé : ${written} questions importées dans content_packs/${values.pack}/questions/`);
process.exit(0);
