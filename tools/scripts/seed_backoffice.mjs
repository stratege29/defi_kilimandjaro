#!/usr/bin/env node
/**
 * Migration one-shot : pousse les packs existants vers les nouvelles
 * collections Firestore du backoffice (Phase 1).
 *
 * Source :
 *   - assets/data/devinettes/starter/_index.json  (catalogue local)
 *   - assets/data/devinettes/starter/<packId>.json (starter bundlé)
 *   - content/ota_packs/<packId>.json (additions OTA, optionnel)
 *   - assets/data/i18n/{fr,en}.json (traductions packs)
 *
 * Cible Firestore :
 *   - catalog/index                   (catalogue enrichi pour Phase 3 client)
 *   - catalog/tags_whitelist          (tous les tags actuellement utilisés)
 *   - packs/{packId}/meta             (latest_published_version, etc.)
 *   - packs/{packId}/i18n/{lang}      (nom + description par langue)
 *   - packs/{packId}/devinettes/{id}  (1 doc par devinette, status=published)
 *   - packs/{packId}/versions/{N}     (snapshot manifest, status=active)
 *
 * NE TOUCHE PAS aux collections existantes rétrocompat :
 *   - content_packs/{packId}          (géré par seed_firestore_packs.mjs)
 *   - content_index/global            (idem)
 *   - submissions / matches_history   (sans rapport)
 *
 * Idempotent : utilise `set merge` partout. Re-jouer = pas d'effet de bord.
 *
 * Usage :
 *   node tools/scripts/seed_backoffice.mjs --project kilimandjaro-dev
 *   node tools/scripts/seed_backoffice.mjs --project kilimandjaro-prod --dry-run
 *   node tools/scripts/seed_backoffice.mjs --project kilimandjaro-dev \
 *     --skip-tags --skip-i18n --skip-versions
 *
 * Auth : Application Default Credentials
 *   gcloud auth application-default login
 *   gcloud config set project kilimandjaro-dev
 *
 * Voir docs/backoffice_schema.md §9 (Migration depuis l'existant).
 */

import { readFileSync, existsSync } from 'node:fs';
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
    'ota-dir': { type: 'string', default: 'content/ota_packs' },
    'i18n-dir': { type: 'string', default: 'assets/data/i18n' },
    'dry-run': { type: 'boolean', default: false },
    'skip-catalog': { type: 'boolean', default: false },
    'skip-tags': { type: 'boolean', default: false },
    'skip-meta': { type: 'boolean', default: false },
    'skip-i18n': { type: 'boolean', default: false },
    'skip-devinettes': { type: 'boolean', default: false },
    'skip-versions': { type: 'boolean', default: false },
  },
});

if (!values.project) {
  console.error(
    'usage: node tools/scripts/seed_backoffice.mjs --project <id> [--dry-run] [--skip-X]',
  );
  process.exit(64);
}

admin.initializeApp({ projectId: values.project });
const db = admin.firestore();

const STARTER_DIR = resolve(values['starter-dir']);
const OTA_DIR = resolve(values['ota-dir']);
const I18N_DIR = resolve(values['i18n-dir']);

const DRY = values['dry-run'];
const log = (msg) => console.log(DRY ? `[DRY] ${msg}` : msg);

// ===========================================================================
// 1. Chargement des sources
// ===========================================================================

function loadJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

function loadIndex() {
  const indexPath = join(STARTER_DIR, '_index.json');
  if (!existsSync(indexPath)) {
    throw new Error(`Index introuvable: ${indexPath}`);
  }
  return loadJson(indexPath);
}

function loadStarterDevinettes(packId) {
  const path = join(STARTER_DIR, `${packId}.json`);
  if (!existsSync(path)) return [];
  const arr = loadJson(path);
  return Array.isArray(arr) ? arr : [];
}

function loadOtaDevinettes(packId) {
  const path = join(OTA_DIR, `${packId}.json`);
  if (!existsSync(path)) return [];
  const arr = loadJson(path);
  return Array.isArray(arr) ? arr : [];
}

/**
 * Merge starter + ota : pour un même id, ota override (même règle que
 * tool/seed_content_packs.dart pour rester cohérent côté serveur).
 */
function mergeDevinettes(starter, ota) {
  if (!ota.length) return starter;
  const byId = new Map();
  const order = [];
  for (const d of starter) {
    if (!d.id) continue;
    byId.set(d.id, d);
    order.push(d.id);
  }
  for (const d of ota) {
    if (!d.id) continue;
    if (!byId.has(d.id)) order.push(d.id);
    byId.set(d.id, d);
  }
  return order.map((id) => byId.get(id));
}

