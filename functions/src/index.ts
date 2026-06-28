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
  // Bucket de stockage explicite : `getStorage().bucket()` (sans nom)
  // requiert un storageBucket par defaut, sinon `publishPack` echoue avec
  // « Bucket name not specified or invalid » lors de l'upload de l'artefact.
  // Les projets recents utilisent le suffixe `.firebasestorage.app`.
  storageBucket: `${projectId}.firebasestorage.app`,
});

// --- Matchmaking ELO (Phase 6) ---
export { requestMatch } from "./matchmaking/requestMatch";
export { cancelMatch } from "./matchmaking/cancelMatch";
export { endMatch } from "./matchmaking/endMatch";
export { submitRoundWin } from "./matchmaking/submitRoundWin";
export { submitRoundTimeout } from "./matchmaking/submitRoundTimeout";
export { advancePhase } from "./matchmaking/advancePhase";
export { joinDuel } from "./matchmaking/joinDuel";
export { forfeitMatch } from "./matchmaking/forfeitMatch";
export { createLocalDuel } from "./matchmaking/createLocalDuel";
export { prunePresence } from "./matchmaking/prunePresence";
export { resolveStaleMatches } from "./matchmaking/resolveStaleMatches";
export { purgeMatches } from "./matchmaking/purgeMatches";

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
export { publishPack } from "./admin/publishPack";
export { rollbackPack } from "./admin/rollbackPack";
export { upsertDevinette } from "./admin/upsertDevinette";
export { deleteDevinette } from "./admin/deleteDevinette";
export { bulkImportDevinettes } from "./admin/bulkImportDevinettes";
export { upsertPackMeta } from "./admin/upsertPackMeta";
export { addTagsToWhitelist } from "./admin/tagsWhitelist";
export { moderateSubmission } from "./admin/moderateSubmission";
export {
  upsertDailyChallenge,
  deleteDailyChallenge,
} from "./admin/dailyChallenge";

// --- Wallet serveur (Phase 4) — cf docs/wallet_server_schema.md ---
export { bootstrapWallet } from "./wallet/bootstrapWallet";
export { unlockPack } from "./wallet/unlockPack";
export { creditCauris } from "./wallet/creditCauris";
export { syncWallet } from "./wallet/syncWallet";

// --- Compte joueur (RGPD / suppression) ---
export { deleteAccount } from "./account/deleteAccount";

// --- Autopilote Instagram (social) — cf docs/instagram_cloud_function.md ---
export {
  publishScheduledInstagramPost,
  igPublishDueNow,
  igPublishPost,
  igPublishMosaicRow,
  igSetAutopilot,
  igSetCampaign,
} from "./social/publishInstagram";
export { igInsights } from "./social/igInsights";
export { igGenerateImages } from "./social/genImages";
export { igRenderCard } from "./social/renderCard";
export { igPublishDueStories, igPublishStoryNow, igSetStoriesAuto } from "./social/stories";
export {
  adminFindPlayers,
  adminRecentPlayers,
  adminGetPlayer,
  adminAdjustCauris,
  adminSetBan,
  adminDeletePlayer,
} from "./admin/players";
export { mergeAccounts } from "./account/mergeAccounts";

// --- Pack Creator (pipeline contenu IA) — cf docs/pack_creator.md ---
export { createPackJob, cancelPackJob, retryPackJob } from "./admin/packJobs";
export { generateResearchPlan, approveResearchPlan } from "./admin/packPlan";
export {
  approveCandidate,
  rejectCandidate,
  updateCandidate,
  reassignCandidate,
  assignCandidateToDaily,
} from "./admin/packReview";
export { setPackTopup } from "./admin/packTopup";
export { drainPackJobs } from "./ai/drainPackJobs";
export { weeklyPackTopup } from "./ai/weeklyPackTopup";
