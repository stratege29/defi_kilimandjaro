/**
 * helpers — refs Firestore/RTDB et utilitaires partagés du module tournoi.
 */

import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import {
  walletDocRef,
  auditCollectionRef,
  CAURIS_MAX_BALANCE,
  type Wallet,
} from "../wallet/walletHelpers";

/** Statuts du cycle de vie d'un tournoi. */
export type TournamentStatus =
  | "scheduled"
  | "live"
  | "finished"
  | "cancelled";

export function tournamentRef(tid: string) {
  return getFirestore().collection("tournaments").doc(tid);
}

export function participantsRef(tid: string) {
  return tournamentRef(tid).collection("participants");
}

export function participantRef(tid: string, uid: string) {
  return participantsRef(tid).doc(uid);
}

/** Path RTDB du pool de matchmaking d'un tournoi (miroir de `/lobby`). */
export function arenaPoolPath(tid: string, uid: string): string {
  return `arena/${tid}/pool/${uid}`;
}

/** Path RTDB du pointeur « match actif » d'un joueur dans un tournoi. */
export function arenaActivePath(tid: string, uid: string): string {
  return `arena/${tid}/active/${uid}`;
}

/** Convertit un Timestamp Firestore (ou un nombre ms) en millisecondes. */
export function toMillis(v: unknown): number {
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === "number" && Number.isFinite(v)) return v;
  // Objets sérialisés {_seconds,_nanoseconds} (rare, défensif).
  if (v && typeof v === "object" && "_seconds" in (v as object)) {
    const s = (v as { _seconds?: number })._seconds ?? 0;
    return s * 1000;
  }
  return 0;
}

/**
 * Crédite des cauris de récompense de tournoi au wallet d'un joueur.
 *
 * Réutilise le schéma wallet (`users/{uid}/inventory/wallet`) et le pattern
 * transactionnel idempotent de `creditCauris.ts`. La clé d'idempotence est
 * dérivée du tournoi (`tournament_{tid}`) : un re-run du finalize ne re-crédite
 * jamais. Si le wallet n'existe pas (joueur n'ayant jamais sync), on ignore le
 * crédit (best-effort) plutôt que d'échouer toute la finalisation.
 *
 * @returns true si crédité, false si ignoré (wallet absent / déjà crédité).
 */
export async function creditTournamentReward(
  uid: string,
  amount: number,
  tid: string,
  rank: number
): Promise<boolean> {
  if (amount <= 0) return false;
  const db = getFirestore();
  const walletRef = walletDocRef(uid);
  const auditRef = auditCollectionRef(uid).doc(`tournament_${tid}`);

  try {
    return await db.runTransaction(async (tx) => {
      const auditSnap = await tx.get(auditRef);
      if (auditSnap.exists) return false; // déjà crédité (idempotence)

      const walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) {
        logger.warn("creditTournamentReward: wallet absent, crédit ignoré", {
          uid,
          tid,
        });
        return false;
      }
      const wallet = walletSnap.data() as Wallet;
      const before = wallet.cauris ?? 0;
      const after = Math.min(before + amount, CAURIS_MAX_BALANCE);
      const effective = after - before;
      const newVersion = (wallet.version ?? 0) + 1;

      tx.update(walletRef, {
        cauris: after,
        version: newVersion,
        updated_at: FieldValue.serverTimestamp(),
      });
      tx.set(auditRef, {
        type: "credit_cauris",
        source: "tournament",
        amount: effective,
        pack_id: null,
        product_id: null,
        cauris_before: before,
        cauris_after: after,
        wallet_version_before: wallet.version ?? 0,
        wallet_version_after: newVersion,
        actor_uid: uid,
        timestamp: FieldValue.serverTimestamp(),
        details: { tournament_id: tid, rank, requested_amount: amount },
      });
      return true;
    });
  } catch (err) {
    logger.error("creditTournamentReward failed", { uid, tid, err });
    return false;
  }
}

/**
 * Octroie un badge cosmétique de tournoi sur le profil du joueur.
 * `profiles/{uid}/badges/{tid}` (un badge par tournoi, idempotent via merge).
 */
export async function awardTournamentBadge(
  uid: string,
  tid: string,
  badgeId: string,
  rank: number,
  tournamentName: string
): Promise<void> {
  await getFirestore()
    .collection("profiles")
    .doc(uid)
    .collection("badges")
    .doc(tid)
    .set(
      {
        tournament_id: tid,
        badge_id: badgeId,
        label: tournamentName,
        rank,
        awarded_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}
