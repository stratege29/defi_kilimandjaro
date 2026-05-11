/**
 * sendChallengeNotif — Realtime DB onCreate trigger.
 *
 * Déclenché à chaque création de /matches/{matchId}.
 *
 * Logique :
 * - QR friend flow (pas de target_uid) → pas de notif (l'autre scanne le QR).
 * - ELO matchmaking flow (pas de target_uid) → pas de notif (les 2 sont dans le lobby).
 * - Défi async (target_uid présent) → envoie une notif FCM au target_uid avec le
 *   matchId encodé dans le payload data (pour deep link routing côté client).
 *
 * Garde-fou : si le destinataire est dans un match actif, la notif est ignorée
 * (géré dans sendFcmToUser).
 */

import { onValueCreated } from "firebase-functions/v2/database";
import { sendFcmToUser } from "../utils/fcm";
import * as logger from "firebase-functions/logger";

interface MatchData {
  created_by?: string;
  target_uid?: string;
  phase?: string;
  is_ranked?: boolean;
}

export const sendChallengeNotif = onValueCreated(
  {
    ref: "/matches/{matchId}",
    // La RTDB de ce projet est en us-central1 (URL legacy firebaseio.com),
    // pas europe-west1 — la fonction doit donc tourner dans la même région
    // que la DB pour que le trigger soit valide. Les callables (requestMatch,
    // endMatch, cancelMatch, requestRematch) restent en europe-west1 pour
    // la latence Côte d'Ivoire (les callables ne sont pas région-bound DB).
    region: "us-central1",
    instance: process.env["RTDB_INSTANCE"] ?? undefined,
  },
  async (event) => {
    const matchId: string = event.params["matchId"];
    const matchData = event.data.val() as MatchData | null;

    if (!matchData) {
      logger.warn(`[sendChallengeNotif] Match ${matchId} vide — skip.`);
      return;
    }

    const targetUid = matchData.target_uid;

    // Seul le flow "défi async" avec target_uid déclenche une notif.
    if (!targetUid || typeof targetUid !== "string") {
      logger.info(
        `[sendChallengeNotif] Match ${matchId} sans target_uid — pas de notif.`
      );
      return;
    }

    logger.info(
      `[sendChallengeNotif] Match ${matchId} → notif FCM pour uid=${targetUid}`
    );

    await sendFcmToUser(
      targetUid,
      "Tu as un défi !",
      "Un grimpeur t'attend pour un duel. Tape pour rejoindre.",
      {
        matchId,
        type: "duel_challenge",
      }
    );
  }
);
