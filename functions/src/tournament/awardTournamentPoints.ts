/**
 * awardTournamentPoints — applique les points d'arène des 2 joueurs d'un match
 * de tournoi, dans une transaction Firestore. Appelé par `endMatch` UNIQUEMENT
 * quand le match porte un `tournament_id`.
 *
 * L'idempotence inter-appels est garantie en amont par le verrou `settled` du
 * match (cf endMatch) : awardTournamentPoints n'est exécuté qu'une fois par
 * match. On reste néanmoins défensif (lecture de l'état courant, pas de double
 * comptage d'un même match au sein de la transaction).
 *
 * Ne touche JAMAIS l'ELO. N'octroie aucun point si le match a démarré après la
 * clôture du tournoi (`created_at >= end_at`) ou si le tournoi est finalisé.
 */

import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import { tournamentRef, participantRef, toMillis } from "./helpers";
import {
  outcomeFor,
  pointsForOutcome,
  resolveScoringConfig,
} from "./scoring";

export async function awardTournamentPoints(params: {
  tournamentId: string;
  matchId: string;
  players: string[];
  /** UID du vainqueur, ou null pour un match nul. */
  winnerUid: string | null;
  /** Timestamp (ms) de création du match (fenêtre tournoi). */
  matchCreatedAt: number;
}): Promise<void> {
  const { tournamentId, matchId, players, winnerUid, matchCreatedAt } = params;
  const db = getFirestore();
  const tRef = tournamentRef(tournamentId);
  const nowMs = Date.now();

  await db.runTransaction(async (tx) => {
    const tSnap = await tx.get(tRef);
    if (!tSnap.exists) {
      logger.warn("awardTournamentPoints: tournoi introuvable", {
        tournamentId,
        matchId,
      });
      return;
    }
    const t = tSnap.data()!;

    // Tournoi déjà clôturé/finalisé → les points n'influenceraient plus le
    // classement, on s'abstient.
    if (t["finalized"] === true || t["status"] === "finished") {
      logger.info("awardTournamentPoints: tournoi finalisé, skip", {
        tournamentId,
        matchId,
      });
      return;
    }

    // Hors fenêtre : le match a été créé après la fin → 0 point (mais le match
    // reste jouable/terminable, on ne le crédite simplement pas).
    const endMs = toMillis(t["end_at"]);
    if (endMs > 0 && matchCreatedAt >= endMs) {
      logger.info("awardTournamentPoints: match hors fenêtre, 0 point", {
        tournamentId,
        matchId,
      });
      return;
    }

    const cfg = resolveScoringConfig({
      points_win: t["points_win"],
      points_draw: t["points_draw"],
      streak_min: t["streak_min"],
      streak_mult: t["streak_mult"],
    });

    // Lecture des 2 participants AVANT toute écriture (contrainte transaction).
    const pRefs = players.map((uid) => participantRef(tournamentId, uid));
    const pSnaps = await Promise.all(pRefs.map((r) => tx.get(r)));

    players.forEach((uid, i) => {
      const ref = pRefs[i];
      const snap = pSnaps[i];
      const prior = snap.data() ?? {};
      const priorStreak = (prior["current_streak"] as number) ?? 0;

      const outcome = outcomeFor(uid, winnerUid);
      const { points, newStreak } = pointsForOutcome(outcome, priorStreak, cfg);

      const update: Record<string, unknown> = {
        points: FieldValue.increment(points),
        matches_played: FieldValue.increment(1),
        current_streak: newStreak,
        last_match_at: nowMs,
      };
      if (outcome === "win") update["wins"] = FieldValue.increment(1);
      else if (outcome === "draw") update["draws"] = FieldValue.increment(1);
      else update["losses"] = FieldValue.increment(1);

      if (snap.exists) {
        tx.update(ref, update);
      } else {
        // Garde-fou : participant inscrit absent (ne devrait pas arriver via
        // l'arène). On crée une fiche minimale pour ne pas perdre le score.
        tx.set(
          ref,
          {
            uid,
            display_name: "Grimpeur anonyme",
            avatar_id: null,
            points,
            matches_played: 1,
            wins: outcome === "win" ? 1 : 0,
            draws: outcome === "draw" ? 1 : 0,
            losses: outcome === "loss" ? 1 : 0,
            current_streak: newStreak,
            last_match_at: nowMs,
            joined_at: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    });
  });
}
