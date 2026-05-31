import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAuth } from "../utils/auth";
import {
  CAURIS_CREDIT_MAX_BY_SOURCE,
  CAURIS_MAX_BALANCE,
  walletDocRef,
  auditCollectionRef,
  type Wallet,
} from "./walletHelpers";

/**
 * `creditCauris` — crédite cauris au wallet d'un user.
 *
 * Appelée en fire-and-forget par le client après une action in-game
 * (victoire, daily challenge, rewarded ad, streak quotidien, grant IAP).
 *
 * Le crédit local est appliqué immédiatement côté client (offline-first).
 * Le serveur est appelé pour persister l'audit + valider anti-cheat.
 *
 * Anti-cheat : `amount <= CAURIS_CREDIT_MAX_BY_SOURCE[source]`. Si violé,
 * la CF rejette `invalid-argument` et log `tamper_detected` dans l'audit.
 *
 * Cf `docs/wallet_server_schema.md` §3 (cycle de vie) et §5 (anti-cheat).
 */

const _allowedSources = ['win', 'daily', 'rewarded', 'streak', 'iap', 'manual'] as const;

const Input = z.object({
  amount: z.number().int().positive().max(100_000),
  source: z.enum(_allowedSources),
  /// Référence optionnelle pour audit (ex: matchId, dailyDate, productId).
  reference: z.string().max(128).optional(),
});

export type CreditCaurisOutput = {
  cauris: number;
  version: number;
  amount: number;
};

export const creditCauris = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<CreditCaurisOutput> => {
    const uid = requireAuth(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { amount, source, reference } = parsed.data;

    const max = CAURIS_CREDIT_MAX_BY_SOURCE[source];
    if (max !== undefined && amount > max) {
      logger.warn("creditCauris: amount exceeds cap (possible tamper)", {
        uid,
        source,
        amount,
        max,
      });
      // Audit log tamper_detected (best-effort hors transaction)
      auditCollectionRef(uid).doc().set({
        type: "tamper_detected",
        source,
        amount,
        actor_uid: uid,
        timestamp: FieldValue.serverTimestamp(),
        details: { reason: "credit_amount_exceeds_cap", cap: max, reference },
      }).catch(() => {});
      throw new HttpsError(
        "invalid-argument",
        `Montant ${amount} dépasse le cap ${max} pour la source "${source}".`
      );
    }

    const db = getFirestore();
    const walletRef = walletDocRef(uid);
    const auditRef = auditCollectionRef(uid).doc();

    const result = await db.runTransaction(async (tx) => {
      const walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Wallet non initialisé. Appeler bootstrapWallet d'abord."
        );
      }
      const wallet = walletSnap.data() as Wallet;
      const currentCauris = wallet.cauris;
      const currentVersion = wallet.version;

      // Saturation au plafond global
      const newCauris = Math.min(currentCauris + amount, CAURIS_MAX_BALANCE);
      const effectiveCredit = newCauris - currentCauris; // peut être < amount si plafond atteint
      const newVersion = currentVersion + 1;

      tx.update(walletRef, {
        cauris: newCauris,
        version: newVersion,
        updated_at: FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, {
        type: "credit_cauris",
        source,
        amount: effectiveCredit,
        pack_id: null,
        product_id: source === 'iap' ? reference ?? null : null,
        cauris_before: currentCauris,
        cauris_after: newCauris,
        wallet_version_before: currentVersion,
        wallet_version_after: newVersion,
        actor_uid: uid,
        timestamp: FieldValue.serverTimestamp(),
        details: { requested_amount: amount, reference },
      });

      return {
        cauris: newCauris,
        version: newVersion,
        amount: effectiveCredit,
      };
    });

    logger.info("creditCauris: success", {
      uid,
      source,
      requestedAmount: amount,
      effectiveCredit: result.amount,
      newBalance: result.cauris,
    });

    return result;
  }
);
