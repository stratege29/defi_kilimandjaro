/**
 * requestArenaMatch — matchmaking « arène » scopé à un tournoi (callable v2).
 *
 * Cœur de la boucle d'enchaînement : appelé par le client dès qu'il entre dans
 * l'arène, puis re-appelé après chaque match tant que la fenêtre est ouverte.
 * Calqué sur `requestMatch.ts` (scan d'un pool + filtre présence + écriture
 * atomique), mais :
 *   - apparie par PROXIMITÉ DE POINTS d'arène (pas l'ELO global),
 *   - crée des matchs marqués `tournament_id` + `is_ranked:false` (pas d'ELO),
 *   - utilise le pool RTDB `arena/{tid}/pool` et le pointeur `arena/{tid}/active`.
 *
 * Anti double-match : `arena/{tid}/active/{uid}` pointe vers le match en cours.
 * Si présent et non terminé, on renvoie ce match (rejoin idempotent) plutôt que
 * d'en créer un second.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { getDatabase, ServerValue } from "firebase-admin/database";

import { requireAuth } from "../utils/auth";
import { requireDuelProtocol } from "../matchmaking/protocol";
import {
  _loadDevinettesCache,
  _pickThreeRounds,
  answersFromRounds,
  toPublicRound,
} from "../matchmaking/devinettesCache";
import {
  buildAnswersNode,
  matchAnswersPath,
} from "../matchmaking/matchAnswers";
import {
  tournamentRef,
  participantRef,
  arenaPoolPath,
  arenaActivePath,
  toMillis,
} from "./helpers";

interface RequestArenaMatchData {
  tournament_id: string;
  request_id: string;
  expansion_step?: number;
}

interface RequestArenaMatchResult {
  status: "matched" | "waiting";
  matchId?: string;
  matchData?: Record<string, unknown>;
}

const PRESENCE_FRESH_MS = 90_000;

export const requestArenaMatch = onCall<
  RequestArenaMatchData,
  Promise<RequestArenaMatchResult>
>(
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request.auth);
    requireDuelProtocol(request.data);
    const { tournament_id: tid, request_id, expansion_step = 0 } =
      request.data;

    if (!tid || typeof tid !== "string") {
      throw new HttpsError("invalid-argument", "tournament_id requis.");
    }
    if (!request_id || typeof request_id !== "string") {
      throw new HttpsError("invalid-argument", "request_id requis.");
    }

    const db = getFirestore();
    const rtdb = getDatabase();
    const now = Date.now();

    // --- Tournoi : doit être live et dans la fenêtre ---
    const tSnap = await tournamentRef(tid).get();
    if (!tSnap.exists) {
      throw new HttpsError("not-found", "Tournoi introuvable.");
    }
    const t = tSnap.data()!;
    if (t["status"] !== "live") {
      throw new HttpsError(
        "failed-precondition",
        "Le tournoi n'est pas en cours."
      );
    }
    const startMs = toMillis(t["start_at"]);
    const endMs = toMillis(t["end_at"]);
    if (now < startMs || now >= endMs) {
      throw new HttpsError(
        "failed-precondition",
        "Hors de la fenêtre du tournoi."
      );
    }

    // --- Participant inscrit + ses points (proximité d'appariement) ---
    const pSnap = await participantRef(tid, uid).get();
    if (!pSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Rejoins le tournoi avant de jouer."
      );
    }
    const myPoints = (pSnap.data()?.["points"] as number) ?? 0;

    // --- Anti double-match : match actif déjà en cours ? ---
    const activeRef = rtdb.ref(arenaActivePath(tid, uid));
    const activeSnap = await activeRef.get();
    if (activeSnap.exists()) {
      const activeMatchId = activeSnap.val() as string;
      const mSnap = await rtdb.ref(`matches/${activeMatchId}`).get();
      if (mSnap.exists()) {
        const m = mSnap.val() as { phase?: string };
        if (m.phase !== "finished") {
          // Match toujours en cours → rejoin idempotent. On purge au passage
          // toute entrée pool résiduelle de ce joueur : sans ça, un 3e joueur
          // pourrait la réclamer alors qu'on est déjà dans un match (fantôme).
          await rtdb.ref(arenaPoolPath(tid, uid)).remove();
          return {
            status: "matched",
            matchId: activeMatchId,
            matchData: mSnap.val() as Record<string, unknown>,
          };
        }
      }
      // Match terminé ou disparu : on nettoie le pointeur et on continue.
      await activeRef.remove();
    }

    // --- Pool : entrée existante (rate-limit + détection appariement passif) ---
    const poolRef = rtdb.ref(arenaPoolPath(tid, uid));
    const existingSnap = await poolRef.get();
    if (existingSnap.exists()) {
      const existing = existingSnap.val() as {
        ts?: number;
        request_id?: string;
        matched_to?: string;
      };
      if (existing.matched_to) {
        const matchedTo = existing.matched_to;
        const matchSnap = await rtdb.ref(`matches/${matchedTo}`).get();
        if (matchSnap.exists()) {
          await poolRef.remove();
          return {
            status: "matched",
            matchId: matchedTo,
            matchData: matchSnap.val() as Record<string, unknown>,
          };
        }
        await poolRef.remove();
      } else {
        const elapsedMs = now - (existing.ts ?? 0);
        if (existing.request_id !== request_id && elapsedMs < 3000) {
          throw new HttpsError(
            "resource-exhausted",
            "Trop de requêtes. Attends quelques secondes."
          );
        }
      }
    }

    // --- Présence fraîche (filtre les fantômes, cf requestMatch) ---
    const presenceSnap = await rtdb.ref("presence").get();
    const presenceData = (presenceSnap.val() ?? {}) as Record<string, unknown>;
    const isFresh = (candidateUid: string): boolean => {
      const entry = presenceData[candidateUid];
      const ts =
        typeof entry === "object" && entry !== null && "ts" in entry
          ? (entry as { ts?: number }).ts
          : undefined;
      return typeof ts === "number" && now - ts < PRESENCE_FRESH_MS;
    };

    // --- Scan du pool du tournoi ---
    // Bande de points : 4 + step*4 (élargie au re-queue pour ne pas bloquer).
    const band = 4 + expansion_step * 4;
    const poolSnap = await rtdb.ref(`arena/${tid}/pool`).get();
    let opponentUid: string | null = null;
    const staleEntries: string[] = [];

    if (poolSnap.exists()) {
      const poolData = poolSnap.val() as Record<
        string,
        { points?: number; ts?: number; matched_to?: string }
      >;
      let bestDiff = Number.POSITIVE_INFINITY;
      for (const [candidateUid, entry] of Object.entries(poolData)) {
        if (candidateUid === uid) continue;
        if (entry.matched_to) continue;
        const candPoints = entry.points ?? 0;
        const diff = Math.abs(candPoints - myPoints);
        if (diff > band) continue;
        if (!isFresh(candidateUid)) {
          staleEntries.push(candidateUid);
          continue;
        }
        // Meilleur appariement = plus proche en points.
        if (diff < bestDiff) {
          bestDiff = diff;
          opponentUid = candidateUid;
        }
      }
    }

    // Nettoyage best-effort des entrées fantômes.
    if (staleEntries.length > 0) {
      const cleanup: Record<string, unknown> = {};
      for (const ghost of staleEntries) {
        cleanup[arenaPoolPath(tid, ghost)] = null;
      }
      await rtdb.ref().update(cleanup);
    }

    // --- Adversaire trouvé : appariement anti-course ---
    // Deux protections combinées contre les "duels fantômes" (deux joueurs
    // créant chacun un match avec le même adversaire quand ils re-quêtent
    // simultanément — fréquent en 1v1 après chaque match) :
    //   1. Symétrie : seul le plus PETIT uid de la paire crée ; l'autre attend
    //      le pointeur actif. Casse le cas où A et B se choisissent mutuellement.
    //   2. Réclamation atomique : transaction sur `pool/{adversaire}/matched_to`.
    //      Empêche deux créateurs distincts (C<B et A<B) de réclamer le même B.
    if (opponentUid && uid > opponentUid) {
      // L'adversaire (uid plus petit) est responsable de créer. On (re)attend ;
      // notre prochain poll récupèrera le match via `arena/{tid}/active/{uid}`.
      await rtdb.ref().update({
        [arenaPoolPath(tid, uid)]: { points: myPoints, ts: now, request_id },
        [`presence/${uid}`]: { ts: ServerValue.TIMESTAMP },
      });
      return { status: "waiting" };
    }

    if (opponentUid) {
      // uid < opponentUid : on réclame l'adversaire atomiquement avant de créer.
      const claimRef = rtdb.ref(
        `${arenaPoolPath(tid, opponentUid)}/matched_to`
      );
      const claim = await claimRef.transaction((cur) =>
        cur ? undefined : uid
      );
      if (!claim.committed || claim.snapshot.val() !== uid) {
        // Adversaire déjà réclamé/parti → on retente au prochain poll.
        await rtdb.ref().update({
          [arenaPoolPath(tid, uid)]: { points: myPoints, ts: now, request_id },
          [`presence/${uid}`]: { ts: ServerValue.TIMESTAMP },
        });
        return { status: "waiting" };
      }

      // Garde anti-fantôme finale : l'adversaire réclamé est-il déjà dans un
      // match actif (entrée pool périmée non nettoyée) ? Si oui, on NE crée pas
      // un 2e match avec lui : on purge son entrée périmée et on réattend.
      const oppActiveSnap = await rtdb
        .ref(arenaActivePath(tid, opponentUid))
        .get();
      if (oppActiveSnap.exists()) {
        const oppMatchSnap = await rtdb
          .ref(`matches/${oppActiveSnap.val() as string}`)
          .get();
        const oppPhase = oppMatchSnap.exists()
          ? (oppMatchSnap.val() as { phase?: string }).phase
          : undefined;
        if (oppMatchSnap.exists() && oppPhase !== "finished") {
          await rtdb.ref().update({
            [arenaPoolPath(tid, opponentUid)]: null,
            [arenaPoolPath(tid, uid)]: {
              points: myPoints,
              ts: now,
              request_id,
            },
            [`presence/${uid}`]: { ts: ServerValue.TIMESTAMP },
          });
          return { status: "waiting" };
        }
      }

      const matchId = _generateMatchId();
      const cache = await _loadDevinettesCache();
      // Scope par packs sélectionnés (config tournoi). Rétro-compat : ancien
      // champ `pack_id` (singulier) → tableau ; vide ⇒ pool global.
      const rawPackIds = t["pack_ids"];
      const packIds = Array.isArray(rawPackIds)
        ? (rawPackIds as unknown[]).filter(
            (p): p is string => typeof p === "string"
          )
        : typeof t["pack_id"] === "string" && t["pack_id"]
          ? [t["pack_id"] as string]
          : [];
      const rounds = _pickThreeRounds(cache, packIds);
      const now2 = Date.now();

      const matchData: Record<string, unknown> = {
        match_id: matchId,
        created_by: uid,
        created_at: now2,
        phase: "countdown",
        phase_started_at: now2,
        is_ranked: false,
        tournament_id: tid,
        current_round: 0,
        total_rounds: 3,
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

      const updates: Record<string, unknown> = {
        [`matches/${matchId}`]: matchData,
        [matchAnswersPath(matchId)]: buildAnswersNode(
          answersFromRounds(rounds)
        ),
        // Retire les 2 du pool, pointe leur match actif.
        [arenaPoolPath(tid, uid)]: null,
        [arenaPoolPath(tid, opponentUid)]: null,
        [arenaActivePath(tid, uid)]: matchId,
        [arenaActivePath(tid, opponentUid)]: matchId,
        // Notifie le joueur passif (fallback à son listener/poll RTDB).
      };
      await rtdb.ref().update(updates);

      return { status: "matched", matchId, matchData };
    }

    // --- Pas d'adversaire : (re)mise en file + heartbeat présence ---
    await rtdb.ref().update({
      [arenaPoolPath(tid, uid)]: { points: myPoints, ts: now, request_id },
      [`presence/${uid}`]: { ts: ServerValue.TIMESTAMP },
    });

    return { status: "waiting" };
  }
);

function _generateMatchId(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}
