#!/usr/bin/env node
/**
 * Seed les docs Firestore pour les packs OTA :
 *   - content_packs/<packId>  (manifests, lus depuis build/seed_packs/manifests.json)
 *   - content_index/global    (liste des packs actifs)
 *
 * Idempotent : utilise `set()` (overwrite complet).
 *
 * Usage :
 *   node tool/seed_firestore_packs.mjs --project kilimandjaro-dev --bucket kilimandjaro-dev.firebasestorage.app
 *   node tool/seed_firestore_packs.mjs --project kilimandjaro-dev --bucket kilimandjaro-dev.firebasestorage.app --dry-run
 *
 * Auth : Application Default Credentials (gcloud auth application-default login).
 */

import { readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import process from 'node:process';

import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    bucket: { type: 'string' },
    manifest: { type: 'string', default: 'build/seed_packs/manifests.json' },
    'dry-run': { type: 'boolean', default: false },
  },
});

if (!values.project || !values.bucket) {
  console.error(
    'usage: node tool/seed_firestore_packs.mjs --project <id> --bucket <bucket> [--manifest <path>] [--dry-run]',
  );
  process.exit(64);
}

admin.initializeApp({ projectId: values.project });
const db = admin.firestore();

const manifests = JSON.parse(readFileSync(values.manifest, 'utf8'));
const packIds = Object.keys(manifests);

console.log(`Project : ${values.project}`);
console.log(`Bucket  : ${values.bucket}`);
console.log(`Manifest: ${values.manifest} (${packIds.length} packs)\n`);

for (const packId of packIds) {
  const m = { ...manifests[packId] };
  // Réécrit le download_url avec le bucket réel (le manifest stocke <BUCKET> placeholder).
  m.download_url = m.download_url.replace('<BUCKET>', values.bucket);

  console.log(`content_packs/${packId} :`);
  console.log(`  pack=${m.pack}  v${m.current_version}  count=${m.count}  hash=${m.hash_sha256.slice(0, 12)}…`);

  if (!values['dry-run']) {
    await db.collection('content_packs').doc(packId).set(m);
  }
}

console.log(`\ncontent_index/global :`);
console.log(`  packs=${packIds.join(', ')}`);

if (!values['dry-run']) {
  await db.collection('content_index').doc('global').set({
    packs: packIds,
    min_format_version: 3,
  });
}

console.log(
  values['dry-run']
    ? '\n[DRY RUN] Aucune écriture effectuée.'
    : '\n✓ Firestore seedé.',
);
process.exit(0);
