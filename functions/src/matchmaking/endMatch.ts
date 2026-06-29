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
import { calculateElo, calculateDrawElo, ELO_INITIAL } from "./elo";
import { settleTournamentMatch } from "../tournament/settleTournamentMatch";

interface EndMatchData {
  matchId: string;
  /**
   * Optionnel : le gagnant déclaré par le client. Le serveur reste
   * autoritaire (lit `matchData.winner`) ; ce champ ne sert que de
   * cross-check. Absent/vide => match nul (E3).
   */
  winner_uid?: string;
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
      tournament_id?: string;
      created_at?: number;
    };

    // Anti-cheat : vérifier que la phase est bien "finished".
    if (matchData.phase !== "finished") {
      throw new HttpsError(
        "failed-precondition",
        "Le match n'est pas encore terminé."
      );
    }

    // Le serveur est AUTORITAIRE sur le gagnant : on lit `matchData.winner`
    // (posé par submitRoundWin/Timeout, verrouillé côté client par les règles
    // RTDB). `winner` absent/vide => match NUL (E3).
    const recordedWinner =
      typeof matchData.winner === "string" && matchData.winner.length > 0
        ? matchData.winner
        : null;
    const isDraw = recordedWinner === null;

    // Cross-check optionnel (défense en profondeur) : si le client déclare un
    // gagnant, il doit correspondre à l'enregistré.
    if (!isDraw && winner_uid && winner_uid !== recordedWinner) {
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
    if (!isDraw && !players.includes(recordedWinner)) {
      throw new HttpsError(
        "failed-precondition",
        "Le gagnant enregistré n'est pas un participant."
      );
    }

    // --- Match de tournoi (arène) : points d'arène, JAMAIS d'ELO ---
    // Court-circuite AVANT la logique ELO. Le règlement (verrou `settled` +
    // crédit) est mutualisé dans settleTournamentMatch, partagé avec
    // forfeitMatch / resolveStaleMatches → scoring serveur-autoritaire et
    // idempotent (un seul crédit quel que soit le chemin de finalisation).
    if (matchData.tournament_id) {
      await settleTournamentMatch(matchId);
      return { new_elo: ELO_INITIAL, delta: 0 };
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

    // --- Match NUL (E3) : ELO de nul appliqué aux deux joueurs ---
    if (isDraw) {
      const [uidA, uidB] = players;
      const [snapA, snapB] = await Promise.all([
        db.collection("profiles").doc(uidA).get(),
        db.collection("profiles").doc(uidB).get(),
      ]);
      const eloA =
        (snapA.data()?.["elo"] as number | undefined) ?? ELO_INITIAL;
      const eloB =
        (snapB.data()?.["elo"] as number | undefined) ?? ELO_INITIAL;
      const { newEloA, newEloB, deltaA, deltaB } = calculateDrawElo(
        eloA,
        eloB
      );
      const nowTs = FieldValue.serverTimestamp();
      const batch = db.batch();
      const refA = db.collection("profiles").doc(uidA);
      const refB = db.collection("profiles").doc(uidB);

      batch.set(
        refA,
        {
          elo: newEloA,
          draws: FieldValue.increment(1),
          totalDuels: FieldValue.increment(1),
          lastDuelAt: nowTs,
        },
        { merge: true }
      );
      batch.set(
        refB,
        {
          elo: newEloB,
          draws: FieldValue.increment(1),
          totalDuels: FieldValue.increment(1),
          lastDuelAt: nowTs,
        },
        { merge: true }
      );
      if (newEloA > ((snapA.data()?.["peakElo"] as number) ?? 0)) {
        batch.update(refA, { peakElo: newEloA });
      }
      if (newEloB > ((snapB.data()?.["peakElo"] as number) ?? 0)) {
        batch.update(refB, { peakElo: newEloB });
      }

      batch.set(db.collection("matches_history").doc(matchId), {
        players,
        winner: null,
        is_draw: true,
        elo_changes: { [uidA]: deltaA, [uidB]: deltaB },
        elo_before: { [uidA]: eloA, [uidB]: eloB },
        elo_after: { [uidA]: newEloA, [uidB]: newEloB },
        finished_at: nowTs,
      });

      const nameA =
        (snapA.data()?.["display_name"] as string | undefined) ??
        "Grimpeur anonyme";
      const nameB =
        (snapB.data()?.["display_name"] as string | undefined) ??
        "Grimpeur anonyme";
      batch.set(
        db.collection("profiles").doc(uidA).collection("duel_history").doc(matchId),
        {
          opponent_uid: uidB,
          opponent_name: nameB,
          did_win: false,
          is_draw: true,
          elo_delta: deltaA,
          finished_at: nowTs,
        }
      );
      batch.set(
        db.collection("profiles").doc(uidB).collection("duel_history").doc(matchId),
        {
          opponent_uid: uidA,
          opponent_name: nameA,
          did_win: false,
          is_draw: true,
          elo_delta: deltaB,
          finished_at: nowTs,
        }
      );

      try {
        await batch.commit();
      } catch (err) {
        await settledRef.set(null);
        throw err;
      }

      const callerIsA = callerUid === uidA;
      return {
        new_elo: callerIsA ? newEloA : newEloB,
        delta: callerIsA ? deltaA : deltaB,
      };
    }

    // --- Victoire / défaite ---
    const winnerUid = recordedWinner!;
    const loserUid = players.find((p) => p !== winnerUid)!;

    // --- Lire les ELOs depuis Firestore ---
    const [winnerSnap, loserSnap] = await Promise.all([
      db.collection("profiles").doc(winnerUid).get(),
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

    const winnerRef = db.collection("profiles").doc(winnerUid);
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
      winner: winnerUid,
      elo_changes: {
        [winnerUid]: winnerDelta,
        [loserUid]: loserDelta,
      },
      elo_before: {
        [winnerUid]: winnerElo,
        [loserUid]: loserElo,
      },
      elo_after: {
        [winnerUid]: newWinnerElo,
        [loserUid]: newLoserElo,
      },
      finished_at: now,
    });

    // --- Écrire les entrées duel_history pour les 2 joueurs ---
    // Chaque joueur a une subcollection profiles/{uid}/duel_history/{matchId}
    // contenant la vue de son duel : opponent, result, delta, timestamp.
    const winnerHistoryRef = db
      .collection("profiles")
      .doc(winnerUid)
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
      opponent_uid: winnerUid,
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
    const callerIsWinner = callerUid === winnerUid;
    return {
      new_elo: callerIsWinner ? newWinnerElo : newLoserElo,
      delta: callerIsWinner ? winnerDelta : loserDelta,
    };
  }
);
