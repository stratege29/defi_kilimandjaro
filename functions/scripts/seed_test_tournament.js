#!/usr/bin/env node
/**
 * Crée un tournoi « arène » de test dans Firestore (collection `tournaments`).
 *
 * En attendant l'UI admin (repo `kilimandjaro-admin`), ce script permet de
 * tester le mode tournoi de bout en bout. Le `tournamentTicker` (CF planifiée)
 * passera ensuite le tournoi `scheduled → live → finished` automatiquement.
 *
 * Le statut est posé directement (`scheduled` par défaut, ou `live` avec
 * `--start-now`) pour ne pas attendre le ticker en dev.
 *
 * Usage :
 *   # tournoi qui démarre dans 2 min, durée 20 min (émulateur)
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 GOOGLE_CLOUD_PROJECT=kilimandjaro-dev \
 *     node functions/scripts/seed_test_tournament.js --in 2 --duration 20
 *
 *   # tournoi live immédiatement (test rapide de l'arène)
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 GOOGLE_CLOUD_PROJECT=kilimandjaro-dev \
 *     node functions/scripts/seed_test_tournament.js --start-now --duration 30
 *
 *   # prod (nécessite GOOGLE_APPLICATION_CREDENTIALS)
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
 *     node functions/scripts/seed_test_tournament.js --in 5 --duration 20
 */

"use strict";

function parseArgs(argv) {
  const args = {
    inMinutes: 2,
    durationMin: 20,
    startNow: false,
    name: "Tournoi de test",
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--in") args.inMinutes = Number(argv[++i]);
    else if (a === "--duration") args.durationMin = Number(argv[++i]);
    else if (a === "--start-now") args.startNow = true;
    else if (a === "--name") args.name = argv[++i];
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const admin = require("firebase-admin");
  admin.initializeApp({
    projectId:
      process.env.GOOGLE_CLOUD_PROJECT ||
      process.env.GCLOUD_PROJECT ||
      "kilimandjaro-dev",
  });
  const db = admin.firestore();
  const { Timestamp, FieldValue } = admin.firestore;

  if (process.env.FIRESTORE_EMULATOR_HOST) {
    console.log(`🔧 Émulateur : ${process.env.FIRESTORE_EMULATOR_HOST}`);
  }

  const now = Date.now();
  const startMs = args.startNow ? now : now + args.inMinutes * 60_000;
  const endMs = startMs + args.durationMin * 60_000;

  const doc = db.collection("tournaments").doc();
  await doc.set({
    name: args.name,
    status: args.startNow ? "live" : "scheduled",
    start_at: Timestamp.fromMillis(startMs),
    end_at: Timestamp.fromMillis(endMs),
    duration_min: args.durationMin,
    pack_id: null,
    participant_count: 0,
    points_win: 3,
    points_draw: 1,
    streak_min: 2,
    streak_mult: 2,
    min_participants: 2,
    max_participants: 200,
    rewards: [
      { rank_min: 1, rank_max: 1, cauris: 500, badge_id: "tournament_gold" },
      { rank_min: 2, rank_max: 3, cauris: 250, badge_id: "tournament_silver" },
      { rank_min: 4, rank_max: 10, cauris: 100, badge_id: null },
    ],
    finalized: false,
    created_by: "seed_script",
    created_at: FieldValue.serverTimestamp(),
  });

  console.log(`✅ Tournoi créé : ${doc.id}`);
  console.log(`   statut   : ${args.startNow ? "live" : "scheduled"}`);
  console.log(`   début    : ${new Date(startMs).toISOString()}`);
  console.log(`   fin      : ${new Date(endMs).toISOString()}`);
  process.exit(0);
}

main().catch((err) => {
  console.error("❌ Échec :", err);
  process.exit(1);
});
