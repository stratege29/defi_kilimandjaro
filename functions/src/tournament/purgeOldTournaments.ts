/**
 * purgeOldTournaments — Cloud Function planifiée (v2 scheduler).
 *
 * Hygiène Firestore : supprime les tournois `finished`/`cancelled` dont la fin
 * remonte à plus de RETENTION_DAYS, ainsi que leur sous-collection
 * `participants`. Sans ce filet, `tournaments/` grossit indéfiniment (un doc +
 * N participants par tournoi).
 *
 * Conservé : les badges gagnés (`profiles/{uid}/badges/{tid}`) — ce sont les
 * trophées du joueur, indépendants du cycle de vie du tournoi. Les tournois
 * `live`/`scheduled` ne sont jamais supprimés (garde sur le statut).
 *
 * Filtrage sans index composite : requête à inégalité simple sur `end_at`
 * (index auto), puis filtre du statut côté code.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

/// Rétention avant suppression d'un tournoi terminé (jours).
const RETENTION_DAYS = 7;

/// Taille de lot sous le plafond Firestore (500 écritures / batch).
const BATCH_LIMIT = 450;

export const purgeOldTournaments = onSchedule(
  {
    schedule: "every 24 hours",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromMillis(
      Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000
    );

    let snap;
    try {
      snap = await db
        .collection("tournaments")
        .where("end_at", "<", cutoff)
        .get();
    } catch (err) {
      logger.error("purgeOldTournaments: requête échouée", err);
      return;
    }

    let purged = 0;
    let participantsDeleted = 0;

    for (const doc of snap.docs) {
      const status = doc.data()["status"];
      // Sécurité : ne supprimer que les tournois réellement clos.
      if (status !== "finished" && status !== "cancelled") continue;

      try {
        const parts = await doc.ref.collection("participants").get();
        let batch = db.batch();
        let n = 0;
        for (const p of parts.docs) {
          batch.delete(p.ref);
          participantsDeleted++;
          if (++n >= BATCH_LIMIT) {
            await batch.commit();
            batch = db.batch();
            n = 0;
          }
        }
        // Le doc tournoi part dans le dernier lot.
        batch.delete(doc.ref);
        await batch.commit();
        purged++;
      } catch (err) {
        logger.error("purgeOldTournaments: suppression échouée", {
          tid: doc.id,
          err,
        });
      }
    }

    logger.info(
      `purgeOldTournaments: ${purged} tournoi(s) supprimé(s) ` +
        `(> ${RETENTION_DAYS}j), ${participantsDeleted} participant(s).`
    );
  }
);
