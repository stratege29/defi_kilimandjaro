/**
 * submitRoundWin — Cloud Function callable (v2).
 *
 * Appele par le client quand un joueur valide le mot du round courant.
 * Responsabilites :
 *   1. Validation auth + integrite des donnees (anti-cheat).
 *   2. Mise a jour des compteurs du joueur gagnant (rounds_won, total_time_ms).
 *   3. Si dernier round : calcule le vainqueur final et bascule en "finished".
 *   4. Si round intermediaire : bascule en "roundEnd", puis schedules la
 *      transition vers le round suivant via un RTDB trigger (cf. advanceRound.ts).
 *
 * Idempotence : si appele 2x avec les memes inputs (retry reseau), le second
 * appel est un no-op silencieux grace a la verification "found deja true".
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";

interface SubmitRoundWinData {
  match_id: string;
  round: number;
  winner_uid: string;
}

interface SubmitRoundWinResult {
  ok: true;
  next_phase: "countdown" | "finished";
  current_round: number;
}

interface PlayerState {
  rounds_won: number;
  total_time_ms: number;
  progress: number;
  found: boolean;
  finished_at?: number;
  rounds?: Record<
    string,
    { progress: number; found: boolean; finished_at?: number; time_taken_ms?: number }
  >;
}

interface MatchState {
  phase: string;
  current_round: number;
  total_rounds: number;
  created_at: number;
  phase_started_at?: number;
  players: Record<string, PlayerState>;
  winner?: string;
}

export const submitRoundWin = onCall<SubmitRoundWinData, Promise<SubmitRoundWinResult>>(
  { region: "europe-west1" },
  async (request) => {
    const callerUid = requireAuth(request.auth);
    const { match_id, round, winner_uid } = request.data;

    // --- Validation des inputs ---
    if (!match_id || typeof match_id !== "string") {
      throw new HttpsError("invalid-argument", "match_id requis.");
    }
    if (typeof round !== "number" || round < 0 || round > 2) {
      throw new HttpsError("invalid-argument", "round doit etre 0, 1 ou 2.");
    }
    if (!winner_uid || typeof winner_uid !== "string") {
      throw new HttpsError("invalid-argument", "winner_uid requis.");
    }
    if (callerUid !== winner_uid) {
      // Le client ne peut declarer que sa propre victoire.
      throw new HttpsError(
        "permission-denied",
        "Tu ne peux declarer la victoire que pour toi-meme."
      );
    }

    const rtdb = getDatabase();
    const matchRef = rtdb.ref(`matches/${match_id}`);
    const matchSnap = await matchRef.get();

    if (!matchSnap.exists()) {
      throw new HttpsError("not-found", `Match ${match_id} introuvable.`);
    }

    const matchData = matchSnap.val() as MatchState;

    // --- Verifier que le match est dans le bon etat ---
    if (matchData.phase !== "active") {
      throw new HttpsError(
        "failed-precondition",
        `Phase invalide: ${matchData.phase}. Attendu: active.`
      );
    }
    if (matchData.current_round !== round) {
      throw new HttpsError(
        "failed-precondition",
        `Round invalide: recu ${round}, courant ${matchData.current_round}.`
      );
    }

    const players = matchData.players ?? {};
    const playerUids = Object.keys(players);

    if (!playerUids.includes(winner_uid)) {
      throw new HttpsError(
        "permission-denied",
        "winner_uid n'est pas participant de ce match."
      );
    }
    if (playerUids.length < 2) {
      throw new HttpsError(
        "failed-precondition",
        "Le match necessite 2 joueurs."
      );
    }

    // --- Idempotence : si le joueur a deja gagne ce round, no-op ---
    const winnerRounds = players[winner_uid]?.rounds ?? {};
    const existingRoundResult = winnerRounds[String(round)];
    if (existingRoundResult?.found === true) {
      // Deja enregistre : retourner le resultat courant sans modifier.
      const isLastRound = round >= (matchData.total_rounds ?? 3) - 1;
      return {
        ok: true,
        next_phase: isLastRound ? "finished" : "countdown",
        current_round: matchData.current_round,
      };
    }

    const now = Date.now();
    const phaseStartedAt = matchData.phase_started_at ?? matchData.created_at;
    const timeTakenMs = now - phaseStartedAt;

    const totalRounds = matchData.total_rounds ?? 3;
    const isLastRound = round >= totalRounds - 1;

    // --- Lire les rounds_won actuels pour recalcul ---
    const winnerCurrentRoundsWon = players[winner_uid]?.rounds_won ?? 0;
    const newRoundsWon = winnerCurrentRoundsWon + 1;

    const winnerCurrentTotalTime = players[winner_uid]?.total_time_ms ?? 0;
    const newTotalTime = winnerCurrentTotalTime + timeTakenMs;

    if (!isLastRound) {
      // --- Round intermediaire : roundEnd, le trigger advanceRound prendra le relai ---
      await matchRef.update({
        phase: "roundEnd",
        phase_started_at: now,
        [`players/${winner_uid}/rounds_won`]: newRoundsWon,
        [`players/${winner_uid}/total_time_ms`]: newTotalTime,
        [`players/${winner_uid}/found`]: true,
        [`players/${winner_uid}/finished_at`]: now,
        [`players/${winner_uid}/rounds/${round}`]: {
          progress: 1.0,
          found: true,
          finished_at: now,
          time_taken_ms: timeTakenMs,
        },
      });

      return { ok: true, next_phase: "countdown", current_round: round + 1 };
    }

    // --- Dernier round : calcul du vainqueur final ---
    const loserUid = playerUids.find((p) => p !== winner_uid)!;

    // Compter les rounds_won de chaque joueur apres ce round.
    const winnerFinalRoundsWon = newRoundsWon;
    const loserFinalRoundsWon = players[loserUid]?.rounds_won ?? 0;

    let finalWinner: string;
    if (winnerFinalRoundsWon > loserFinalRoundsWon) {
      finalWinner = winner_uid;
    } else if (loserFinalRoundsWon > winnerFinalRoundsWon) {
      finalWinner = loserUid;
    } else {
      // Egalite parfaite en rounds : tiebreaker = temps cumule le plus court.
      const winnerTime = newTotalTime;
      const loserTime = players[loserUid]?.total_time_ms ?? 0;
      finalWinner = winnerTime <= loserTime ? winner_uid : loserUid;
    }

    await matchRef.update({
      phase: "finished",
      phase_started_at: now,
      winner: finalWinner,
      [`players/${winner_uid}/rounds_won`]: newRoundsWon,
      [`players/${winner_uid}/total_time_ms`]: newTotalTime,
      [`players/${winner_uid}/found`]: true,
      [`players/${winner_uid}/finished_at`]: now,
      [`players/${winner_uid}/rounds/${round}`]: {
        progress: 1.0,
        found: true,
        finished_at: now,
        time_taken_ms: timeTakenMs,
      },
    });

    return { ok: true, next_phase: "finished", current_round: round };
  }
);