function loadI18n() {
  const fr = existsSync(join(I18N_DIR, 'fr.json'))
    ? loadJson(join(I18N_DIR, 'fr.json'))
    : {};
  const en = existsSync(join(I18N_DIR, 'en.json'))
    ? loadJson(join(I18N_DIR, 'en.json'))
    : {};
  return { fr, en };
}

function packI18n(i18nAll, packId) {
  const out = {};
  for (const lang of ['fr', 'en']) {
    const block = i18nAll[lang]?.pack?.[packId];
    if (!block) continue;
    out[lang] = {
      lang,
      name: block.name ?? '',
      description: block.description ?? '',
      short_tagline: block.short_tagline ?? '',
    };
  }
  return out;
}

// ===========================================================================
// 2. Construction du catalogue distant
// ===========================================================================

function buildCatalogIndex(index, packsData) {
  const STARTER_BUNDLED = new Set(['culture_ci', 'crack_nouchi']);
  const ORDERING = { culture_ci: 10, crack_nouchi: 20, football_ci: 30 };
  const THEME_COLORS = {
    culture_ci: '#E07A19',
    crack_nouchi: '#5E2BFF',
    football_ci: '#1F8A3D',
  };

  const list = [];
  for (const [packId, indexEntry] of Object.entries(index.packs)) {
    const bundled = STARTER_BUNDLED.has(packId);
    const pack = packsData[packId];
    list.push({
      id: packId,
      visible: true,
      ordering: ORDERING[packId] ?? 100,
      bundled,
      free_choice_eligible: indexEntry.free_choice_eligible ?? false,
      // Bundle packs gratuits (déjà offerts au choix), autres payants
      unlock_cost_cauris: bundled ? 0 : (indexEntry.price_cauris ?? 2000),
      available_from: null,
      available_until: null,
      min_app_version: '0.1.0',
      theme_color_hex: THEME_COLORS[packId] ?? '#888888',
      icon_url: null, // à uploader plus tard via UI admin
      tags: deduceCatalogTags(packId),
      count: pack?.devinettes?.length ?? indexEntry.count ?? 0,
      current_version: indexEntry.current_version ?? 1,
    });
  }
  list.sort((a, b) => a.ordering - b.ordering);
  return list;
}

function deduceCatalogTags(packId) {
  // Tags marketing par pack (≠ tags devinettes individuels)
  if (packId === 'culture_ci') return ['culture', 'tradition', 'cuisine'];
  if (packId === 'crack_nouchi') return ['langage', 'argot', 'urbain'];
  if (packId === 'football_ci') return ['sport', 'eleph', 'football'];
  return [];
}

// ===========================================================================
// 3. Whitelist tags devinettes
// ===========================================================================

function computeTagsWhitelist(packsData) {
  const set = new Set();
  for (const pack of Object.values(packsData)) {
    for (const d of pack.devinettes) {
      for (const t of d.tags ?? []) {
        if (typeof t === 'string' && t.trim()) {
          set.add(t.toLowerCase().trim());
        }
      }
    }
  }
  return [...set].sort();
}

// ===========================================================================
// 4. Pushers Firestore
// ===========================================================================

