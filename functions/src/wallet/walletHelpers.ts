/**
 * Helpers partagés pour les CFs wallet (bootstrapWallet, unlockPack,
 * creditCauris, syncWallet).
 *
 * Cf `docs/wallet_server_schema.md` pour le design complet.
 */

import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

/// Schéma du doc `users/{uid}/inventory/wallet`.
export interface Wallet {
  cauris: number;
  owned_packs: string[];
  version: number;
  created_at: Timestamp;
  updated_at: Timestamp;
  last_sync_at: Timestamp;
  bootstrap_source: string;
}

/// Caps anti-cheat par type de crédit (cauris max par appel).
///
/// Valeurs choisies large (> max théorique remote config) pour ne pas bloquer
/// les UX legit mais bloquer les bots qui pousseraient 999999 d'un coup.
///
/// Cf docs/wallet_server_schema.md §5.
export const CAURIS_CREDIT_MAX_BY_SOURCE: Record<string, number> = {
  win: 200, // > eco_win_reward_base (30) * tier max (~5)
  daily: 800, // > 100 base + bonus streak max
  rewarded: 300, // > eco_rewarded_video_bonus (50) avec marge
  streak: 500, // > eco_streak_rewards max (300)
  iap: 5000, // = max IAP pack (coins_pack_4999)
  manual: 1000, // dev/admin grant
};

/// Solde maximum autorisé (anti-spam, anti-overflow JS).
export const CAURIS_MAX_BALANCE = 999_999;

/// Cap du bootstrap depuis le client (anti-cheat sur premier sync).
/// = eco_initial_cauris (120) + marge raisonnable pour les early adopters.
export const CAURIS_BOOTSTRAP_CAP = 2_000;

/// Path Firestore du wallet d'un user.
export function walletDocRef(uid: string) {
  return getFirestore()
    .collection("users")
    .doc(uid)
    .collection("inventory")
    .doc("wallet");
}

/// Path Firestore de la subcollection audit.
///
/// Choix : `users/{uid}/inventory_audit/` au lieu d'un nesting
/// `users/{uid}/inventory/wallet/audit/` — plus simple à indexer et à
/// gouverner par rules Firestore.
export function auditCollectionRef(uid: string) {
  return getFirestore()
    .collection("users")
    .doc(uid)
    .collection("inventory_audit");
}

/**
 * Écrit un log d'audit (append-only).
 *
 * @param uid - propriétaire du wallet
 * @param data - payload du log (type, source, amounts, etc.)
 * @param tx - transaction Firestore (optionnel, pour append dans la même tx)
 */
export function writeAuditLog(
  uid: string,
  data: Record<string, unknown>,
  tx?: FirebaseFirestore.Transaction
): void {
  const ref = auditCollectionRef(uid).doc();
  const payload = {
    ...data,
    actor_uid: uid,
    timestamp: FieldValue.serverTimestamp(),
  };
  if (tx) {
    tx.set(ref, payload);
  } else {
    void ref.set(payload);
  }
}
