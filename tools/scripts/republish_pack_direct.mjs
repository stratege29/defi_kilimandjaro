// Republie un pack OTA EN DIRECT via l'admin SDK (ADC), sans la Cloud Function
// callable publishPack (qui exige un ID token admin impossible à obtenir en
// script sans clé de service account).
//
// Reproduit fidèlement la logique de functions/src/admin/publishPack.ts +
// packArtifact.ts : fetch devinettes Firestore → artefact v3 (hash + gzip) →
// upload Storage → écritures content_packs / content_index / catalog / meta /
// versions + transitions de status + audit.
//
// Firestore ET Storage fonctionnent avec l'ADC (gcloud auth
// application-default login) — prouvé par reimport_football_ci.mjs.
//
// USAGE
//   node tools/scripts/republish_pack_direct.mjs --project kilimandjaro-dev \
//     --pack football_ci --bucket kilimandjaro-dev.firebasestorage.app
//   # ajoute --apply pour écrire réellement (sinon dry-run : build seulement)

import { parseArgs } from 'node:util';
import process from 'node:process';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    pack: { type: 'string', default: 'football_ci' },
    bucket: { type: 'string' },
    actor: { type: 'string', default: 'republish_pack_direct.mjs' },
    apply: { type: 'boolean', default: false },
  },
});

if (!values.project || !values.bucket) {
  console.error(
    'usage: --project <id> --bucket <bucket> [--pack football_ci] [--apply]',
  );
  process.exit(64);
}

const PACK_ID = values.pack;
const FORMAT_V3 = 3;
const DEFAULT_LANG = 'fr';
const MIN_APP_VERSION = '0.1.0';
const ACTOR = values.actor;

admin.initializeApp({
  projectId: values.project,
  storageBucket: values.bucket,
});
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// --- helpers (transcrits de packArtifact.ts / publishPack.ts) ---

function toDevinetteV3(data) {
  return {
    id: data.id,
    pack: data.pack,
    country: data.country,
    answer: data.answer,
    answer_normalized: data.answer_normalized,
    letters_pool: data.letters_pool,
    riddle: data.riddle,
    explanation: data.explanation,
    difficulty: data.difficulty,
    estimated_time_s: data.estimated_time_s ?? 30,
    tags: data.tags ?? [],
    format_version: FORMAT_V3,
  };
}

function detectLangs(devinettes) {
  const langs = new Set();
  for (const d of devinettes) {
    for (const k of Object.keys(d.riddle ?? {})) langs.add(k);
    for (const k of Object.keys(d.explanation ?? {})) langs.add(k);
  }
  if (langs.size === 0) return [DEFAULT_LANG];
  return [...langs].sort();
}

function buildPackPayloadV3(packId, packVersion, devinettes) {
  return {
    format_version: FORMAT_V3,
    pack_id: packId,
    pack_version: packVersion,
    langs: detectLangs(devinettes),
    default_lang: DEFAULT_LANG,
    min_app_version: MIN_APP_VERSION,
    count: devinettes.length,
    devinettes,
  };
}

function buildPackArtifact(packId, packVersion, devinettes) {
  const payload = buildPackPayloadV3(packId, packVersion, devinettes);
  const encoded1 = Buffer.from(JSON.stringify(payload), 'utf8');
  payload.hash_sha256 = createHash('sha256').update(encoded1).digest('hex');
  const encodedFinal = Buffer.from(JSON.stringify(payload), 'utf8');
  const hashFinal = createHash('sha256').update(encodedFinal).digest('hex');
  const gz = gzipSync(encodedFinal);
  return { payload, hashSha256: hashFinal, gz, sizeBytes: gz.length };
}

function storagePathFor(packId, v) {
  return `packs/v2/${packId}/${packId}-v${v}.json.gz`;
}
function downloadUrlFor(bucket, storagePath) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(
    storagePath,
  )}?alt=media`;
}

// --- 1. Fetch devinettes éligibles (draft|published, non deleted), triées ---
const packRef = db.collection('packs').doc(PACK_ID);
const snap = await packRef
  .collection('devinettes')
  .where('status', 'in', ['draft', 'published'])
  .get();

const raw = [];
const payload = [];
for (const doc of snap.docs) {
  const data = doc.data();
  if (data.deleted_at != null) continue;
  raw.push(doc);
  payload.push(toDevinetteV3(data));
}
raw.sort((a, b) => a.id.localeCompare(b.id));
payload.sort((a, b) => a.id.localeCompare(b.id));

if (payload.length === 0) {
  console.error(`ABORT: aucune devinette éligible dans ${PACK_ID}.`);
  process.exit(1);
}

// Sanity : pas de mojibake résiduel dans ce qu'on s'apprête à publier.
const stillCorrupt = payload.filter(
  (d) => /√|Ã|â€/.test(d.riddle?.fr ?? '') || /√|Ã|â€/.test(d.explanation?.fr ?? ''),
);
if (stillCorrupt.length > 0) {
  console.error(
    `ABORT: ${stillCorrupt.length} devinette(s) encore corrompues — ` +
      `relance d'abord reimport_football_ci.mjs --apply.`,
  );
  console.error('  ex:', stillCorrupt[0].id, stillCorrupt[0].riddle?.fr);
  process.exit(1);
}

// --- 2. Versions ---
const metaSnap = await packRef.collection('meta').doc('doc').get();
const currentVersion =
  (metaSnap.exists ? metaSnap.data()?.latest_published_version : 0) ?? 0;
const nextVersion = currentVersion + 1;

