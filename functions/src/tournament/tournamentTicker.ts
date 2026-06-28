/**
 * tournamentTicker — CF planifiée (toutes les minutes) qui pilote le cycle de
 * vie des tournois :
 *   - `scheduled → live`  quand `start_at <= now`
 *   - `live → finished`   quand `end_at <= now`, avec FINALISATION :
 *       classement figé, récompenses (cauris + badges) distribuées.
 *
 * Idempotence de la finalisation : transaction sur le flag `finalized` du doc
 * tournoi (premier passage gagne). Pattern aligné sur `prunePresence`.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import {
  getFirestore,
  FieldValue,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";

import {
  participantsRef,
  creditTournamentReward,
  awardTournamentBadge,
  toMillis,
} from "./helpers";
import {
  rankParticipants,
  rewardForRank,
  type ParticipantScore,
  type RewardTier,
} from "./scoring";

export const tournamentTicker = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const db = getFirestore();
    const now = Date.now();

    // --- Activation : scheduled → live ---
    try {
      const scheduledSnap = await db
        .collection("tournaments")
        .where("status", "==", "scheduled")
        .get();
      for (const doc of scheduledSnap.docs) {
        if (toMillis(doc.data()["start_at"]) <= now) {
          await doc.ref.update({ status: "live" });
          logger.info("tournamentTicker: activé", { tid: doc.id });
        }
      }
    } catch (err) {
      logger.error("tournamentTicker: activation échouée", err);
    }

    // --- Finalisation : live → finished ---
    try {
      const liveSnap = await db
        .collection("tournaments")
        .where("status", "==", "live")
        .get();
      for (const doc of liveSnap.docs) {
        if (toMillis(doc.data()["end_at"]) <= now) {
          await finalizeTournament(doc);
        }
      }
    } catch (err) {
      logger.error("tournamentTicker: finalisation échouée", err);
    }
  }
);

async function finalizeTournament(
  tournamentDoc: QueryDocumentSnapshot
): Promise<void> {
  const db = getFirestore();
  const tid = tournamentDoc.id;

  // Verrou d'idempotence : on ne finalise qu'une fois.
  const locked = await db.runTransaction(async (tx) => {
    const snap = await tx.get(tournamentDoc.ref);
    const d = snap.data();
    if (!d || d["finalized"] === true || d["status"] === "finished") {
      return false;
    }
    tx.update(tournamentDoc.ref, {
      status: "finished",
      finalized: true,
      finalized_at: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!locked) return;

  const data = tournamentDoc.data();
  const tournamentName = (data["name"] as string) ?? "Tournoi";
  const minParticipants = (data["min_participants"] as number) ?? 2;
  const tiers = (data["rewards"] as RewardTier[]) ?? [];

  // Lecture et classement des participants.
  const partsSnap = await participantsRef(tid).get();
  const scores: ParticipantScore[] = partsSnap.docs.map((p) => {
    const pd = p.data();
    return {
      uid: p.id,
      points: (pd["points"] as number) ?? 0,
      wins: (pd["wins"] as number) ?? 0,
      last_match_at: (pd["last_match_at"] as number) ?? 0,
    };
  });
  const ranked = rankParticipants(scores);
  const eligible = ranked.length >= minParticipants;

  logger.info("tournamentTicker: finalisation", {
    tid,
    participants: ranked.length,
    eligible,
  });

  // Pose rang + récompenses sur chaque participant, crédite cauris + badge.
  for (const p of ranked) {
    const reward = eligible
      ? rewardForRank(p.rank, tiers)
      : { cauris: 0, badge_id: null };

    await participantsRef(tid)
      .doc(p.uid)
      .set(
        {
          rank: p.rank,
          reward_cauris: reward.cauris,
          reward_badge: reward.badge_id,
        },
        { merge: true }
      );

    if (reward.cauris > 0) {
      await creditTournamentReward(p.uid, reward.cauris, tid, p.rank);
    }
    if (reward.badge_id) {
      await awardTournamentBadge(
        p.uid,
        tid,
        reward.badge_id,
        p.rank,
        tournamentName
      );
    }
  }

  // Nettoyage du pool RTDB résiduel du tournoi (entrées waiting/actives).
  try {
    const { getDatabase } = await import("firebase-admin/database");
    await getDatabase().ref(`arena/${tid}`).remove();
  } catch (err) {
    logger.warn("tournamentTicker: nettoyage arena échoué", { tid, err });
  }
}
