/**
 * advanceRound — RTDB trigger (onValueUpdated).
 *
 * Choix architectural : transitions pilotees par le SERVEUR, pas par l'UI.
 *
 * Justification :
 *   - Dans un duel 1v1 temps reel, les deux appareils peuvent avoir des
 *     connectivites differentes. Si on delegue la transition a l'UI de l'un
 *     des deux joueurs (celui qui a gagne ou l'autre), on risque la desync :
 *     le joueur A voit "Round 2" pendant que B est encore sur "Round 1".
 *   - Avec un trigger RTDB cote serveur, la source de verite est unique :
 *     l'ecriture dans /matches/{id}/phase. Les deux clients observent le
 *     meme stream RTDB et transitionnent simultanement.
 *   - Simplicite : pas de double-timer client, pas de race condition sur
 *     "qui declenche la transition".
 *
 * Flux :
 *   roundEnd (3 s)  → current_round += 1, phase = countdown
 *   countdown (3 s) → phase = active
 *
 * Les deux delais sont de 3 s (configurable via ROUND_END_DELAY_MS /
 * COUNTDOWN_DELAY_MS). L'UI peut afficher une animation de ce cote sans
 * avoir a piloter la transition.
 *
 * Garde-fous :
 *   - Verifie que la phase n'a pas deja change avant d'ecrire (idempotence).
 *   - N'agit pas si le match est deja en "finished".
 *   - Le setTimeout de 3 s est acceptable dans une CF v2 (instance chaude,
 *     pas de cold start entre les deux delais pour le meme match).
 */

import { onValueUpdated } from "firebase-functions/v2/database";
import { getDatabase } from "firebase-admin/database";

const ROUND_END_DELAY_MS = 3000;
const COUNTDOWN_DELAY_MS = 3000;

// Note region : la RTDB du projet est sur firebaseio.com (us-central1).
// Le trigger doit etre dans la meme region que sa database, sinon Firebase
// refuse le deploiement avec "pattern cannot match any databases in region X".
export const advanceRound = onValueUpdated(
  {
    ref: "/matches/{matchId}/phase",
    region: "us-central1",
  },
  async (event) => {
    const matchId = event.params["matchId"];
    const newPhase = event.data.after.val() as string | null;

    if (newPhase === "roundEnd") {
      await _handleRoundEnd(matchId);
    } else if (newPhase === "countdown") {
      await _handleCountdown(matchId);
    }
    // Autres phases (waiting, active, intro, finished) : rien a faire.
  }
);

async function _handleRoundEnd(matchId: string): Promise<void> {
  await new Promise<void>((resolve) => setTimeout(resolve, ROUND_END_DELAY_MS));

  const rtdb = getDatabase();
  const matchRef = rtdb.ref(`matches/${matchId}`);
  const snap = await matchRef.get();
  if (!snap.exists()) return;

  const data = snap.val() as { phase: string; current_round: number; total_rounds: number };

  // Idempotence : verifier que la phase est toujours "roundEnd".
  if (data.phase !== "roundEnd") return;
  if (data.current_round >= (data.total_rounds ?? 3) - 1) {
    // Ne devrait pas arriver (submitRoundWin gere le cas dernier round), mais
    // securite supplementaire.
    return;
  }

  const nextRound = data.current_round + 1;
  await matchRef.update({
    current_round: nextRound,
    phase: "countdown",
    phase_started_at: Date.now(),
  });
}

async function _handleCountdown(matchId: string): Promise<void> {
  await new Promise<void>((resolve) => setTimeout(resolve, COUNTDOWN_DELAY_MS));

  const rtdb = getDatabase();
  const matchRef = rtdb.ref(`matches/${matchId}`);
  const snap = await matchRef.get();
  if (!snap.exists()) return;

  const data = snap.val() as { phase: string };

  // Idempotence : verifier que la phase est toujours "countdown".
  if (data.phase !== "countdown") return;

  await matchRef.update({
    phase: "active",
    phase_started_at: Date.now(),
  });
}