// --- 3. Artefact ---
const artifact = buildPackArtifact(PACK_ID, nextVersion, payload);
const storagePath = storagePathFor(PACK_ID, nextVersion);
const downloadUrl = downloadUrlFor(values.bucket, storagePath);

console.log('=== RÉPUBLICATION (direct admin SDK) ===');
console.log(`  pack            : ${PACK_ID}`);
console.log(`  devinettes      : ${payload.length}`);
console.log(`  version         : ${currentVersion} → ${nextVersion}`);
console.log(`  langs           : ${JSON.stringify(artifact.payload.langs)}`);
console.log(`  hash_sha256     : ${artifact.hashSha256}`);
console.log(`  size (gz)       : ${artifact.sizeBytes} bytes`);
console.log(`  storage_path    : ${storagePath}`);
console.log(`  download_url    : ${downloadUrl}`);
console.log(`  ex riddle[0]    : ${payload[0].riddle?.fr}`);

if (!values.apply) {
  console.log('\nDRY-RUN (aucune écriture). Relance avec --apply.');
  process.exit(0);
}

// --- 4. Upload Storage ---
const bucketRef = admin.storage().bucket();
await bucketRef.file(storagePath).save(artifact.gz, {
  contentType: 'application/json',
  metadata: {
    contentEncoding: 'gzip',
    cacheControl: 'public, max-age=86400',
    metadata: {
      hashSha256: artifact.hashSha256,
      packVersion: String(nextVersion),
      formatVersion: String(FORMAT_V3),
    },
  },
});
console.log(`\n✓ uploadé sur gs://${bucketRef.name}/${storagePath}`);

// --- 5. Écritures Firestore ---
// 5a. versions/<N> active
await packRef.collection('versions').doc(String(nextVersion)).set(
  {
    number: nextVersion,
    hash_sha256: artifact.hashSha256,
    size_bytes: artifact.sizeBytes,
    count: payload.length,
    storage_path: storagePath,
    download_url: downloadUrl,
    format_version: FORMAT_V3,
    langs: artifact.payload.langs,
    default_lang: DEFAULT_LANG,
    min_app_version: MIN_APP_VERSION,
    published_at: FieldValue.serverTimestamp(),
    published_by: ACTOR,
    status: 'active',
    previous_version: currentVersion > 0 ? currentVersion : null,
  },
  { merge: true },
);
// 5b. archive l'ancienne version
if (currentVersion > 0) {
  await packRef.collection('versions').doc(String(currentVersion)).set(
    {
      status: 'archived',
      archived_at: FieldValue.serverTimestamp(),
      archived_by: ACTOR,
    },
    { merge: true },
  );
}
// 5c. content_packs/<id>  (← LE manifeste que l'app lit pour l'OTA)
await db.collection('content_packs').doc(PACK_ID).set(
  {
    pack: PACK_ID,
    current_version: nextVersion,
    format_version: FORMAT_V3,
    hash_sha256: artifact.hashSha256,
    size_bytes: artifact.sizeBytes,
    count: payload.length,
    storage_path: storagePath,
    download_url: downloadUrl,
    min_app_version: MIN_APP_VERSION,
    langs: artifact.payload.langs,
    default_lang: DEFAULT_LANG,
    enabled: true,
    updated_at: FieldValue.serverTimestamp(),
  },
  { merge: true },
);
// 5d. content_index/global
await db.collection('content_index').doc('global').set(
  { packs: FieldValue.arrayUnion(PACK_ID), min_format_version: FORMAT_V3 },
  { merge: true },
);
// 5e. catalog/index : bump catalog_version (cache-bust clients)
const catalogVersion = await db.runTransaction(async (tx) => {
  const ref = db.collection('catalog').doc('index');
  const s = await tx.get(ref);
  const cur = (s.exists ? s.data()?.catalog_version : 0) ?? 0;
  const next = cur + 1;
  tx.set(ref, { catalog_version: next, updated_at: FieldValue.serverTimestamp() }, { merge: true });
  return next;
});
// 5f. meta
await packRef.collection('meta').doc('doc').set(
  {
    id: PACK_ID,
    latest_published_version: nextVersion,
    next_draft_version: nextVersion + 1,
    pending_changes: 0,
    updated_at: FieldValue.serverTimestamp(),
    updated_by: ACTOR,
  },
  { merge: true },
);

// --- 6. Transitions de status (draft → published) ---
let promoted = 0;
const BATCH = 400;
for (let i = 0; i < raw.length; i += BATCH) {
  const batch = db.batch();
  for (const doc of raw.slice(i, i + BATCH)) {
    if (doc.data().status === 'draft') {
      batch.update(doc.ref, {
        status: 'published',
        published_version: nextVersion,
        draft_version: null,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: ACTOR,
      });
      promoted++;
    }
  }
  await batch.commit();
}

// --- 7. Audit ---
await packRef.collection('audit').add({
  type: 'publish',
  actor_uid: ACTOR,
  timestamp: FieldValue.serverTimestamp(),
  details: {
    version: nextVersion,
    previous_version: currentVersion > 0 ? currentVersion : null,
    count: payload.length,
    hash_sha256: artifact.hashSha256,
    size_bytes: artifact.sizeBytes,
    promoted_drafts: promoted,
    note: 'republish direct (fix mojibake accents) — bypass callable',
  },
});

console.log(
  `\n✅ Publié v${nextVersion} (catalog_version=${catalogVersion}, ` +
    `${promoted} drafts promus). Les clients re-téléchargeront au prochain sync OTA.`,
);
process.exit(0);
