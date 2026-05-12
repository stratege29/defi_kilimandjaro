#!/usr/bin/env node
/**
 * Seed Firestore `packs` collection from build/seed_packs/manifests.json.
 *
 * Manifest format (one entry per pack):
 *   {
 *     "packs": [
 *       {
 *         "id": "village_des_or",
 *         "version": 2,
 *         "locale": "fr-CI",
 *         "title": "Village des Or",
 *         "objectPath": "village_des_or.json.gz",  // relative under packs/v2/
 *         "size": 12345,
 *         "sha256": "...",
 *         "tags": ["cuisine", "masque"]
 *       }
 *     ]
 *   }
 *
 * The script rewrites `url` to the canonical public bucket URL using the
 * --bucket flag, then upserts each pack into Firestore.
 *
 * Usage:
 *   node tools/scripts/seed_firestore.mjs \
 *     --bucket kilimandjaro-prod.appspot.com \
 *     --manifest build/seed_packs/manifests.json
 *
 * Auth: relies on Application Default Credentials. Run
 *   gcloud auth application-default login
 * once per machine.
 */

import { readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import process from 'node:process';

import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    bucket: { type: 'string' },
    manifest: { type: 'string' },
    project: { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
  },
});

if (!values.bucket || !values.manifest) {
  console.error(
    'usage: seed_firestore.mjs --bucket <bucket> --manifest <path> ' +
      '[--project <id>] [--dry-run]',
  );
  process.exit(64);
}

admin.initializeApp({
  projectId: values.project ?? process.env.GCLOUD_PROJECT,
});

const manifest = JSON.parse(readFileSync(values.manifest, 'utf8'));
if (!Array.isArray(manifest.packs)) {
  console.error('manifest missing "packs" array');
  process.exit(1);
}

const db = admin.firestore();
const collection = db.collection('packs');

const baseUrl = `https://firebasestorage.googleapis.com/v0/b/${values.bucket}/o`;

let written = 0;
for (const pack of manifest.packs) {
  if (!pack.id || !pack.objectPath) {
    console.warn('skipping pack without id/objectPath:', pack);
    continue;
  }
  const encodedPath = encodeURIComponent(`packs/v2/${pack.objectPath}`);
  const url = `${baseUrl}/${encodedPath}?alt=media`;

  const doc = {
    id: pack.id,
    version: pack.version ?? 1,
    locale: pack.locale ?? 'fr-CI',
    title: pack.title ?? pack.id,
    url,
    objectPath: `packs/v2/${pack.objectPath}`,
    bucket: values.bucket,
    size: pack.size ?? 0,
    sha256: pack.sha256 ?? null,
    tags: pack.tags ?? [],
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (values['dry-run']) {
    console.log(`[dry-run] packs/${pack.id} ←`, doc);
  } else {
    await collection.doc(pack.id).set(doc, { merge: true });
    console.log(`✓ packs/${pack.id} (${pack.objectPath})`);
  }
  written++;
}

console.log(`==> ${values['dry-run'] ? '[dry-run] ' : ''}wrote ${written} pack(s)`);
process.exit(0);
