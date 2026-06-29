/**
 * settleTournamentMatch — règle les points d'arène d'un match de tournoi
 * terminé, depuis N'IMPORTE QUEL chemin de finalisation (endMatch côté client,
 * forfeitMatch, resolveStaleMatches côté serveur).
 *
 * Pourquoi : avant, les points n'étaient crédités que par `endMatch` (déclenché
 * par le client). Un abandon (`forfeitMatch`) ou une résolution AWOL
 * (`resolveStaleMatches`) posait bien le `winner` mais ne créditait jamais →
 * un joueur pouvait force-quitter pour priver son adversaire de points, et un
 * match abandonné des deux côtés perdait ses points. Ce helper rend le scoring
 * 100% serveur-autoritaire.
 *
 * Idempotent : verrou RTDB `matches/{id}/settled` PARTAGÉ avec endMatch — un
 * seul award quels que soient les appels concurrents / retries. No-op si le
 * match n'est pas un match de tournoi ou n'est pas encore `finished`.
 */

import { getDatabase } from "firebase-admin/database";
import { logger } from "firebase-functions/v2";

import { awardTournamentPoints } from "./awardTournamentPoints";

export async function settleTournamentMatch(matchId: string): Promise<void> {
  const rtdb = getDatabase();
  const snap = await rtdb.ref(`matches/${matchId}`).get();
  if (!snap.exists()) return;

  const m = snap.val() as {
    phase?: string;
    winner?: string;
    players?: Record<string, unknown>;
    tournament_id?: string;
    created_at?: number;
  };

  if (!m.tournament_id) return; // pas un match de tournoi
  if (m.phase !== "finished") return; // pas encore finalisé

  const players = Object.keys(m.players ?? {});
  if (players.length < 2) return;

  // Verrou idempotent partagé avec endMatch : premier appelant gagne.
  const settledRef = rtdb.ref(`matches/${matchId}/settled`);
  const txn = await settledRef.transaction((cur) =>
    cur === true ? undefined : true
  );
  if (!txn.committed) return; // déjà réglé

  try {
    await awardTournamentPoints({
      tournamentId: m.tournament_id,
      matchId,
      players,
      winnerUid:
        typeof m.winner === "string" && m.winner.length > 0 ? m.winner : null,
      matchCreatedAt: m.created_at ?? 0,
    });
  } catch (err) {
    // Échec après pose du verrou → on le libère pour permettre un retry propre.
    await settledRef.set(null);
    logger.error("settleTournamentMatch: award échoué", { matchId, err });
    throw err;
  }
}
