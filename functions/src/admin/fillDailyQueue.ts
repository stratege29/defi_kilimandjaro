/**
 * Planificateur de la file « Question du jour » (`daily_queue`).
 *
 * Chaque jour (05:00 Abidjan = UTC), remplit les prochains jours LIBRES (horizon
 * 14 j) avec les questions en file (FIFO sur created_at) : pour chaque date sans
 * `daily_challenges/{date}`, pioche la plus ancienne question `queued` et l'y
 * assigne (status → used). Abidjan = UTC+0 → date locale = date UTC.
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const HORIZON_DAYS = 14;

export const fillDailyQueue = onSchedule(
  {
    schedule: "0 5 * * *",
    timeZone: "Africa/Abidjan",
    region: "europe-west1",
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const qsnap = await db
      .collection("daily_queue")
      .where("status", "==", "queued")
      .get();
    if (qsnap.empty) {
      logger.info("fillDailyQueue: file vide.");
      return;
    }
    const queued = qsnap.docs
      .map((d) => ({
        ref: d.ref,
        data: d.data(),
        at:
          (d.data().created_at as { toMillis?: () => number })?.toMillis?.() ?? 0,
      }))
      .sort((a, b) => a.at - b.at);

    let qi = 0;
    let assigned = 0;
    for (let i = 0; i < HORIZON_DAYS && qi < queued.length; i++) {
      const date = new Date(Date.now() + i * 86_400_000)
        .toISOString()
        .slice(0, 10);
      const dref = db.collection("daily_challenges").doc(date);
      if ((await dref.get()).exists) continue;

      const item = queued[qi++];
      const core: Record<string, unknown> = { ...item.data };
      delete core.status;
      delete core.created_at;
      delete core.created_by;
      delete core.used_date;

      await dref.set({
        ...core,
        id: `daily_${date.replace(/-/g, "")}`,
        pack: "daily",
        assigned_at: FieldValue.serverTimestamp(),
        assigned_by: "fillDailyQueue",
        custom: true,
      });
      await item.ref.set(
        { status: "used", used_date: date },
        { merge: true }
      );
      assigned++;
    }
    logger.info("fillDailyQueue", { assigned, remaining: queued.length - qi });
  }
);
