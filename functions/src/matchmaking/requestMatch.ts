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
import {
  _loadDevinettesCache,
  _pickThreeRounds,
  answersFromRounds,
  toPublicRound,
} from "./devinettesCache";
import { buildAnswersNode, matchAnswersPath } from "./matchAnswers";
import { requireDuelProtocol } from "./protocol";

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
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request.auth);
    // Gate version : refuse les clients antérieurs au contrat C2/C3 (sinon duel
    // injouable). Cf. protocol.ts.
    requireDuelProtocol(request.data);
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

    // --- Présence (M3) : filtrer les adversaires fantômes ---
    // Un joueur peut rester dans /lobby alors qu'il est déconnecté (app tuée,
    // réseau coupé). L'apparier crée un duel mort jusqu'au filet
    // resolveStaleMatches. On exige donc une présence FRAÎCHE (heartbeat client
    // ~45s). Fenêtre 90s < TTL prune (120s) pour ne pas matcher un ghost en
    // sursis. On nettoie au passage les entrées lobby périmées rencontrées.
    const PRESENCE_FRESH_MS = 90000;
    const presenceSnap = await rtdb.ref("presence").get();
    const presenceData = (presenceSnap.val() ?? {}) as Record<
      string,
      { ts?: number } | unknown
    >;
    const isFresh = (candidateUid: string): boolean => {
      const entry = presenceData[candidateUid];
      const ts =
        typeof entry === "object" && entry !== null && "ts" in entry
          ? (entry as { ts?: number }).ts
          : undefined;
      return typeof ts === "number" && now - ts < PRESENCE_FRESH_MS;
    };

    // --- Scanner le lobby ---
    const lobbySnap = await rtdb.ref("lobby").get();
    let opponentUid: string | null = null;
    const staleLobby: string[] = [];

    if (lobbySnap.exists()) {
      const lobbyData = lobbySnap.val() as Record<
        string,
        { mmr: number; ts: number; request_id: string; matched_to?: string }
      >;
      for (const [candidateUid, entry] of Object.entries(lobbyData)) {
        if (candidateUid === "stats") continue; // /lobby/stats n'est pas un joueur
        if (candidateUid === uid) continue;
        if (entry.matched_to) continue;
        if (entry.mmr < eloMin || entry.mmr > eloMax) continue;
        if (!isFresh(candidateUid)) {
          staleLobby.push(candidateUid);
          continue;
        }
        opponentUid = candidateUid;
        break;
      }
    }

    // Nettoyage best-effort des entrées lobby fantômes (rien d'autre ne purge
    // /lobby — prunePresence ne touche que /presence).
    if (staleLobby.length > 0) {
      const cleanup: Record<string, unknown> = {};
      for (const ghost of staleLobby) cleanup[`lobby/${ghost}`] = null;
      await rtdb.ref().update(cleanup);
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
        // Anti-cheat (C3) : payload public sans `answer`. Les réponses vont
        // dans le nœud serveur-only /match_answers, révélées en fin de manche.
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
        [matchAnswersPath(matchId)]: buildAnswersNode(
          answersFromRounds(rounds)
        ),
        [`lobby/${uid}`]: null,
        [`lobby/${opponentUid}/matched_to`]: matchId,
      };
      await rtdb.ref().update(updates);

      return { status: "matched", matchId, matchData };
    }

    // --- Pas d'adversaire : ecrire / mettre a jour le lobby ---
    await lobbyRef.set({ mmr: myElo, ts: now, request_id });

    // Écriture de la présence : le client maintient cela via heartbeat,
    // mais la CF peut aussi l'écrire pour garantir un timestamp frais.
    // La prunePresence CF recalculera le compteur /lobby/stats/online
    // automatiquement toutes les 1 minute.
    const updatePresence: Record<string, unknown> = {
      [`presence/${uid}`]: { ts: ServerValue.TIMESTAMP },
    };
    await rtdb.ref().update(updatePresence);

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
