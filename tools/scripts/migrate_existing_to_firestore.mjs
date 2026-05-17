#!/usr/bin/env node
/**
 * Migration one-shot — seed Firestore avec les packs existants
 *   (starter/*.json + content/ota_packs/*.json), conformément au schéma
 *   exploité par le backoffice / la Cloud Function `publishPack`.
 *
 *   - `content_packs/{packId}` : métadonnées (name, description, country,
 *     prices, enabled=false par défaut). PAS de manifest — la première
 *     publication via `publishPack` le générera.
 *
 *   - `content_packs/{packId}/questions/{questionId}` : un doc par question,
 *     id du doc = id de la question (format v3 strict).
 *
 * Merge rule (alignée sur tool/seed_content_packs.dart) :
 *   - starter[id] ∪ ota[id]  →  ota override sur même id
 *   - ids exclusivement starter : conservés
 *   - ids exclusivement ota    : appendés
 *
 * Idempotent : `set(..., {merge: true})` sur métadonnées + questions.
 *
 * Auth : Application Default Credentials.
 *   gcloud auth application-default login
 *
 * Usage :
 *   node tools/scripts/migrate_existing_to_firestore.mjs --project kilimandjaro-dev
 *   node tools/scripts/migrate_existing_to_firestore.mjs --project kilimandjaro-dev --dry-run
 */

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import process from "node:process";

import admin from "firebase-admin";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");

const { values } = parseArgs({
  options: {
    project: { type: "string" },
    "dry-run": { type: "boolean", default: false },
    "starter-dir": {
      type: "string",
      default: "assets/data/devinettes/starter",
    },
    "ota-dir": {
      type: "string",
      default: "content/ota_packs",
    },
  },
});

if (!values.project) {
  console.error(
    "usage: node tools/scripts/migrate_existing_to_firestore.mjs " +
      "--project <id> [--dry-run]"
  );
  process.exit(64);
}

const starterDir = resolve(repoRoot, values["starter-dir"]);
const otaDir = resolve(repoRoot, values["ota-dir"]);

if (!existsSync(starterDir)) {
  console.error(`Starter dir introuvable : ${starterDir}`);
  process.exit(1);
}

// Charge l'index des packs starter.
const indexPath = join(starterDir, "_index.json");
if (!existsSync(indexPath)) {
  console.error(`Index introuvable : ${indexPath}`);
  process.exit(1);
}
const indexJson = JSON.parse(readFileSync(indexPath, "utf8"));
const packsIndex = indexJson.packs ?? {};

admin.initializeApp({ projectId: values.project });
const db = admin.firestore();

console.log(`Project : ${values.project}`);
console.log(`Starter : ${starterDir}`);
console.log(`OTA     : ${otaDir}`);
console.log(`Dry run : ${values["dry-run"] ? "OUI" : "non"}\n`);

let totalQuestions = 0;
let totalPacks = 0;

for (const [packId, meta] of Object.entries(packsIndex)) {
  const starterFile = join(starterDir, `${packId}.json`);
  if (!existsSync(starterFile)) {
    console.log(`  • ${packId} : fichier starter manquant — skip.`);
    continue;
  }
  const starter = JSON.parse(readFileSync(starterFile, "utf8"));
  const otaFile = join(otaDir, `${packId}.json`);
  const ota = existsSync(otaFile)
    ? JSON.parse(readFileSync(otaFile, "utf8"))
    : [];

  const merged = mergeById(starter, ota);
  console.log(
    `  • ${packId} : starter=${starter.length} ota=${ota.length} merged=${merged.length}`
  );

  // 1. Doc pack (métadonnées éditables seulement — PAS le manifest).
  const packDoc = {
    name: meta.name_key ?? packId,
    description: meta.description_key ?? "",
    country: detectCountry(merged) ?? "ci",
    enabled: false, // sera flip côté backoffice après vérification
    free_choice_eligible: meta.free_choice_eligible ?? false,
    price_eur: meta.price_eur ?? 2.99,
    price_cauris: meta.price_cauris ?? 2000,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!values["dry-run"]) {
    await db.collection("content_packs").doc(packId).set(packDoc, { merge: true });
  }

  // 2. Sous-collection questions.
  const batchSize = 400;
  for (let i = 0; i < merged.length; i += batchSize) {
    const slice = merged.slice(i, i + batchSize);
    if (values["dry-run"]) {
      console.log(`    [dry] batch ${i / batchSize + 1} : ${slice.length} questions`);
      continue;
    }
    const batch = db.batch();
    for (const q of slice) {
      const ref = db
        .collection("content_packs")
        .doc(packId)
        .collection("questions")
        .doc(q.id);
      batch.set(
        ref,
        {
          ...q,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          // created_at est posé uniquement si absent (preserve l'historique).
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    await batch.commit();
    console.log(
      `    ✓ batch ${i / batchSize + 1} commit : ${slice.length} questions`
    );
  }

  totalPacks++;
  totalQuestions += merged.length;
}

console.log(
  `\n${values["dry-run"] ? "[DRY RUN] " : ""}Terminé : ${totalPacks} packs · ${totalQuestions} questions.`
);
process.exit(0);

// ---------------------------------------------------------------------------

function mergeById(starter, additions) {
  if (!Array.isArray(additions) || additions.length === 0) return starter;
  const byId = new Map();
  const order = [];
  for (const entry of starter) {
    if (!entry?.id) continue;
    byId.set(entry.id, entry);
    order.push(entry.id);
  }
  for (const entry of additions) {
    if (!entry?.id) continue;
    if (!byId.has(entry.id)) order.push(entry.id);
    byId.set(entry.id, entry);
  }
  return order.map((id) => byId.get(id));
}

function detectCountry(questions) {
  for (const q of questions) {
    if (typeof q?.country === "string") return q.country;
  }
  return null;
}
