/**
 * forfeitMatch — abandon d'un duel (callable v2).
 *
 * Anti-cheat (C1) : remplace l'ancien write client direct de `winner`/`phase`
 * (duel_repository.forfeit). Les règles RTDB durcies interdisent désormais au
 * client d'écrire `winner` ou `phase=finished` ; seul le serveur (Admin SDK)
 * le fait. Un joueur qui abandonne déclare donc son forfait via cette CF, qui
 * désigne l'adversaire vainqueur.
 *
 * Flux :
 *   1. Vérifie l'auth + App Check.
 *   2. Lit /matches/{matchId}. Idempotent si déjà `finished`.
 *   3. Vérifie que le caller est participant.
 *   4. Désigne l'autre joueur vainqueur (ou null s'il est seul).
 *   5. Bascule phase=finished + reveal de la réponse de la manche courante.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import { readAnswer } from "./matchAnswers";

interface ForfeitMatchData {
  matchId: string;
}

interface ForfeitMatchResult {
  ok: true;
  winner: string | null;
}

export const forfeitMatch = onCall<
  ForfeitMatchData,
  Promise<ForfeitMatchResult>
>({ region: "europe-west1", enforceAppCheck: true }, async (request) => {
  const callerUid = requireAuth(request.auth);
  const { matchId } = request.data;

  if (!matchId || typeof matchId !== "string") {
    throw new HttpsError("invalid-argument", "matchId requis.");
  }

  const rtdb = getDatabase();
  const matchRef = rtdb.ref(`matches/${matchId}`);
  const snap = await matchRef.get();
  if (!snap.exists()) {
    throw new HttpsError("not-found", `Match ${matchId} introuvable.`);
  }

  const data = snap.val() as {
    phase?: string;
    current_round?: number;
    winner?: string | null;
    players?: Record<string, unknown>;
  };

  const players = data.players ?? {};
  const uids = Object.keys(players);

  if (!uids.includes(callerUid)) {
    throw new HttpsError(
      "permission-denied",
      "Tu n'es pas participant de ce match."
    );
  }

  // Idempotence : déjà terminé → no-op.
  if (data.phase === "finished") {
    return { ok: true, winner: data.winner ?? null };
  }

  const otherUid = uids.find((u) => u !== callerUid) ?? null;
  const round = data.current_round ?? 0;
  const answer = await readAnswer(matchId, round);

  await matchRef.update({
    phase: "finished",
    phase_started_at: Date.now(),
    winner: otherUid,
    forfeited_by: callerUid,
    ...(answer != null ? { [`rounds/${round}/answer`]: answer } : {}),
  });

  return { ok: true, winner: otherUid };
});
