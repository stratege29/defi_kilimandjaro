import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

import { requireAuth } from "../utils/auth";

/**
 * `deleteAccount` — suppression définitive du compte joueur (RGPD / exigence
 * stores : Apple 5.1.1(v), Google Play Data deletion).
 *
 * Purge, dans l'ordre :
 *   1. `profiles/{uid}` — profil ELO + display_name (seule PII réelle).
 *   2. `users/{uid}` (récursif) — wallet, inventory, inventory_audit.
 *   3. L'utilisateur Firebase Auth (en dernier : invalide les requêtes
 *      futures du token).
 *
 * Idempotent : si les documents n'existent pas, ne lève pas d'erreur. Appelable
 * par n'importe quel utilisateur authentifié (anonyme ou lié) — chacun ne peut
 * supprimer que son propre uid.
 *
 * Les nœuds RTDB `/matches/{id}` ne sont pas purgés : ils ne contiennent que
 * des références d'uid (aucune PII) et sont éphémères.
 */
export const deleteAccount = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<{ success: true; uid: string }> => {
    const uid = requireAuth(req.auth);
    const db = getFirestore();

    try {
      await db.collection("profiles").doc(uid).delete();
      await db.recursiveDelete(db.collection("users").doc(uid));
    } catch (e) {
      logger.error("deleteAccount: firestore purge failed", { uid, error: e });
      throw new HttpsError(
        "internal",
        "Échec de la suppression des données. Réessaie plus tard."
      );
    }

    try {
      await getAuth().deleteUser(uid);
    } catch (e) {
      // Idempotence : si l'utilisateur Auth n'existe déjà plus, on tolère.
      const code = (e as { code?: string }).code;
      if (code !== "auth/user-not-found") {
        logger.error("deleteAccount: auth deleteUser failed", { uid, error: e });
        throw new HttpsError(
          "internal",
          "Échec de la suppression du compte. Réessaie plus tard."
        );
      }
    }

    logger.info("deleteAccount: done", { uid });
    return { success: true, uid };
  }
);
