/**
 * purgeMatches — Cloud Function planifiée (v2 scheduler).
 *
 * Hygiène RTDB : supprime les matchs qui n'ont plus d'utilité et leurs
 * réponses serveur-only associées (/match_answers).
 *
 *   - `finished` : le résultat est déjà persisté côté Firestore
 *     (matches_history + profiles via endMatch) ; le nœud RTDB ne sert plus
 *     une fois les deux clients passés à l'écran résultat. On garde une marge
 *     (RETAIN_MS) bien supérieure au temps d'appel d'endMatch.
 *   - `waiting` : duel QR créé mais jamais rejoint (deleteIfOwner non appelé,
 *     ou créateur parti). Au-delà de RETAIN_MS, le QR est de toute façon
 *     obsolète.
 *
 * Sans ce filet, /matches et /match_answers grossissent indéfiniment (chaque
 * duel + chaque transition abandonnée laissent un nœud). Cf. resolveStaleMatches
 * qui finalise d'abord les matchs bloqués (active/countdown/roundEnd) → ils
 * deviennent `finished` → purgés ici.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { getDatabase } from "firebase-admin/database";

const RETAIN_MS = 60 * 60 * 1000; // 1 h — très au-delà du temps d'appel endMatch

interface MatchMeta {
  phase_started_at?: number;
  created_at?: number;
}

export const purgeMatches = onSchedule(
  {
    schedule: "every 15 minutes",
    region: "europe-west1",
    timeZone: "UTC",
  },
  async () => {
    const rtdb = getDatabase();
    const now = Date.now();
    const updates: Record<string, unknown> = {};
    let purged = 0;

    for (const phase of ["finished", "waiting"] as const) {
      const snap = await rtdb
        .ref("matches")
        .orderByChild("phase")
        .equalTo(phase)
        .get();
      if (!snap.exists()) continue;

      const matches = snap.val() as Record<string, MatchMeta>;
      for (const [matchId, data] of Object.entries(matches)) {
        const ts = data.phase_started_at ?? data.created_at ?? now;
        if (now - ts < RETAIN_MS) continue;
        updates[`matches/${matchId}`] = null;
        updates[`match_answers/${matchId}`] = null;
        purged++;
      }
    }

    if (purged > 0) {
      await rtdb.ref().update(updates);
      logger.info("purgeMatches", { purged });
    }
  }
);