async function pushCatalogIndex(catalogList) {
  log(`catalog/index : ${catalogList.length} packs (catalog_version=1)`);
  if (!DRY) {
    await db.collection('catalog').doc('index').set(
      {
        schema_version: 4,
        catalog_version: 1,
        packs: catalogList,
        seeded_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function pushTagsWhitelist(tags) {
  log(`catalog/tags_whitelist : ${tags.length} tags uniques`);
  if (tags.length <= 20) {
    log(`  Tags: ${tags.join(', ')}`);
  } else {
    log(`  Premiers tags: ${tags.slice(0, 20).join(', ')}... +${tags.length - 20}`);
  }
  if (!DRY) {
    await db.collection('catalog').doc('tags_whitelist').set(
      {
        tags,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        seeded_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function pushPackMeta(packId, indexEntry, devinetteCount) {
  const currentVersion = indexEntry.current_version ?? 1;
  log(
    `packs/${packId}/meta/doc : latest_v=${currentVersion}, next_draft=${currentVersion + 1}, count=${devinetteCount}`,
  );
  if (!DRY) {
    await db
      .collection('packs')
      .doc(packId)
      .collection('meta')
      .doc('doc')
      .set(
        {
          id: packId,
          bundled: ['culture_ci', 'crack_nouchi'].includes(packId),
          latest_published_version: currentVersion,
          next_draft_version: currentVersion + 1,
          pending_changes: 0,
          seeded_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }
}

async function pushPackI18n(packId, i18nData) {
  for (const [lang, doc] of Object.entries(i18nData)) {
    log(`packs/${packId}/i18n/${lang} : "${doc.name}"`);
    if (!DRY) {
      await db
        .collection('packs')
        .doc(packId)
        .collection('i18n')
        .doc(lang)
        .set(
          {
            ...doc,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            seeded_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
    }
  }
}

async function pushPackDevinettes(packId, devinettes, currentVersion) {
  log(`packs/${packId}/devinettes : ${devinettes.length} docs (status=published, v=${currentVersion})`);

  // Batches de 400 (limite Firestore 500/batch)
  let written = 0;
  for (let i = 0; i < devinettes.length; i += 400) {
    const chunk = devinettes.slice(i, i + 400);
    if (!DRY) {
      const batch = db.batch();
      for (const d of chunk) {
        const ref = db
          .collection('packs')
          .doc(packId)
          .collection('devinettes')
          .doc(d.id);
        batch.set(
          ref,
          {
            // Contenu format v3
            id: d.id,
            pack: d.pack ?? packId,
            country: d.country ?? 'ci',
            answer: d.answer,
            answer_normalized: d.answer_normalized,
            letters_pool: d.letters_pool,
            riddle: d.riddle ?? {},
            explanation: d.explanation ?? {},
            difficulty: d.difficulty,
            estimated_time_s: d.estimated_time_s ?? 30,
            tags: d.tags ?? [],
            format_version: 3,
            // Cycle de vie backoffice
            status: 'published',
            published_version: currentVersion,
            draft_version: null,
            deleted_at: null,
            seeded_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      await batch.commit();
    }
    written += chunk.length;
    process.stdout.write(`\r  → ${written}/${devinettes.length} `);
  }
  if (devinettes.length > 0) process.stdout.write('\n');
}

async function pushPackVersion(packId, currentVersion, devinetteCount) {
  log(`packs/${packId}/versions/${currentVersion} : status=active (placeholder)`);
  if (!DRY) {
    await db
      .collection('packs')
      .doc(packId)
      .collection('versions')
      .doc(String(currentVersion))
      .set(
        {
          number: currentVersion,
          count: devinetteCount,
          // Les champs hash/storage_path/download_url ne sont PAS connus ici
          // (ils sont calculés par publishPack). Ce doc est un placeholder
          // qui sera enrichi lors du prochain publish OU peut être laissé tel
          // quel si on lit le manifest depuis content_packs/<id>.
          format_version: 3,
          langs: ['fr'],
          default_lang: 'fr',
          min_app_version: '0.1.0',
          status: 'active',
          seeded: true,
          seeded_at: admin.firestore.FieldValue.serverTimestamp(),
          published_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }
}

// ===========================================================================
// 5. Main
// ===========================================================================

async function main() {
  console.log(`Project   : ${values.project}`);
  console.log(`Starter   : ${STARTER_DIR}`);
  console.log(`OTA       : ${OTA_DIR}`);
  console.log(`i18n      : ${I18N_DIR}`);
  console.log(`Dry run   : ${DRY}`);
  console.log('');

  const index = loadIndex();
  const i18nAll = loadI18n();

  // Charge et fusionne les devinettes par pack
  const packsData = {};
  for (const packId of Object.keys(index.packs)) {
    const starter = loadStarterDevinettes(packId);
    const ota = loadOtaDevinettes(packId);
    const merged = mergeDevinettes(starter, ota);
    packsData[packId] = {
      devinettes: merged,
      i18n: packI18n(i18nAll, packId),
      starterCount: starter.length,
      otaCount: ota.length,
    };
    console.log(
      `  ${packId} : ${starter.length} starter + ${ota.length} OTA = ${merged.length} total`,
    );
  }
  console.log('');

  // 1. catalog/index
  if (!values['skip-catalog']) {
    const catalogList = buildCatalogIndex(index, packsData);
    await pushCatalogIndex(catalogList);
  }

  // 2. catalog/tags_whitelist
  if (!values['skip-tags']) {
    const tags = computeTagsWhitelist(packsData);
    await pushTagsWhitelist(tags);
  }

  // 3. Par pack : meta + i18n + devinettes + versions
  for (const [packId, data] of Object.entries(packsData)) {
    const indexEntry = index.packs[packId];
    const currentVersion = indexEntry.current_version ?? 1;
    console.log(`\n--- ${packId} ---`);

    if (!values['skip-meta']) {
      await pushPackMeta(packId, indexEntry, data.devinettes.length);
    }
    if (!values['skip-i18n']) {
      await pushPackI18n(packId, data.i18n);
    }
    if (!values['skip-devinettes']) {
      await pushPackDevinettes(packId, data.devinettes, currentVersion);
    }
    if (!values['skip-versions']) {
      await pushPackVersion(packId, currentVersion, data.devinettes.length);
    }
  }

  console.log(
    DRY
      ? '\n[DRY RUN] Aucune écriture effectuée.'
      : '\n✓ Backoffice seedé.',
  );
}

main().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
