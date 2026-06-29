/**
 * fcm.ts — Helper centralisé pour l'envoi de messages FCM.
 *
 * Utilise le Admin SDK Messaging qui supporte APNs + FCM nativement.
 * Le token FCM du destinataire est lu depuis Firestore profiles/{uid}/fcm_token.
 *
 * Règles :
 * - Ne jamais envoyer si le destinataire n'a pas de token enregistré.
 * - Ne jamais envoyer si le destinataire est dans un match phase=active.
 * - Toutes les erreurs sont loggées mais ne font pas échouer la CF appelante.
 */

import { getFirestore } from "firebase-admin/firestore";
import { getDatabase } from "firebase-admin/database";
import { getMessaging, Message } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

/** Charge le token FCM d'un utilisateur depuis Firestore. */
async function _getFcmToken(uid: string): Promise<string | null> {
  const snap = await getFirestore().collection("profiles").doc(uid).get();
  if (!snap.exists) return null;
  const token = snap.data()?.["fcm_token"];
  if (typeof token !== "string" || token.trim() === "") return null;
  return token;
}

/**
 * Vérifie que le destinataire n'est pas actuellement dans un match actif.
 *
 * Scan /matches/ à la recherche d'un match phase=active contenant uid.
 * Si un match actif est trouvé, retourne true (bloquer l'envoi).
 *
 * NOTE : Realtime DB ne supporte pas les requêtes multi-champs.
 * On maintient un nœud d'index léger /active_players/{uid}: matchId.
 * Si ce nœud n'est pas encore en place (PR future), on skip la vérification.
 */
async function _isInActiveMatch(uid: string): Promise<boolean> {
  try {
    const snap = await getDatabase().ref(`active_players/${uid}`).get();
    return snap.exists();
  } catch {
    // Fail-open : si le nœud n'existe pas, ne pas bloquer l'envoi.
    return false;
  }
}

/**
 * Envoie une notification FCM à un utilisateur.
 *
 * @param recipientUid - UID Firebase du destinataire.
 * @param title        - Titre de la notification.
 * @param body         - Corps de la notification.
 * @param data         - Payload data (pour le routing deep link côté client).
 * @returns true si le message a été envoyé, false sinon (pas de token, blocage).
 */
export async function sendFcmToUser(
  recipientUid: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<boolean> {
  // 1. Récupérer le token FCM.
  const token = await _getFcmToken(recipientUid);
  if (!token) {
    logger.info(`[FCM] Pas de token pour uid=${recipientUid}, skip.`);
    return false;
  }

  // 2. Vérifier que le joueur n'est pas dans un duel actif.
  const inMatch = await _isInActiveMatch(recipientUid);
  if (inMatch) {
    logger.info(
      `[FCM] uid=${recipientUid} est dans un match actif — notif supprimée.`
    );
    return false;
  }

  // 3. Construire et envoyer le message.
  const message: Message = {
    token,
    notification: { title, body },
    data,
    apns: {
      payload: {
        aps: {
          // Son système par défaut + badge + alerte obligatoire sur iOS.
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
      },
    },
    android: {
      priority: "high",
      notification: {
        sound: "default",
        channelId: "duel_challenges",
      },
    },
  };

  try {
    const msgId = await getMessaging().send(message);
    logger.info(`[FCM] Message envoyé uid=${recipientUid} msgId=${msgId}`);
    return true;
  } catch (err) {
    logger.error(`[FCM] Échec envoi uid=${recipientUid}`, err);
    return false;
  }
}

/**
 * Envoie une notification FCM à un topic broadcast (tous les abonnés).
 *
 * Utilisé pour les annonces de contenu (nouveaux packs / mises à jour) via le
 * topic `pack_updates`. Contrairement à {@link sendFcmToUser}, pas de lecture
 * de token ni de garde "match actif" : c'est un broadcast.
 *
 * @param topic - Nom du topic (ex. `pack_updates`).
 * @param title - Titre de la notification.
 * @param body  - Corps de la notification.
 * @param data  - Payload data (routing deep link côté client, ex. `type`).
 * @returns true si le message a été accepté par FCM, false sinon.
 */
export async function sendFcmToTopic(
  topic: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<boolean> {
  const message: Message = {
    topic,
    notification: { title, body },
    data,
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
      },
    },
    android: {
      priority: "high",
      notification: {
        sound: "default",
        channelId: "content_updates",
      },
    },
  };

  try {
    const msgId = await getMessaging().send(message);
    logger.info(`[FCM] Topic message envoyé topic=${topic} msgId=${msgId}`);
    return true;
  } catch (err) {
    logger.error(`[FCM] Échec envoi topic=${topic}`, err);
    return false;
  }
}
