/**
 * joinTournament — inscription d'un joueur à un tournoi (callable v2).
 *
 * Autorisé tant que le tournoi est `scheduled` ou `live` et que la fenêtre n'est
 * pas close (`now < end_at`). Crée `tournaments/{tid}/participants/{uid}` et
 * incrémente `participant_count` de façon atomique. Idempotent : un 2e appel ne
 * recrée pas le participant ni ne re-compte.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAuth } from "../utils/auth";
import { tournamentRef, participantRef, toMillis } from "./helpers";

const Input = z.object({ tournament_id: z.string().min(1).max(128) });

export const joinTournament = onCall(
  { region: "europe-west1", enforceAppCheck: true },
  async (req) => {
    const uid = requireAuth(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const tid = parsed.data.tournament_id;

    const db = getFirestore();
    // Profil lu hors transaction (pas de write concurrent dessus ici).
    const profileSnap = await db.collection("profiles").doc(uid).get();
    const profile = profileSnap.data() ?? {};
    const displayName =
      (profile["display_name"] as string | undefined) ?? "Grimpeur anonyme";
    const avatarId = (profile["avatar_id"] as string | undefined) ?? null;

    const tRef = tournamentRef(tid);
    const pRef = participantRef(tid, uid);
    const now = Date.now();

    const result = await db.runTransaction(async (tx) => {
      const tSnap = await tx.get(tRef);
      if (!tSnap.exists) {
        throw new HttpsError("not-found", "Tournoi introuvable.");
      }
      const t = tSnap.data()!;
      const status = t["status"] as string;
      if (status !== "scheduled" && status !== "live") {
        throw new HttpsError(
          "failed-precondition",
          `Inscriptions fermées (statut "${status}").`
        );
      }
      if (toMillis(t["end_at"]) <= now) {
        throw new HttpsError(
          "failed-precondition",
          "Le tournoi est terminé."
        );
      }

      const pSnap = await tx.get(pRef);
      if (pSnap.exists) {
        // Déjà inscrit → idempotent, pas de re-comptage ni de check plafond.
        return { joined: true, already: true };
      }

      // Plafond d'inscrits (défaut 200). Ne s'applique qu'aux nouveaux.
      const count = (t["participant_count"] as number) ?? 0;
      const max = (t["max_participants"] as number) ?? 200;
      if (count >= max) {
        throw new HttpsError("resource-exhausted", "Tournoi complet.");
      }

      tx.set(pRef, {
        uid,
        display_name: displayName,
        avatar_id: avatarId,
        points: 0,
        matches_played: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        current_streak: 0,
        last_match_at: 0,
        joined_at: FieldValue.serverTimestamp(),
      });
      tx.update(tRef, { participant_count: FieldValue.increment(1) });
      return { joined: true, already: false };
    });

    return result;
  }
);
