#!/usr/bin/env node
/**
 * Corrige le champ `answer` des devinettes déjà publiées (ou en draft) dont
 * la valeur contient encore des accents — bug historique de `upsertDevinette`
 * / `packJobsShared` / `bulkImportDevinettes` qui sauvegardaient `answer` en
 * majuscules SANS retirer les accents, alors que `letters_pool` était déjà
 * généré depuis la forme normalisée. Résultat : mots comme « FÊTE »
 * invalidables côté client (la grille ne propose que des lettres sans
 * accent).
 *
 * Scanne `packs/{pack}/devinettes/{id}` (collectionGroup) et met à jour `answer`
 * pour qu'il corresponde à `answer_normalized` en majuscules — ne touche PAS
 * `letters_pool` (déjà correct).
 *
 * Usage:
 *   node functions/scripts/fix_accented_answers.js --dry-run   # défaut, aucune écriture
 *   node functions/scripts/fix_accented_answers.js --apply     # écrit réellement
 *
 * Auth : nécessite des identifiants admin valides (ADC via
 * `gcloud auth application-default login`, ou GOOGLE_APPLICATION_CREDENTIALS).
 */

const APPLY = process.argv.includes("--apply");

async function main() {
  const admin = require("firebase-admin");
  const { normalize } = require("../lib/utils/normalize");

  const projectId = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
  admin.initializeApp({ projectId });
  const db = admin.firestore();

  console.log(`Projet : ${projectId} — mode : ${APPLY ? "APPLY (écriture réelle)" : "DRY-RUN"}`);

  const snap = await db.collectionGroup("devinettes").get();
  console.log(`Total devinettes scannées : ${snap.size}`);

  const mismatches = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const currentAnswer = data.answer;
    if (typeof currentAnswer !== "string") continue;

    const correctAnswer = data.answer_normalized
      ? String(data.answer_normalized).toUpperCase()
      : normalize(currentAnswer.toUpperCase()).toUpperCase();

    if (currentAnswer !== correctAnswer) {
      mismatches.push({
        path: doc.ref.path,
        pack: data.pack,
        id: data.id,
        before: currentAnswer,
        after: correctAnswer,
        status: data.status,
      });
    }
  }

  console.log(`\nDevinettes avec accent résiduel dans "answer" : ${mismatches.length}`);
  const byPack = {};
  for (const m of mismatches) {
    byPack[m.pack] = (byPack[m.pack] || 0) + 1;
    console.log(`  [${m.status}] ${m.path} : "${m.before}" → "${m.after}"`);
  }
  console.log("\nRépartition par pack :", byPack);

  if (!APPLY) {
    console.log("\nDry-run terminé — relancer avec --apply pour écrire.");
    return;
  }

  console.log("\nÉcriture en cours...");
  const BATCH_SIZE = 400;
  for (let i = 0; i < mismatches.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = mismatches.slice(i, i + BATCH_SIZE);
    for (const m of chunk) {
      batch.update(db.doc(m.path), { answer: m.after });
    }
    await batch.commit();
    console.log(`  batch ${i / BATCH_SIZE + 1} : ${chunk.length} docs corrigés`);
  }
  console.log(`\n${mismatches.length} devinettes corrigées.`);
}

main().catch((e) => {
  console.error("Erreur :", e);
  process.exit(1);
});
