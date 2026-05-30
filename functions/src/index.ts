/**
 * Cloud Functions entry point — Kilimandjaro.
 *
 * Toutes les fonctions exportées ici sont déployables via `firebase deploy
 * --only functions`. Les triggers sont organisés par domaine sous `src/`.
 *
 * Domaines :
 * - matchmaking/  : requestMatch, cancelMatch, endMatch (Phase 6)
 * - matchmaking/  : sendChallengeNotif, requestRematch (Phase 7 — social)
 * - devinettes/   : submitDevinette, reportDevinette (UGC)
 * - curation/     : rebuildCommunityPack (UGC pack rebuild)
 */
import { initializeApp } from "firebase-admin/app";

// databaseURL explicite (auto-discovery non fiable depuis europe-west1 vers
// une RTDB us-central1). Construction dynamique depuis le projet actif :
//   dev  → https://kilimandjaro-dev-default-rtdb.firebaseio.com
//   prod → https://kilimandjaro-prod-default-rtdb.firebaseio.com
//
// Hypothese : RTDB en us-central1 (URL historique firebaseio.com) avec
// instance par defaut `{projectId}-default-rtdb`. Si la RTDB prod est
// creee dans une autre region, ajuster ici (ex: .europe-west1.firebase
// database.app). Cf. debug duel 3-manches : sans cette config explicite,
// les writes RTDB partent dans le vide silencieusement.
const projectId =
  process.env["GCLOUD_PROJECT"] ?? "kilimandjaro-dev";
initializeApp({
  databaseURL: `https://${projectId}-default-rtdb.firebaseio.com`,
});

// --- Matchmaking ELO (Phase 6) ---
export { requestMatch } from "./matchmaking/requestMatch";
export { cancelMatch } from "./matchmaking/cancelMatch";
export { endMatch } from "./matchmaking/endMatch";
export { submitRoundWin } from "./matchmaking/submitRoundWin";
export { submitRoundTimeout } from "./matchmaking/submitRoundTimeout";
export { advancePhase } from "./matchmaking/advancePhase";
export { createLocalDuel } from "./matchmaking/createLocalDuel";

// --- Social & Viral (Phase 7) ---
export { sendChallengeNotif } from "./matchmaking/sendChallengeNotif";
export { requestRematch } from "./matchmaking/requestRematch";
export { respondToChallenge } from "./matchmaking/respondToChallenge";

// --- UGC (user-generated devinettes) ---
export { submitDevinette } from "./devinettes/submitDevinette";
export { reportDevinette } from "./devinettes/reportDevinette";

// --- Curation ---
export { rebuildCommunityPack } from "./curation/rebuildCommunityPack";

// --- IAP server validation (Phase 4) ---
export { validateIapReceipt } from "./iap/validateIapReceipt";

// --- Backoffice admin (Phase 1) — cf docs/backoffice_schema.md ---
export { validatePackDraft } from "./admin/validatePackDraft";
