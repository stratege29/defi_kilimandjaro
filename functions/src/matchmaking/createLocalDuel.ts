/**
 * createLocalDuel — duel local (QR code / deep-link), non-ranked.
 *
 * Symetrique de requestMatch mais pour les duels entre amis (pas de
 * matchmaking ELO). Cree le match cote serveur avec les 3 rounds tires
 * du cache devinettes (anti-cheat : tirage serveur uniquement).
 *
 * Flow :
 *   1. Client appelle createLocalDuel() (callable)
 *   2. Serveur genere matchId + secret + 3 rounds (easy/medium/hard)
 *   3. Serveur ecrit /matches/{matchId} en RTDB avec phase=waiting
 *   4. Retourne { matchId, secret } au client
 *   5. Client genere le QR code pour partager
 *   6. Le 2e joueur scan le QR -> joinDuel() -> phase=countdown -> advanceRound
 */

import { HttpsError, onCall } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import {
  _loadDevinettesCache,
  _pickThreeRounds,
  answersFromRounds,
  toPublicRound,
} from "./devinettesCache";
import { buildAnswersNode, matchAnswersPath } from "./matchAnswers";
import { requireDuelProtocol } from "./protocol";

const REGION = "europe-west1";

function _generateMatchId(): string {
  // 6 caracteres alphanumeriques, lisibles (sans 0/O/1/I).
  // Garde la coherence avec l'UI client (DuelScanView accepte maxLength: 6).
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

function _generateSecret(): string {
  // 24 hex caracteres (12 bytes random). Coherent avec l'UI client
  // (DuelScanView accepte maxLength: 24 dans le champ Secret).
  const bytes: number[] = [];
  for (let i = 0; i < 12; i++) {
    bytes.push(Math.floor(Math.random() * 256));
  }
  return bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const createLocalDuel = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth requise");
    }
    requireDuelProtocol(request.data);

    const matchId = _generateMatchId();
    const secret = _generateSecret();
    const now = Date.now();

    const cache = await _loadDevinettesCache();
    const rounds = _pickThreeRounds(cache);

    const matchData: Record<string, unknown> = {
      match_id: matchId,
      secret,
      created_by: uid,
      created_at: now,
      phase: "waiting",
      is_ranked: false,
      current_round: 0,
      total_rounds: 3,
      // Anti-cheat (C3) : payload public sans `answer` (réponses serveur-only).
      rounds: {
        0: toPublicRound(rounds[0]),
        1: toPublicRound(rounds[1]),
        2: toPublicRound(rounds[2]),
      },
      players: {
        [uid]: {
          progress: 0,
          found: false,
          rounds_won: 0,
          total_time_ms: 0,
          rounds: {},
        },
      },
    };

    const rtdb = getDatabase();
    await rtdb.ref().update({
      [`matches/${matchId}`]: matchData,
      [matchAnswersPath(matchId)]: buildAnswersNode(answersFromRounds(rounds)),
    });

    return { matchId, secret };
  },
);
