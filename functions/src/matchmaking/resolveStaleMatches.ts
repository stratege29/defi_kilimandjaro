/**
 * resolveStaleMatches — Cloud Function planifiée (v2 scheduler).
 *
 * Filet de sécurité : finalise les duels restés en phase `active` bien au-delà
 * de la durée d'un round. Couvre le cas où un (ou les deux) joueur(s) ne
 * signale(nt) jamais leur timeout — adversaire déconnecté/app tuée — laissant
 * le match bloqué sans transition vers l'écran résultat.
 *
 * Indépendant du client : débloque même les anciens builds (qui ne re-signalent
 * pas le timeout) et le cas où le joueur présent se déconnecte après son
 * timeout. Latence : jusqu'à ~1 min (intervalle du scheduler).
 *
 * Un round dure 30s. Le flux normal quitte `active` au plus tard ~40s (grâce
 * serveur + retries client). Un match encore `active` après STALE_ACTIVE_MS est
 * donc anormal (bloqué) → on le résout : round intermédiaire → roundEnd ;
 * dernier round → finished avec gagnant calculé sur rounds_won (+ tiebreak temps).
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getDatabase } from "firebase-admin/database";

const STALE_ACTIVE_MS = 55000; // 30s round + grâce + retries + marge

interface RoundResult {
  progress?: number;
  found?: boolean;
  finished_at?: number;
  time_taken_ms?: number;
}

interface PlayerState {
  rounds_won?: number;
  total_time_ms?: number;
  rounds?: Record<string, RoundResult> | RoundResult[];
}

interface MatchData {
  phase: string;
  current_round: number;
  total_rounds?: number;
  phase_started_at?: number;
  created_at?: number;
  players?: Record<string, PlayerState>;
}

function getRoundResult(
  player: PlayerState | undefined,
  round: number
): RoundResult | undefined {
  if (!player?.rounds) return undefined;
  const rounds = player.rounds;
  if (Array.isArray(rounds)) return rounds[round];
  return rounds[String(round)];
}

function computeWinner(
  players: Record<string, PlayerState>,
  uids: string[]
): string | null {
  if (uids.length < 2) return uids[0] ?? null;
  const [a, b] = uids;
  const aw = players[a]?.rounds_won ?? 0;
  const bw = players[b]?.rounds_won ?? 0;
  if (aw > bw) return a;
  if (bw > aw) return b;
  const at = players[a]?.total_time_ms ?? 0;
  const bt = players[b]?.total_time_ms ?? 0;
  if (at > 0 && bt > 0) return at <= bt ? a : b;
  if (at > 0) return a;
  if (bt > 0) return b;
  return null;
}

export const resolveStaleMatches = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const rtdb = getDatabase();
    const now = Date.now();

    const snap = await rtdb
      .ref("matches")
      .orderByChild("phase")
      .equalTo("active")
      .get();
    if (!snap.exists()) {
      return;
    }

    const matches = snap.val() as Record<string, MatchData>;
    let resolved = 0;

    for (const [matchId, data] of Object.entries(matches)) {
      const startedAt = data.phase_started_at ?? data.created_at ?? now;
      if (now - startedAt < STALE_ACTIVE_MS) continue; // pas encore bloqué

      const round = data.current_round ?? 0;
      const totalRounds = data.total_rounds ?? 3;
      const isLastRound = round >= totalRounds - 1;
      const players = data.players ?? {};
      const uids = Object.keys(players);

      const updates: Record<string, unknown> = {};

      // Marque en timeout tout joueur sans résultat pour le round courant.
      for (const uid of uids) {
        const rr = getRoundResult(players[uid], round);
        const acted = rr?.found === true || rr?.time_taken_ms != null;
        if (!acted) {
          updates[`players/${uid}/rounds/${round}`] = {
            progress: 0,
            found: false,
            time_taken_ms: 30000,
            awol: true,
          };
        }
      }

      updates.phase = isLastRound ? "finished" : "roundEnd";
      updates.phase_started_at = now;
      if (isLastRound) {
        updates.winner = computeWinner(players, uids);
      }

      await rtdb.ref(`matches/${matchId}`).update(updates);
      resolved++;
      logger.warn("resolveStaleMatches: match bloqué résolu", {
        matchId,
        round,
        isLastRound,
        ageMs: now - startedAt,
      });
    }

    if (resolved > 0) {
      logger.info("resolveStaleMatches", { resolved });
    }
  }
);
