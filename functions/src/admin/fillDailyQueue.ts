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
import { getFirestore, FieldValue, FieldPath } from "firebase-admin/firestore";

const HORIZON_DAYS = 14;
/** Rétention des défis du jour passés (purge auto au-delà). */
const RETENTION_DAYS = 90;

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

/**
 * Purge des défis du jour passés (`daily_challenges/{yyyy-MM-dd}`) au-delà de la
 * rétention. Les docs sont keyés par date → on borne par documentId() < cutoff.
 * Inoffensif côté joueur (l'app ne lit que la date du jour) — simple ménage.
 * Tourne à 04:00 (avant fillDailyQueue à 05:00). Max 400 suppressions / run.
 */
export const purgeOldDailyChallenges = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: "Africa/Abidjan",
    region: "europe-west1",
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const cutoff = new Date(Date.now() - RETENTION_DAYS * 86_400_000)
      .toISOString()
      .slice(0, 10);
    const snap = await db
      .collection("daily_challenges")
      .where(FieldPath.documentId(), "<", cutoff)
      .limit(400)
      .get();
    if (snap.empty) {
      logger.info("purgeOldDailyChallenges: rien à purger.", { cutoff });
      return;
    }
    const batch = db.batch();
    let deleted = 0;
    for (const d of snap.docs) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d.id)) continue; // garde-fou : ids date seulement
      batch.delete(d.ref);
      deleted++;
    }
    await batch.commit();
    logger.info("purgeOldDailyChallenges", { cutoff, deleted });
  }
);
