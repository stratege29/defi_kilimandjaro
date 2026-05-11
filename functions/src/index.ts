/**
 * Cloud Functions entry point — Kilimandjaro.
 *
 * Toutes les fonctions exportées ici sont déployables via `firebase deploy
 * --only functions`. Les triggers sont organisés par domaine sous `src/`.
 *
 * Domaines :
 * - matchmaking/  : requestMatch, cancelMatch, endMatch (Phase 6)
 * - matchmaking/  : sendChallengeNotif, requestRematch (Phase 7 — social)
 */
import { initializeApp } from "firebase-admin/app";

initializeApp();

// --- Matchmaking ELO (Phase 6) ---
export { requestMatch } from "./matchmaking/requestMatch";
export { cancelMatch } from "./matchmaking/cancelMatch";
export { endMatch } from "./matchmaking/endMatch";

// --- Social & Viral (Phase 7) ---
export { sendChallengeNotif } from "./matchmaking/sendChallengeNotif";
export { requestRematch } from "./matchmaking/requestRematch";
