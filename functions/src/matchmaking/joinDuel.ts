/**
 * joinDuel — rejoindre un duel existant (callable v2).
 *
 * Anti-cheat (C1) : remplace les writes client directs de `phase=countdown`
 * (duel_repository.joinDuel / joinOpen). Sous les règles RTDB durcies, un
 * nouveau joueur n'est pas encore « participant » au moment où il voudrait
 * écrire `phase`, donc le write serait refusé. Le serveur (Admin SDK) ajoute
 * le joueur à `players` et bascule la phase.
 *
 * Couvre les deux flux d'entrée du 2e joueur :
 *   - QR ami (createLocalDuel)        → `secret` fourni, vérifié.
 *   - Deep link / rematch accepté     → pas de secret ; si le match porte un
 *     `target_uid`, seul ce destinataire peut rejoindre.
 *
 * Le flux matchmaking ELO (requestMatch) n'utilise PAS cette CF : les deux
 * joueurs y sont déjà ajoutés à la création.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import { requireDuelProtocol } from "./protocol";

interface JoinDuelData {
  matchId: string;
  /** Optionnel : requis seulement pour le flux QR (createLocalDuel). */
  secret?: string;
}

interface JoinDuelResult {
  ok: true;
  matchData: Record<string, unknown>;
}

export const joinDuel = onCall<JoinDuelData, Promise<JoinDuelResult>>(
  { region: "europe-west1", enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request.auth);
    requireDuelProtocol(request.data);
    const { matchId, secret } = request.data;

    if (!matchId || typeof matchId !== "string") {
      throw new HttpsError("invalid-argument", "matchId requis.");
    }

    const rtdb = getDatabase();
    const matchRef = rtdb.ref(`matches/${matchId}`);
    const snap = await matchRef.get();
    if (!snap.exists()) {
      throw new HttpsError("not-found", "duel_not_found");
    }

    const data = snap.val() as {
      secret?: string;
      created_by?: string;
      target_uid?: string;
      phase?: string;
      players?: Record<string, unknown>;
    };

    const players = data.players ?? {};

    // Créateur ou déjà présent : no-op, on renvoie l'état courant.
    if (data.created_by === uid || players[uid]) {
      return { ok: true, matchData: snap.val() as Record<string, unknown> };
    }

    // Vérif secret uniquement si fourni (flux QR).
    if (secret && secret.length > 0 && data.secret !== secret) {
      throw new HttpsError("permission-denied", "Secret invalide.");
    }

    // Défi ciblé (rematch/challenge via requestRematch) : seul le
    // destinataire peut rejoindre — le matchId seul ne suffit pas.
    if (data.target_uid && data.target_uid !== uid) {
      throw new HttpsError("permission-denied", "duel_reserved");
    }

    if (Object.keys(players).length >= 2) {
      throw new HttpsError("failed-precondition", "duel_full");
    }
    if (data.phase === "finished") {
      throw new HttpsError("failed-precondition", "duel_expired");
    }

    // --- Réclamation atomique de la place de 2e joueur (anti-course) ---
    // Le check players.length ci-dessus est lu AVANT écriture : deux uids
    // différents (même code/QR partagé à plusieurs amis) pouvaient le passer
    // tous les deux et produire un match à 3 joueurs — toute la logique aval
    // suppose exactement 2. Transaction premier-arrivé sur joiner_uid ; un
    // retry réseau du même joueur (claim déjà à son uid) continue.
    const claimRef = rtdb.ref(`matches/${matchId}/joiner_uid`);
    const claim = await claimRef.transaction((cur) => (cur ? undefined : uid));
    if (claim.snapshot.val() !== uid) {
      throw new HttpsError("failed-precondition", "duel_full");
    }

    await matchRef.update({
      [`players/${uid}`]: {
        progress: 0,
        found: false,
        rounds_won: 0,
        total_time_ms: 0,
        rounds: {},
      },
      phase: "countdown",
      phase_started_at: Date.now(),
    });

    const updated = await matchRef.get();
    const updatedData = updated.val() as {
      rounds?: unknown;
      created_by?: string;
    } | null;
    // Si le créateur a supprimé le match pendant le join (fenêtre lecture →
    // écriture, autorisée par les rules tant que phase == waiting), l'update
    // ci-dessus a RECRÉÉ un nœud tronqué sans rounds : grille vide injouable.
    // On nettoie et on signale l'expiration.
    if (updatedData?.rounds == null || updatedData.created_by == null) {
      await matchRef.remove();
      throw new HttpsError("failed-precondition", "duel_expired");
    }
    return { ok: true, matchData: updated.val() as Record<string, unknown> };
  }
);
