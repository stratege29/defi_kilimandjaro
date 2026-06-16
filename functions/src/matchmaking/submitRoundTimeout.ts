/**
 * submitRoundTimeout — Cloud Function callable (v2).
 *
 * Appele par le client quand son timer 30s atteint 0 sans qu'il ait trouve
 * le mot. Gere les 2 cas :
 *   - Rounds intermediaires (0, 1) : marque le joueur comme found=false ;
 *     si l'autre joueur est aussi found=false (les 2 ont timeout sans
 *     personne gagner), passe le match en phase=roundEnd (personne ne
 *     gagne ce round).
 *   - Dernier round (2) : marque le joueur comme found=false ; si l'autre
 *     joueur est aussi found=false, termine le match (phase=finished)
 *     avec calcul du gagnant final via rounds_won + tiebreaker temps.
 *
 * Idempotence : les 2 clients vont appeler en parallele au timeout. Le
 * second appel voit `found` deja set a false et la phase deja avancee,
 * retourne OK silencieusement.
 *
 * Garde-fous :
 *   - Verifie que le delai minimum (28s) s'est ecoule depuis phase_started_at
 *     (anti-cheat : un client ne peut pas declarer le timeout avant l'heure).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import { readAnswer } from "./matchAnswers";

interface SubmitRoundTimeoutData {
  match_id: string;
  round: number;
}

interface SubmitRoundTimeoutResult {
  ok: true;
  new_phase: string;
  current_round: number;
  /** true tant qu'on attend que l'adversaire agisse (le client doit re-tenter). */
  waiting_for_opponent?: boolean;
}

const MIN_ELAPSED_MS = 28000; // tolerance 2s sous les 30s du round
// Au-dela de ce delai, si l'adversaire n'a TOUJOURS ni trouve ni timeout, on
// le considere injoignable (AWOL : deconnecte, app tuee) et on resout le round
// quand meme — sinon le duel reste bloque a vie (pas de transition resultat).
// 30s de round + 8s de grace : laisse le temps a un adversaire lent de timeout.
const OPPONENT_AWOL_MS = 38000;

interface RoundResult {
  progress?: number;
  found?: boolean;
  finished_at?: number;
  time_taken_ms?: number;
}

interface PlayerState {
  rounds_won: number;
  total_time_ms: number;
  progress: number;
  found: boolean;
  rounds?: Record<string, RoundResult> | RoundResult[];
}

function _getRoundResult(
  player: PlayerState | undefined,
  round: number
): RoundResult | undefined {
  if (!player?.rounds) return undefined;
  const rounds = player.rounds;
  if (Array.isArray(rounds)) {
    return rounds[round];
  }
  return rounds[String(round)];
}

export const submitRoundTimeout = onCall<
  SubmitRoundTimeoutData,
  Promise<SubmitRoundTimeoutResult>
