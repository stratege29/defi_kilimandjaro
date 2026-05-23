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

initializeApp();

// --- Matchmaking ELO (Phase 6) ---
export { requestMatch } from "./matchmaking/requestMatch";
export { cancelMatch } from "./matchmaking/cancelMatch";
export { endMatch } from "./matchmaking/endMatch";
export { submitRoundWin } from "./matchmaking/submitRoundWin";
export { advanceRound } from "./matchmaking/advanceRound";
export { createLocalDuel } from "./matchmaking/createLocalDuel";

// --- Social & Viral (Phase 7) ---
export { sendChallengeNotif } from "./matchmaking/sendChallengeNotif";
export { requestRematch } from "./matchmaking/requestRematch";

// --- UGC (user-generated devinettes) ---
export { submitDevinette } from "./devinettes/submitDevinette";
export { reportDevinette } from "./devinettes/reportDevinette";

// --- Curation ---
export { rebuildCommunityPack } from "./curation/rebuildCommunityPack";
