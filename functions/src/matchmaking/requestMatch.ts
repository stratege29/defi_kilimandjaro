/**
 * requestMatch — Cloud Function callable (v2).
 *
 * Flux :
 * 1. Verifie l'auth.
 * 2. Rate-limit 1 appel / 3 s par UID.
 * 3. Lit (ou initialise a 1000) l'ELO du joueur dans Firestore.
 * 4. Cherche dans /lobby un adversaire dans la bande ELO +/-band_radius.
 * 4a. Si adversaire trouve :
 *     - Tire 3 devinettes (easy/medium/hard) depuis le cache Firestore.
 *     - Cree /matches/{matchId} avec les 3 rounds.
 *     - Supprime les 2 entrees lobby.
 *     - Retourne {status:"matched", matchId, matchData}.
 * 4b. Sinon : ecrit /lobby/{uid} et retourne {status:"waiting"}.
 *
 * Cache des devinettes : voir devinettesCache.ts (TTL 5 min, fallback samples).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import { ELO_INITIAL } from "./elo";
import { _loadDevinettesCache, _pickThreeRounds } from "./devinettesCache";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RequestMatchData {
  request_id: string;
  expansion_step?: number;
}

interface RequestMatchResult {
  status: "matched" | "waiting";
  matchId?: string;
  matchData?: Record<string, unknown>;
  lobbyEntry?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------

export const requestMatch = onCall<RequestMatchData, Promise<RequestMatchResult>>(
  { region: "europe-west1" },
  async (request) => {
    const uid = requireAuth(request.auth);
    const { request_id, expansion_step = 0 } = request.data;

    if (!request_id || typeof request_id !== "string") {
      throw new HttpsError("invalid-argument", "request_id requis.");
    }

    const db = getFirestore();
    const rtdb = getDatabase();
    const now = Date.now();

    // --- Rate limit : 1 appel / 3 s ---
    const lobbyRef = rtdb.ref(`lobby/${uid}`);
    const existingSnap = await lobbyRef.get();
    if (existingSnap.exists()) {
      const existing = existingSnap.val() as {
        ts: number;
        request_id: string;
        matched_to?: string;
      };
      const elapsedMs = now - (existing.ts ?? 0);
      // Meme request_id = expansion — pas de rate limit.
      if (existing.request_id !== request_id && elapsedMs < 3000) {
        throw new HttpsError(
          "resource-exhausted",
          "Trop de requetes. Attends 3 secondes entre chaque tentative."
        );
      }
      if (existing.matched_to) {
        return {
          status: "waiting",
          lobbyEntry: { matched_to: existing.matched_to },
        };
      }
    }

    // --- Lire ELO depuis Firestore ---
    const profileRef = db.collection("profiles").doc(uid);
    const profileSnap = await profileRef.get();
    let myElo: number;

    if (!profileSnap.exists) {
      myElo = ELO_INITIAL;
      await profileRef.set(
        {
          elo: ELO_INITIAL,
          peakElo: ELO_INITIAL,
          totalDuels: 0,
          wins: 0,
          losses: 0,
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      const data = profileSnap.data()!;
      myElo = (data["elo"] as number) ?? ELO_INITIAL;
    }

    // --- Bande ELO ---
    // expansion_step 0 → +-150, 1 → +-225, 2 → +-300, …
    const bandRadius = 150 + expansion_step * 75;
    const eloMin = myElo - bandRadius;
    const eloMax = myElo + bandRadius;

    // --- Scanner le lobby ---
    const lobbySnap = await rtdb.ref("lobby").get();
    let opponentUid: string | null = null;

    if (lobbySnap.exists()) {
      const lobbyData = lobbySnap.val() as Record<
        string,
        { mmr: number; ts: number; request_id: string; matched_to?: string }
      >;
      for (const [candidateUid, entry] of Object.entries(lobbyData)) {
        if (candidateUid === uid) continue;
        if (entry.matched_to) continue;
        if (entry.mmr < eloMin || entry.mmr > eloMax) continue;
        opponentUid = candidateUid;
        break;
      }
    }

    // --- Match trouve ---
    if (opponentUid) {
      const matchId = _generateMatchId();
      const cache = await _loadDevinettesCache();
      const rounds = _pickThreeRounds(cache);
      const now2 = Date.now();

      const matchData: Record<string, unknown> = {
        match_id: matchId,
        created_by: uid,
        created_at: now2,
        phase: "waiting",
        is_ranked: true,
        current_round: 0,
        total_rounds: 3,
        rounds: {
          0: rounds[0],
          1: rounds[1],
          2: rounds[2],
        },
        players: {
          [uid]: {
            progress: 0,
            found: false,
            rounds_won: 0,
            total_time_ms: 0,
            rounds: {},
          },
          [opponentUid]: {
            progress: 0,
            found: false,
            rounds_won: 0,
            total_time_ms: 0,
            rounds: {},
          },
        },
      };

      // Ecriture atomique dans Realtime DB.
      const updates: Record<string, unknown> = {
        [`matches/${matchId}`]: matchData,
        [`lobby/${uid}`]: null,
        [`lobby/${opponentUid}`]: null,
      };
      await rtdb.ref().update(updates);

      return { status: "matched", matchId, matchData };
    }

    // --- Pas d'adversaire : ecrire / mettre a jour le lobby ---
    await lobbyRef.set({ mmr: myElo, ts: now, request_id });

    return { status: "waiting", lobbyEntry: { mmr: myElo, ts: now } };
  }
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function _generateMatchId(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}
