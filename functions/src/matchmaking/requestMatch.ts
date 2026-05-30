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
import { getDatabase, ServerValue } from "firebase-admin/database";
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

    // --- Check match deja appaire (joueur passif notifie via lobby) ---
    // Pattern Lichess/Firebase : quand un poll trouve `matched_to`, on lit
    // le match et on retourne `matched` au client. Le listener RTDB cote
    // client devrait avoir push avant, mais ce polling est un fallback fiable.
    const lobbyRef = rtdb.ref(`lobby/${uid}`);
    const existingSnap = await lobbyRef.get();
    if (existingSnap.exists()) {
      const existing = existingSnap.val() as {
        ts: number;
        request_id: string;
        matched_to?: string;
      };

      // Match deja cree pour ce joueur passif → retourner matched.
      if (existing.matched_to) {
        const matchedTo = existing.matched_to;
        const matchSnap = await rtdb.ref(`matches/${matchedTo}`).get();
        if (matchSnap.exists()) {
          await lobbyRef.remove();
          return {
            status: "matched",
            matchId: matchedTo,
            matchData: matchSnap.val() as Record<string, unknown>,
          };
        }
        // Match supprime (rare : adversaire forfait apres creation) :
        // on nettoie et on continue a chercher normalement.
        await lobbyRef.remove();
      } else {
        // Rate limit : 1 appel / 3 s sauf meme request_id (expansion).
        const elapsedMs = now - (existing.ts ?? 0);
        if (existing.request_id !== request_id && elapsedMs < 3000) {
          throw new HttpsError(
            "resource-exhausted",
            "Trop de requetes. Attends 3 secondes entre chaque tentative."
          );
        }
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

      // Phase = countdown direct (pas waiting) pour declencher l'overlay
      // 3,2,1 du DuelPlayView des reception cote client. La duree de
      // l'animation (3s) est calculee via phase_started_at, donc les 2
      // clients restent synchronises meme si B arrive avec ~500ms de retard.
      const matchData: Record<string, unknown> = {
        match_id: matchId,
        created_by: uid,
        created_at: now2,
        phase: "countdown",
        phase_started_at: now2,
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

      // Ecriture atomique : creation du match + notification du joueur passif
      // via `matched_to` sur son entree lobby (sera detecte par son listener
      // RTDB ou par son prochain poll). L'appelant `uid` est notifie via la
      // valeur de retour, donc son entree lobby peut etre supprimee.
      const updates: Record<string, unknown> = {
        [`matches/${matchId}`]: matchData,
        [`lobby/${uid}`]: null,
        [`lobby/${opponentUid}/matched_to`]: matchId,
      };
      await rtdb.ref().update(updates);

      return { status: "matched", matchId, matchData };
    }

    // --- Pas d'adversaire : ecrire / mettre a jour le lobby ---
    await lobbyRef.set({ mmr: myElo, ts: now, request_id });

    // Increment online counter and setup onDisconnect hook to decrement.
    // This is done here so the counter reflects active matchmaking players.
    const onlineRef = rtdb.ref("lobby/stats/online");
    const updateOnline: Record<string, unknown> = {
      [`presence/${uid}`]: { ts: ServerValue.TIMESTAMP },
    };
    await rtdb.ref().update(updateOnline);

    // Read current value and increment atomically
    const currentSnap = await onlineRef.get();
    const current = (currentSnap.val() as number) || 0;
    await onlineRef.set(current + 1);

    // Configure disconnect hook to decrement counter (will trigger when
    // connection drops or lobby entry is removed).
    await onlineRef.onDisconnect().set(Math.max(0, current));

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
