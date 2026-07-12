/**
 * sendTournamentReminders — logique de rappel push avant le démarrage d'un
 * tournoi, appelée depuis tournamentTicker (même cadence 1 min, pas de CF
 * planifiée séparée).
 *
 * Idempotence : verrou transactionnel sur le flag `reminder_sent` du doc
 * tournoi (même pattern que `finalizeTournament` dans tournamentTicker.ts).
 */

import { logger } from "firebase-functions/v2";
import {
  getFirestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";

import { participantsRef, toMillis } from "./helpers";
import { sendFcmToUser } from "../utils/fcm";

/** Fenêtre avant `start_at` pendant laquelle le rappel doit partir. */
export const REMINDER_LEAD_MS = 5 * 60_000; // 5 minutes

/**
 * Un tournoi `scheduled` est-il dû pour son rappel de démarrage imminent ?
 *
 * Dû si maintenant est dans la fenêtre [start_at - leadMs, start_at[ et le
 * rappel n'a pas déjà été envoyé. Ne se déclenche jamais après start_at (le
 * ticker aura basculé le tournoi en `live` — pas de rappel a posteriori).
 *
 * Fonction pure, testable sans Firestore.
 */
export function isReminderDue(
  status: string,
  startAtMs: number,
  reminderSent: boolean,
  nowMs: number,
  leadMs: number = REMINDER_LEAD_MS
): boolean {
  if (status !== "scheduled" || reminderSent) return false;
  return nowMs >= startAtMs - leadMs && nowMs < startAtMs;
}

/**
 * Parcourt des tournois `scheduled` et envoie un rappel push à chaque
 * participant inscrit des tournois dus, avec verrou idempotent par tournoi.
 */
export async function sendTournamentReminders(
  scheduledDocs: QueryDocumentSnapshot[],
  now: number
): Promise<void> {
  const db = getFirestore();

  for (const doc of scheduledDocs) {
    const d = doc.data();
    const startAtMs = toMillis(d["start_at"]);
    const reminderSent = d["reminder_sent"] === true;

    if (
      !isReminderDue(d["status"] as string, startAtMs, reminderSent, now)
    ) {
      continue;
    }

    // Verrou transactionnel : un seul tick gagne l'envoi pour ce tournoi.
    const locked = await db.runTransaction(async (tx) => {
      const snap = await tx.get(doc.ref);
      const dd = snap.data();
      if (!dd || dd["reminder_sent"] === true || dd["status"] !== "scheduled") {
        return false;
      }
      tx.update(doc.ref, { reminder_sent: true });
      return true;
    });
    if (!locked) continue;

    const tid = doc.id;
    const tournamentName = (d["name"] as string) ?? "Tournoi";

    try {
      const partsSnap = await participantsRef(tid).get();
      const results = await Promise.allSettled(
        partsSnap.docs.map((p) =>
          sendFcmToUser(
            p.id,
            "L'arène va s'ouvrir !",
            `${tournamentName} démarre dans quelques minutes. Prépare-toi à duelliser.`,
            { tournament_id: tid, type: "tournament_reminder" }
          )
        )
      );
      const failures = results.filter((r) => r.status === "rejected").length;
      logger.info("sendTournamentReminders: rappel envoyé", {
        tid,
        participants: partsSnap.size,
        failures,
      });
    } catch (err) {
      logger.error("sendTournamentReminders: échec pour un tournoi", {
        tid,
        err,
      });
    }
  }
}
