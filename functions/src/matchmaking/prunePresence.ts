/**
 * prunePresence — Cloud Function planifiée (v2 scheduler).
 *
 * Exécutée toutes les 1 minute. Responsable de nettoyer `presence/` des
 * entrées périmées (> 120 secondes sans heartbeat) et recalculer
 * `/lobby/stats/online` avec le décompte actuel des joueurs frais.
 *
 * Source de vérité = ensemble des entrées `presence/{uid}` dont le timestamp
 * est < 120s. Les clients maintiennent ce pool via heartbeat 45s + onDisconnect().remove().
 * La CF n'écrit jamais `presence/`, elle lit uniquement et met à jour le compteur.
 *
 * Pattern standard de présence : on évite les increment/decrement côté client
 * (race conditions) et la fuite de valeurs. À la place :
 * 1. Client écrit/maintient `presence/{uid}`.
 * 2. CF planifiée recalcule le compteur centralisé.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getDatabase } from "firebase-admin/database";

const TTL_MS = 120000; // 120 secondes, > 45s heartbeat + marge

/**
 * Prune entries in presence/ with ts > TTL and recalculate /lobby/stats/online.
 *
 * Runs every 1 minute.
 */
export const prunePresence = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const rtdb = getDatabase();
    const now = Date.now();

    try {
      // Read all presence entries
      const presenceSnap = await rtdb.ref("presence").get();

      if (!presenceSnap.exists()) {
        // No presence data yet, set counter to 0
        await rtdb.ref("lobby/stats/online").set(0);
        logger.info("prunePresence: no presence entries, set online=0");
        return;
      }

      const presenceData = presenceSnap.val() as Record<
        string,
        { ts: number } | unknown
      >;

      const toDelete: string[] = [];
      let freshCount = 0;

      for (const [uid, entry] of Object.entries(presenceData)) {
        if (typeof entry === "object" && entry !== null && "ts" in entry) {
          const ts = (entry as { ts: number }).ts;
          const ageMs = now - ts;

          if (ageMs > TTL_MS) {
            toDelete.push(uid);
            logger.debug(`prunePresence: deleting ${uid} (age ${ageMs}ms)`);
          } else {
            freshCount++;
          }
        }
      }

      // Build multi-path update: always refresh the counter (freshCount can
      // change without any deletion when a new player joins) + drop stale entries.
      const updates: Record<string, unknown> = {
        "lobby/stats/online": freshCount,
      };

      for (const uid of toDelete) {
        updates[`presence/${uid}`] = null;
      }

      await rtdb.ref().update(updates);
      logger.info(
        `prunePresence: deleted ${toDelete.length} stale entries, online=${freshCount}`
      );
    } catch (error) {
      logger.error("prunePresence failed", error);
      throw error;
    }
  }
);
