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

// databaseURL explicite : la RTDB du projet est en us-central1 (URL historique
// firebaseio.com). Sans cette config, les CF en europe-west1 ne resolvent pas
// correctement l'URL via auto-discovery, et les writes RTDB partent "dans le
// vide" silencieusement (CF return OK mais rien n'est ecrit). Cf. debug
// duel 3-manches : submitRoundWin retournait next_phase=countdown mais
// l'update phase=roundEnd n'arrivait jamais aux clients.
initializeApp({
  databaseURL: "https://kilimandjaro-dev-default-rtdb.firebaseio.com",
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
