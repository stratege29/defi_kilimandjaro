/**
 * advancePhase — transition de phase pilotee par le client (callable v2).
 *
 * Remplace l'ancien `advanceRound` (RTDB trigger + setTimeout 3s), qui n'etait
 * pas fiable car Cloud Functions v2 tuent leurs instances en idle, ce qui
 * "perd" les setTimeout en attente.
 *
 * Le client appelle cette CF apres avoir affiche son animation locale
 * (roundEnd 3s, countdown 3s). La CF valide :
 *   - le caller est participant du match
 *   - la phase courante est bien roundEnd ou countdown
 *   - le delai minimal (2s pour tolerer un peu de latence) est ecoule depuis
 *     phase_started_at, pour eviter qu'un client malicieux skip l'animation
 *
 * Idempotence : les 2 clients vont appeler en parallele a la fin de leur
 * animation. Le premier qui passe ecrit la nouvelle phase. Le second voit la
 * phase deja avancee et retourne OK silencieusement.
 *
 * Transitions :
 *   roundEnd  -> countdown (current_round += 1)
 *   countdown -> active
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";

interface AdvancePhaseData {
  match_id: string;
}

interface AdvancePhaseResult {
  ok: true;
  new_phase: string;
  current_round: number;
}

const MIN_ELAPSED_MS = 2000; // tolerance 1s sous les 3s d'animation client

export const advancePhase = onCall<AdvancePhaseData, Promise<AdvancePhaseResult>>(
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const callerUid = requireAuth(request.auth);
    const { match_id } = request.data;

    if (!match_id || typeof match_id !== "string") {
      throw new HttpsError("invalid-argument", "match_id requis.");
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
      players?: Record<string, unknown>;
    };

    const players = data.players ?? {};
    if (!Object.keys(players).includes(callerUid)) {
      throw new HttpsError(
        "permission-denied",
        "Pas participant de ce match."
      );
    }

    const startedAt = data.phase_started_at ?? data.created_at ?? Date.now();
    const elapsed = Date.now() - startedAt;

    // --- Transition roundEnd -> countdown ---
    if (data.phase === "roundEnd") {
      if (elapsed < MIN_ELAPSED_MS) {
        // Idempotence : si appele trop tot, on retourne le state actuel.
        return {
          ok: true,
          new_phase: data.phase,
          current_round: data.current_round,
        };
      }
      const nextRound = (data.current_round ?? 0) + 1;
      await matchRef.update({
        phase: "countdown",
        current_round: nextRound,
        phase_started_at: Date.now(),
      });
      return { ok: true, new_phase: "countdown", current_round: nextRound };
    }

    // --- Transition countdown -> active ---
    if (data.phase === "countdown") {
      if (elapsed < MIN_ELAPSED_MS) {
        return {
          ok: true,
          new_phase: data.phase,
          current_round: data.current_round,
        };
      }
      await matchRef.update({
        phase: "active",
        phase_started_at: Date.now(),
      });
      return {
        ok: true,
        new_phase: "active",
        current_round: data.current_round,
      };
    }

    // --- Phase deja avancee ou inattendue : idempotent ---
    return {
      ok: true,
      new_phase: data.phase,
      current_round: data.current_round,
    };
  },
);