>({ region: "europe-west1", enforceAppCheck: true }, async (request) => {
  const callerUid = requireAuth(request.auth);
  const { match_id, round } = request.data;

  if (!match_id || typeof match_id !== "string") {
    throw new HttpsError("invalid-argument", "match_id requis.");
  }
  if (typeof round !== "number" || round < 0 || round > 2) {
    throw new HttpsError("invalid-argument", "round doit etre 0, 1 ou 2.");
  }

  const rtdb = getDatabase();
  const matchRef = rtdb.ref(`matches/${match_id}`);
  const snap = await matchRef.get();
  if (!snap.exists()) {
    throw new HttpsError("not-found", `Match ${match_id} introuvable.`);
  }

  const data = snap.val() as {
    phase: string;
    current_round: number;
    total_rounds: number;
    phase_started_at?: number;
    created_at?: number;
    players?: Record<string, PlayerState>;
    winner?: string;
  };

  // Idempotence : si la phase n'est plus active, l'autre client a deja
  // declare le timeout ou un joueur a gagne. No-op.
  if (data.phase !== "active") {
    return {
      ok: true,
      new_phase: data.phase,
      current_round: data.current_round,
    };
  }

  if (data.current_round !== round) {
    throw new HttpsError(
      "failed-precondition",
      `Round invalide: recu ${round}, courant ${data.current_round}.`
    );
  }

  const players = data.players ?? {};
  if (!Object.keys(players).includes(callerUid)) {
    throw new HttpsError(
      "permission-denied",
      "Pas participant de ce match."
    );
  }

  // Anti-cheat : delai minimum ecoule depuis le debut du round.
  const startedAt = data.phase_started_at ?? data.created_at ?? Date.now();
  const elapsed = Date.now() - startedAt;
  if (elapsed < MIN_ELAPSED_MS) {
    throw new HttpsError(
      "failed-precondition",
      `Timer pas encore ecoule (${elapsed}ms < ${MIN_ELAPSED_MS}ms).`
    );
  }

  const now = Date.now();
  const totalRounds = data.total_rounds ?? 3;
  const isLastRound = round >= totalRounds - 1;

  // Reveal de la reponse de la manche courante (la manche se termine quand on
  // bascule en roundEnd/finished). Fragment vide si introuvable (best-effort).
  const answer = await readAnswer(match_id, round);
  const reveal: Record<string, unknown> =
    answer != null ? { [`rounds/${round}/answer`]: answer } : {};

  // --- Marquer ce joueur comme timeout (found=false explicite) ---
  await matchRef.update({
    [`players/${callerUid}/rounds/${round}`]: {
      progress: 0,
      found: false,
      time_taken_ms: 30000,
    },
  });

  // --- RE-LIRE le state apres notre ecriture pour detecter une race
  //     condition avec l'autre client qui aurait appele en parallele.
  //     Sans ce re-read, les 2 appels lisent un state ou aucun n'a encore
  //     timeout, et aucun ne declenche la transition. ---
  const freshSnap = await matchRef.get();
  if (!freshSnap.exists()) {
    return { ok: true, new_phase: data.phase, current_round: data.current_round };
  }
  const freshData = freshSnap.val() as typeof data;
  // Si une autre CF a deja avance la phase, no-op.
  if (freshData.phase !== "active") {
    return {
      ok: true,
      new_phase: freshData.phase,
      current_round: freshData.current_round,
    };
  }
  const freshPlayers = freshData.players ?? {};

  // --- Verifier si l'autre joueur a aussi timeout (ou n'a pas trouve) ---
  const otherUid = Object.keys(freshPlayers).find((uid) => uid !== callerUid);
  if (!otherUid) {
    // Match a 1 seul joueur (cas anormal) : termine.
    await matchRef.update({
      phase: "finished",
      phase_started_at: now,
      winner: null,
      ...reveal,
    });
    return { ok: true, new_phase: "finished", current_round: round };
  }

  const otherRoundResult = _getRoundResult(freshPlayers[otherUid], round);
  const otherHasFound = otherRoundResult?.found === true;
  const otherHasTimeout =
    otherRoundResult?.found === false && otherRoundResult.time_taken_ms != null;

  // Si l'autre a trouve : on ne fait rien (submitRoundWin a deja gere).
  if (otherHasFound) {
    return {
      ok: true,
      new_phase: freshData.phase,
      current_round: freshData.current_round,
    };
  }

  // Si l'autre n'a ni trouve ni timeout : deux cas.
  if (!otherHasTimeout) {
    // (a) Encore dans le delai de grace : on attend que l'autre client
    //     appelle submitRoundTimeout (ou submitRoundWin s'il trouve). Le
    //     client appelant re-tentera tant que `waiting_for_opponent`.
    if (elapsed < OPPONENT_AWOL_MS) {
      return {
        ok: true,
        new_phase: freshData.phase,
        current_round: freshData.current_round,
        waiting_for_opponent: true,
      };
    }
    // (b) Au-dela de la grace, l'adversaire est injoignable (AWOL) : on le
    //     marque explicitement comme timeout et on resout le round/match,
    //     pour ne pas bloquer le joueur present. (Le gagnant final est
    //     calcule sur rounds_won : un adversaire AWOL n'a rien gagne.)
    await matchRef.update({
      [`players/${otherUid}/rounds/${round}`]: {
        progress: 0,
        found: false,
        time_taken_ms: 30000,
        awol: true,
      },
    });
    // on continue vers la logique d'avancement de phase ci-dessous.
  }

  // --- Les 2 joueurs ont timeout : avancer la phase ---
  if (!isLastRound) {
    // Round intermediaire : passer a roundEnd (personne ne gagne ce round).
    await matchRef.update({
      phase: "roundEnd",
      phase_started_at: now,
      ...reveal,
    });
    return { ok: true, new_phase: "roundEnd", current_round: round };
  }

  // --- Dernier round + timeout double : terminer le match ---
  const callerRoundsWon = freshPlayers[callerUid]?.rounds_won ?? 0;
  const otherRoundsWon = freshPlayers[otherUid]?.rounds_won ?? 0;
  const callerTotalTime = freshPlayers[callerUid]?.total_time_ms ?? 0;
  const otherTotalTime = freshPlayers[otherUid]?.total_time_ms ?? 0;

  let finalWinner: string | null;
  if (callerRoundsWon > otherRoundsWon) {
    finalWinner = callerUid;
  } else if (otherRoundsWon > callerRoundsWon) {
    finalWinner = otherUid;
  } else if (callerTotalTime > 0 && otherTotalTime > 0) {
    finalWinner = callerTotalTime <= otherTotalTime ? callerUid : otherUid;
  } else if (callerTotalTime > 0) {
    finalWinner = callerUid;
  } else if (otherTotalTime > 0) {
    finalWinner = otherUid;
  } else {
    finalWinner = null; // egalite parfaite 0-0-0 sans temps
  }

  await matchRef.update({
    phase: "finished",
    phase_started_at: now,
    winner: finalWinner,
    ...reveal,
  });

  return { ok: true, new_phase: "finished", current_round: round };
});
