/**
 * createTournament / cancelTournament — CFs admin (callable v2).
 *
 * Création réservée au rôle `admin` (claim), appelée depuis la console admin.
 * Le tournoi naît en `scheduled` ; le `tournamentTicker` le passera `live` à
 * `start_at` puis `finished` à `end_at`.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import { tournamentRef } from "./helpers";
import { DEFAULT_SCORING } from "./scoring";

const OPTS = { region: "europe-west1" as const, enforceAppCheck: false, cors: true };

const RewardTierSchema = z.object({
  rank_min: z.number().int().positive(),
  rank_max: z.number().int().positive(),
  cauris: z.number().int().min(0).max(5000).optional(),
  badge_id: z.string().max(64).nullable().optional(),
});

const CreateInput = z.object({
  name: z.string().trim().min(1).max(80),
  /** Début du tournoi en millisecondes epoch (doit être dans le futur). */
  start_at: z.number().int().positive(),
  /** Durée de la fenêtre de jeu en minutes. */
  duration_min: z.number().int().min(1).max(1440),
  pack_id: z.string().max(64).nullable().optional(),
  points_win: z.number().int().min(0).max(100).optional(),
  points_draw: z.number().int().min(0).max(100).optional(),
  streak_min: z.number().int().min(1).max(50).optional(),
  streak_mult: z.number().int().min(1).max(10).optional(),
  min_participants: z.number().int().min(1).max(10_000).optional(),
  /** Plafond d'inscrits. Défaut 200 (limite confortable sur l'archi actuelle :
   *  compteur mono-doc + lecture full pool). Au-delà de 500, prévoir du
   *  sharding. Lancer plusieurs tournois en parallèle pour scaler le total. */
  max_participants: z.number().int().min(2).max(10_000).optional(),
  rewards: z.array(RewardTierSchema).max(50).optional(),
});

export const createTournament = onCall(OPTS, async (req) => {
  const adminUid = requireAdmin(req.auth);

  const parsed = CreateInput.safeParse(req.data);
  if (!parsed.success) {
    throw new HttpsError("invalid-argument", parsed.error.message);
  }
  const d = parsed.data;

  const now = Date.now();
  if (d.start_at <= now) {
    throw new HttpsError(
      "invalid-argument",
      "start_at doit être dans le futur."
    );
  }

  const endAtMs = d.start_at + d.duration_min * 60_000;
  const db = getFirestore();
  const ref = tournamentRef(db.collection("tournaments").doc().id);

  await ref.set({
    name: d.name,
    status: "scheduled",
    start_at: Timestamp.fromMillis(d.start_at),
    end_at: Timestamp.fromMillis(endAtMs),
    duration_min: d.duration_min,
    pack_id: d.pack_id ?? null,
    participant_count: 0,
    points_win: d.points_win ?? DEFAULT_SCORING.points_win,
    points_draw: d.points_draw ?? DEFAULT_SCORING.points_draw,
    streak_min: d.streak_min ?? DEFAULT_SCORING.streak_min,
    streak_mult: d.streak_mult ?? DEFAULT_SCORING.streak_mult,
    min_participants: d.min_participants ?? 2,
    max_participants: d.max_participants ?? 200,
    rewards: d.rewards ?? [],
    finalized: false,
    created_by: adminUid,
    created_at: FieldValue.serverTimestamp(),
  });

  return { tournament_id: ref.id };
});

const CancelInput = z.object({ tournament_id: z.string().min(1).max(128) });

export const cancelTournament = onCall(OPTS, async (req) => {
  requireAdmin(req.auth);

  const parsed = CancelInput.safeParse(req.data);
  if (!parsed.success) {
    throw new HttpsError("invalid-argument", parsed.error.message);
  }
  const ref = tournamentRef(parsed.data.tournament_id);

  await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Tournoi introuvable.");
    }
    const status = snap.data()?.status as string;
    // On n'annule que les tournois pas encore démarrés, pour ne pas perturber
    // une arène en cours et son scoring.
    if (status !== "scheduled") {
      throw new HttpsError(
        "failed-precondition",
        `Impossible d'annuler un tournoi au statut "${status}".`
      );
    }
    tx.update(ref, { status: "cancelled" });
  });

  return { ok: true };
});
