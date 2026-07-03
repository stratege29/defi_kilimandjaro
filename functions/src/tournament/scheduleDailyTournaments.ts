/**
 * scheduleDailyTournaments — CF planifiée (v2 scheduler).
 *
 * Génère chaque jour les tournois « arène » récurrents, en `scheduled` :
 *   - Semaine (lun–ven) : 12h30 et 19h00.
 *   - Week-end (sam, dim) : toutes les 2 h de 08h00 à 22h00 (8 créneaux).
 * Durée 15 min chacun, noms « chics » rotatifs.
 *
 * Fuseau : Abidjan = UTC (pas de décalage horaire), donc les heures sont
 * interprétées en UTC directement. Le `tournamentTicker` bascule ensuite chaque
 * tournoi `scheduled → live` à `start_at` puis le finalise à `end_at`.
 *
 * Idempotence : id de doc déterministe `auto_<yyyy-MM-dd>_<HHMM>` + `create()`
 * (ignore ALREADY_EXISTS) → un re-run ne duplique jamais un créneau.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

/** Créneaux (heure locale = UTC) « HH:MM ». */
export const WEEKDAY_SLOTS = ["12:30", "19:00"];
export const WEEKEND_SLOTS = [
  "08:00",
  "10:00",
  "12:00",
  "14:00",
  "16:00",
  "18:00",
  "20:00",
  "22:00",
];

export const AUTO_DURATION_MIN = 15;

/** Noms « chics » à saveur griot/ivoirienne, en rotation. */
export const CHIC_NAMES = [
  "Le Cercle des Griots",
  "Couronne d'Or de Kilimandjaro",
  "L'Arène des Sages",
  "Le Grand Duel des Cauris",
  "Trône de la Savane",
  "Les Lauriers d'Abidjan",
  "La Joute des Ancêtres",
  "Concours des Champions",
  "L'Ascension Royale",
  "Le Défi des Étoiles",
  "Panthéon des Grimpeurs",
  "La Ronde des Braves",
];

/** Barème de récompenses par défaut des tournois auto. */
const AUTO_REWARDS = [
  { rank_min: 1, rank_max: 1, cauris: 500, badge_id: "tournament_gold" },
  { rank_min: 2, rank_max: 3, cauris: 250, badge_id: "tournament_silver" },
  { rank_min: 4, rank_max: 10, cauris: 100, badge_id: null },
];

interface Slot {
  hh: number;
  mm: number;
}

/** Créneaux du jour selon le jour de semaine (UTC). */
export function slotsForDate(date: Date): Slot[] {
  const dow = date.getUTCDay(); // 0 = dimanche, 6 = samedi
  const isWeekend = dow === 0 || dow === 6;
  const raw = isWeekend ? WEEKEND_SLOTS : WEEKDAY_SLOTS;
  return raw.map((s) => {
    const [hh, mm] = s.split(":").map((n) => parseInt(n, 10));
    return { hh, mm };
  });
}

/** Clé de jour UTC `yyyy-MM-dd`. */
function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Nom chic déterministe (rotation par jour + créneau, sans répétition immédiate). */
export function pickChicName(date: Date, slotIndex: number): string {
  const dayNum = Math.floor(date.getTime() / 86_400_000);
  return CHIC_NAMES[(dayNum + slotIndex) % CHIC_NAMES.length];
}

export const scheduleDailyTournaments = onSchedule(
  {
    // Chaque jour à 00:15 UTC : crée les tournois du jour courant.
    schedule: "15 0 * * *",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const slots = slotsForDate(now);
    const key = dayKey(now);

    let created = 0;
    for (let i = 0; i < slots.length; i++) {
      const { hh, mm } = slots[i];
      const start = new Date(
        Date.UTC(
          now.getUTCFullYear(),
          now.getUTCMonth(),
          now.getUTCDate(),
          hh,
          mm,
          0,
          0
        )
      );
      // Ne crée pas les créneaux déjà passés (ex. déploiement en milieu de
      // journée) — seuls les tournois à venir ont du sens.
      if (start.getTime() <= now.getTime()) continue;

      const endMs = start.getTime() + AUTO_DURATION_MIN * 60_000;
      const hhmm = `${String(hh).padStart(2, "0")}${String(mm).padStart(2, "0")}`;
      const id = `auto_${key}_${hhmm}`;

      try {
        await db
          .collection("tournaments")
          .doc(id)
          .create({
            name: pickChicName(now, i),
            status: "scheduled",
            start_at: Timestamp.fromMillis(start.getTime()),
            end_at: Timestamp.fromMillis(endMs),
            duration_min: AUTO_DURATION_MIN,
            pack_ids: [],
            pack_id: null,
            participant_count: 0,
            points_win: 3,
            points_draw: 1,
            streak_min: 2,
            streak_mult: 2,
            min_participants: 2,
            max_participants: 200,
            rewards: AUTO_REWARDS,
            finalized: false,
            created_by: "auto_scheduler",
            auto: true,
            created_at: FieldValue.serverTimestamp(),
          });
        created++;
      } catch (err) {
        // ALREADY_EXISTS (re-run) ou autre : on log en debug et on continue.
        const code = (err as { code?: number | string }).code;
        if (code === 6 || code === "already-exists") continue;
        logger.error("scheduleDailyTournaments: create échoué", { id, err });
      }
    }

    logger.info(
      `scheduleDailyTournaments: ${created} tournoi(s) créé(s) pour ${key} ` +
        `(${slots.length} créneau(x)).`
    );
  }
);
