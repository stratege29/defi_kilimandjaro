/**
 * respondToChallenge — Reponse a un challenge async (rematch) callable v2.
 *
 * Le caller est l'opponent qui recoit le challenge (target_uid du match).
 * Il accepte ou refuse via le dialog modal in-app (IncomingChallengeListener).
 *
 * Flow accepte :
 *   1. Verifier callerUid == target_uid du match.
 *   2. Cleanup pending_challenges/{callerUid}.
 *   3. Retourner OK — le client appelle ensuite joinOpen pour rejoindre.
 *
 * Flow refuse :
 *   1. Verifier callerUid == target_uid du match.
 *   2. Cleanup pending_challenges/{callerUid}.
 *   3. Ecrire phase=finished + declined=true sur le match.
 *   4. Le caller (initiateur du rematch) detecte via stream RTDB la phase
 *      finished sans winner et affiche "Adversaire a refuse".
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import * as logger from "firebase-functions/logger";

interface RespondToChallengeData {
  matchId: string;
  accept: boolean;
}

interface RespondToChallengeResult {
  ok: true;
  accepted: boolean;
}

export const respondToChallenge = onCall<
  RespondToChallengeData,
  Promise<RespondToChallengeResult>
>(
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const callerUid = requireAuth(request.auth);
    const { matchId, accept } = request.data;

    if (!matchId || typeof matchId !== "string") {
      throw new HttpsError("invalid-argument", "matchId requis.");
    }
    if (typeof accept !== "boolean") {
      throw new HttpsError("invalid-argument", "accept (bool) requis.");
    }

    const rtdb = getDatabase();
    const matchRef = rtdb.ref(`matches/${matchId}`);
    const snap = await matchRef.get();
    if (!snap.exists()) {
      throw new HttpsError("not-found", `Match ${matchId} introuvable.`);
    }

    const data = snap.val() as {
      target_uid?: string;
      created_by?: string;
      phase?: string;
    };

    if (data.target_uid !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "Tu n'es pas la cible de ce challenge."
      );
    }

    // Cleanup pending_challenges en tous les cas.
    const pendingRef = rtdb.ref(`pending_challenges/${callerUid}`);

    if (accept) {
      // Le client appellera joinOpen apres cette reponse pour ajouter
      // son entree players et basculer la phase en countdown.
      await pendingRef.remove();
      logger.info(
        `[respondToChallenge] ACCEPTED matchId=${matchId} by ${callerUid}`
      );
      return { ok: true, accepted: true };
    }

    // Refus : marquer le match comme decline pour notifier le caller.
    // Le caller observe le match en stream et detecte phase=finished + declined.
    const updates: Record<string, unknown> = {
      [`matches/${matchId}/phase`]: "finished",
      [`matches/${matchId}/declined`]: true,
      [`matches/${matchId}/declined_by`]: callerUid,
      [`matches/${matchId}/declined_at`]: Date.now(),
      [`pending_challenges/${callerUid}`]: null,
    };
    await rtdb.ref().update(updates);

    logger.info(
      `[respondToChallenge] DECLINED matchId=${matchId} by ${callerUid}`
    );
    return { ok: true, accepted: false };
  }
);
