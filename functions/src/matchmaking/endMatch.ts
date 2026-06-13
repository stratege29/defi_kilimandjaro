/**
 * endMatch — Cloud Function callable (v2).
 *
 * Flux :
 * 1. Vérifie l'auth.
 * 2. Lit /matches/{matchId} pour vérifier :
 *    - Les 2 joueurs sont présents.
 *    - La phase est "finished".
 *    - Le winner déclaré par le client correspond au winner enregistré en DB (anti-cheat).
 * 3. Lit les ELOs des 2 joueurs depuis Firestore.
 * 4. Calcule les nouveaux ELOs avec K=32.
 * 5. Met à jour profiles/{uid} pour les 2 joueurs via Admin SDK.
 * 6. Écrit matches_history/{matchId} dans Firestore.
 * 7. Retourne {new_elo, delta} au client appelant.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import { calculateElo, ELO_INITIAL } from "./elo";

interface EndMatchData {
  matchId: string;
  winner_uid: string;
}

interface EndMatchResult {
  new_elo: number;
  delta: number;
}

export const endMatch = onCall<EndMatchData, Promise<EndMatchResult>>(
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const callerUid = requireAuth(request.auth);
    const { matchId, winner_uid } = request.data;

    if (!matchId || typeof matchId !== "string") {
      throw new HttpsError("invalid-argument", "matchId requis.");
    }
    if (!winner_uid || typeof winner_uid !== "string") {
      throw new HttpsError("invalid-argument", "winner_uid requis.");
    }

    const rtdb = getDatabase();
    const db = getFirestore();

    // --- Lire le match depuis Realtime DB ---
    const matchSnap = await rtdb.ref(`matches/${matchId}`).get();
    if (!matchSnap.exists()) {
      throw new HttpsError("not-found", `Match ${matchId} introuvable.`);
    }

    const matchData = matchSnap.val() as {
      phase: string;
      winner?: string;
      players?: Record<string, unknown>;
      is_ranked?: boolean;
    };

    // Anti-cheat : vérifier que la phase est bien "finished".
    if (matchData.phase !== "finished") {
      throw new HttpsError(
        "failed-precondition",
        "Le match n'est pas encore terminé."
      );
    }

    // Anti-cheat : vérifier que le winner déclaré correspond à la DB.
    if (matchData.winner !== winner_uid) {
      throw new HttpsError(
        "permission-denied",
        "Le winner déclaré ne correspond pas au résultat enregistré."
      );
    }

    // Vérifier que le caller est un participant du match.
    const players = Object.keys(matchData.players ?? {});
    if (!players.includes(callerUid)) {
      throw new HttpsError(
        "permission-denied",
        "Tu n'es pas participant de ce match."
      );
    }
    if (players.length < 2) {
      throw new HttpsError(
        "failed-precondition",
        "Le match nécessite 2 joueurs."
      );
    }

    // Vérifier que le match est ranked.
    if (!matchData.is_ranked) {
      // Pour les duels ami (non-ranked), ne pas modifier l'ELO.
      return { new_elo: ELO_INITIAL, delta: 0 };
    }

    // --- Idempotence (C4) : verrou anti double-application de l'ELO ---
    // Les deux joueurs (et les retries reseau) appellent endMatch. Sans
    // verrou, chaque appel ré-applique wins/elo (FieldValue.increment non
    // idempotent) → inflation. Une transaction RTDB pose un flag `settled` :
    // le premier appel gagne et applique ; les suivants renvoient le resultat
    // depuis l'historique sans muter les profils.
    const settledRef = rtdb.ref(`matches/${matchId}/settled`);
    const settledTxn = await settledRef.transaction((cur) =>
      cur === true ? undefined : true
    );
    if (!settledTxn.committed) {
      const histSnap = await db
        .collection("matches_history")
        .doc(matchId)
        .get();
      const hist = histSnap.data() ?? {};
      const changes = (hist["elo_changes"] ?? {}) as Record<string, number>;
      const afters = (hist["elo_after"] ?? {}) as Record<string, number>;
      return {
        new_elo: afters[callerUid] ?? ELO_INITIAL,
        delta: changes[callerUid] ?? 0,
      };
    }

    const loserUid = players.find((p) => p !== winner_uid)!;

    // --- Lire les ELOs depuis Firestore ---
    const [winnerSnap, loserSnap] = await Promise.all([
      db.collection("profiles").doc(winner_uid).get(),
      db.collection("profiles").doc(loserUid).get(),
    ]);

    const winnerElo: number =
      (winnerSnap.data()?.["elo"] as number | undefined) ?? ELO_INITIAL;
    const loserElo: number =
      (loserSnap.data()?.["elo"] as number | undefined) ?? ELO_INITIAL;

    // --- Calcul ELO ---
    const { newWinnerElo, newLoserElo, winnerDelta, loserDelta } =
      calculateElo(winnerElo, loserElo);

    const now = FieldValue.serverTimestamp();

    // --- Mettre à jour les profils (Admin SDK — ne passe jamais par le client) ---
    const batch = db.batch();

    const winnerRef = db.collection("profiles").doc(winner_uid);
    batch.set(
      winnerRef,
      {
        elo: newWinnerElo,
        peakElo: newWinnerElo > (winnerSnap.data()?.["peakElo"] as number ?? 0)
          ? newWinnerElo
          : FieldValue.increment(0), // no-op if not a new record
        wins: FieldValue.increment(1),
        totalDuels: FieldValue.increment(1),
        lastDuelAt: now,
      },
      { merge: true }
    );

    // Separate peak update to avoid conditional in batch.
    if (newWinnerElo > ((winnerSnap.data()?.["peakElo"] as number) ?? 0)) {
      batch.update(winnerRef, { peakElo: newWinnerElo });
    }

    const loserRef = db.collection("profiles").doc(loserUid);
    batch.set(
      loserRef,
      {
        elo: newLoserElo,
        losses: FieldValue.increment(1),
        totalDuels: FieldValue.increment(1),
        lastDuelAt: now,
      },
      { merge: true }
    );

    // --- Écrire l'historique match ---
    const historyRef = db.collection("matches_history").doc(matchId);
    batch.set(historyRef, {
      players,
      winner: winner_uid,
      elo_changes: {
        [winner_uid]: winnerDelta,
        [loserUid]: loserDelta,
      },
      elo_before: {
        [winner_uid]: winnerElo,
        [loserUid]: loserElo,
      },
      elo_after: {
        [winner_uid]: newWinnerElo,
        [loserUid]: newLoserElo,
      },
      finished_at: now,
    });

    // --- Écrire les entrées duel_history pour les 2 joueurs ---
    // Chaque joueur a une subcollection profiles/{uid}/duel_history/{matchId}
    // contenant la vue de son duel : opponent, result, delta, timestamp.
    const winnerHistoryRef = db
      .collection("profiles")
      .doc(winner_uid)
      .collection("duel_history")
      .doc(matchId);
    const loserHistoryRef = db
      .collection("profiles")
      .doc(loserUid)
      .collection("duel_history")
      .doc(matchId);

    const winnerHistoryData = {
      opponent_uid: loserUid,
      opponent_name: loserSnap.data()?.["display_name"] as string | undefined ?? "Grimpeur anonyme",
      did_win: true,
      elo_delta: winnerDelta,
      finished_at: now,
    };

    const loserHistoryData = {
      opponent_uid: winner_uid,
      opponent_name: winnerSnap.data()?.["display_name"] as string | undefined ?? "Grimpeur anonyme",
      did_win: false,
      elo_delta: loserDelta,
      finished_at: now,
    };

    batch.set(winnerHistoryRef, winnerHistoryData);
    batch.set(loserHistoryRef, loserHistoryData);

    try {
      await batch.commit();
    } catch (err) {
      // Echec d'ecriture apres avoir pose le verrou : on libere `settled`
      // pour permettre un retry propre (l'ELO n'a pas ete applique).
      await settledRef.set(null);
      throw err;
    }

    // Retourner le résultat au caller.
    const callerIsWinner = callerUid === winner_uid;
    return {
      new_elo: callerIsWinner ? newWinnerElo : newLoserElo,
      delta: callerIsWinner ? winnerDelta : loserDelta,
    };
  }
);
