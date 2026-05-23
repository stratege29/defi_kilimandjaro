/**
 * requestRematch — Cloud Function callable (v2).
 *
 * Flux :
 * 1. Verifie l'auth.
 * 2. Lit /matches/{previousMatchId}/players pour confirmer que le caller
 *    etait bien participant du match precedent (anti-abus).
 * 3. Rate-limit 1 rematch / 10 s par paire (uid, opponentUid) via RTDB.
 * 4. Tire 3 devinettes (easy/medium/hard) depuis le cache partage.
 * 5. Cree /matches/{newMatchId} avec target_uid=opponentUid (declenche
 *    sendChallengeNotif → notif FCM a l'adversaire).
 * 6. Retourne {matchId, secret} au caller.
 *
 * Le caller observe /matches/{newMatchId} (stream RTDB).
 * L'adversaire recoit la notif → tape → deep link → joinDuel → match demarre.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { getFirestore } from "firebase-admin/firestore";
import { requireAuth } from "../utils/auth";
import { ELO_INITIAL } from "./elo";
import * as logger from "firebase-functions/logger";
import { _loadDevinettesCache, _pickThreeRounds } from "./devinettesCache";

interface RequestRematchData {
  previousMatchId: string;
  opponentUid: string;
}

interface RequestRematchResult {
  matchId: string;
  secret: string;
}

/** Genere un matchId lisible (6 caracteres, sans ambigus). */
function _generateMatchId(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

/** Genere un secret hexadecimal 24 caracteres. */
function _generateSecret(): string {
  const bytes: number[] = [];
  for (let i = 0; i < 12; i++) {
    bytes.push(Math.floor(Math.random() * 256));
  }
  return bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Cle de rate-limit RTDB pour une paire de joueurs (canonique). */
function _rateLimitKey(uid1: string, uid2: string): string {
  const [a, b] = [uid1, uid2].sort();
  return `rematch_rate_limit/${a}_${b}`;
}

export const requestRematch = onCall<
  RequestRematchData,
  Promise<RequestRematchResult>
>(
  { region: "europe-west1" },
  async (request) => {
    const callerUid = requireAuth(request.auth);
    const { previousMatchId, opponentUid } = request.data;

    if (!previousMatchId || typeof previousMatchId !== "string") {
      throw new HttpsError("invalid-argument", "previousMatchId requis.");
    }
    if (!opponentUid || typeof opponentUid !== "string") {
      throw new HttpsError("invalid-argument", "opponentUid requis.");
    }
    if (opponentUid === callerUid) {
      throw new HttpsError(
        "invalid-argument",
        "Tu ne peux pas te defier toi-meme."
      );
    }

    const rtdb = getDatabase();
    const db = getFirestore();
    const now = Date.now();

    // --- Verifier que le caller etait dans le match precedent ---
    const prevSnap = await rtdb
      .ref(`matches/${previousMatchId}/players`)
      .get();
    if (!prevSnap.exists()) {
      throw new HttpsError(
        "not-found",
        `Match precedent ${previousMatchId} introuvable.`
      );
    }
    const prevPlayers = prevSnap.val() as Record<string, unknown>;
    if (!prevPlayers[callerUid]) {
      throw new HttpsError(
        "permission-denied",
        "Tu n'etais pas participant du match precedent."
      );
    }
    if (!prevPlayers[opponentUid]) {
      throw new HttpsError(
        "permission-denied",
        "L'adversaire n'etait pas dans le match precedent."
      );
    }

    // --- Rate-limit : 1 rematch / 10 s par paire ---
    const rateLimitKey = _rateLimitKey(callerUid, opponentUid);
    const rateLimitSnap = await rtdb.ref(rateLimitKey).get();
    if (rateLimitSnap.exists()) {
      const lastTs = rateLimitSnap.val() as number;
      if (now - lastTs < 10_000) {
        throw new HttpsError(
          "resource-exhausted",
          "Attends 10 secondes avant de renvoyer un defi."
        );
      }
    }
    await rtdb.ref(rateLimitKey).set(now);

    // --- Tirer 3 devinettes depuis le cache partage ---
    const cache = await _loadDevinettesCache();
    const rounds = _pickThreeRounds(cache);

    // --- Lire l'ELO du caller ---
    const profileSnap = await db.collection("profiles").doc(callerUid).get();
    const callerElo: number =
      (profileSnap.data()?.["elo"] as number | undefined) ?? ELO_INITIAL;

    // --- Creer le nouveau match ---
    const newMatchId = _generateMatchId();
    const secret = _generateSecret();

    const matchData: Record<string, unknown> = {
      match_id: newMatchId,
      secret,
      created_by: callerUid,
      created_at: now,
      phase: "waiting",
      is_ranked: true,
      current_round: 0,
      total_rounds: 3,
      rounds: {
        0: rounds[0],
        1: rounds[1],
        2: rounds[2],
      },
      // target_uid declenche sendChallengeNotif → notif FCM a l'adversaire.
      target_uid: opponentUid,
      previous_match_id: previousMatchId,
      caller_elo: callerElo,
      players: {
        [callerUid]: {
          progress: 0,
          found: false,
          rounds_won: 0,
          total_time_ms: 0,
          rounds: {},
        },
      },
    };

    await rtdb.ref(`matches/${newMatchId}`).set(matchData);

    logger.info(
      `[requestRematch] caller=${callerUid} vs opponent=${opponentUid} ` +
        `newMatchId=${newMatchId} previousMatchId=${previousMatchId}`
    );

    return { matchId: newMatchId, secret };
  }
);
