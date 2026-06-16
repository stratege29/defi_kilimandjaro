/**
 * cancelMatch — Cloud Function callable (v2).
 *
 * Supprime /lobby/{uid} dans Realtime DB.
 * Appelé par le client quand :
 * - L'utilisateur appuie sur "ANNULER" dans le lobby.
 * - Le timeout de 30 s expire côté client.
 */

import { onCall } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";

interface CancelMatchResult {
  success: boolean;
}

export const cancelMatch = onCall<void, Promise<CancelMatchResult>>(
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request.auth);

    const rtdb = getDatabase();
    await rtdb.ref(`lobby/${uid}`).remove();

    return { success: true };
  }
);
