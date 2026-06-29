import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAuth } from "../utils/auth";
import {
  CAURIS_CREDIT_MAX_BY_SOURCE,
  CAURIS_CREDIT_DAILY_COUNT_MAX,
  CAURIS_MAX_BALANCE,
  walletDocRef,
  auditCollectionRef,
  creditCountersRef,
  utcDayKey,
  type Wallet,
  type CreditCounters,
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
  /// Clé d'idempotence (UUID v4 client). Garantit l'exactly-once : un retry
  /// avec la même clé ne re-crédite pas. Sert d'ID de doc d'audit pour
  /// dédup transactionnelle. Optionnelle (rétro-compat clients legacy).
  /// Cf docs/wallet_server_schema.md §3 (outbox idempotent).
  idempotencyKey: z
    .string()
    .regex(/^[A-Za-z0-9_-]{8,128}$/)
    .optional(),
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
    const { amount, source, reference, idempotencyKey } = parsed.data;

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
    const counterRef = creditCountersRef(uid);
    const today = utcDayKey();
    const dailyCountMax = CAURIS_CREDIT_DAILY_COUNT_MAX[source];
    // Idempotence : la clé client devient l'ID du doc d'audit. Sa présence
    // dans la transaction prouve que le crédit a déjà été appliqué (le doc
    // n'est écrit qu'avec la mutation du wallet, atomiquement).
    const auditRef = idempotencyKey
      ? auditCollectionRef(uid).doc(idempotencyKey)
      : auditCollectionRef(uid).doc();

    const result = await db.runTransaction(async (tx) => {
      // Dédup : lecture AVANT toute écriture (contrainte transaction Firestore).
      if (idempotencyKey) {
        const auditSnap = await tx.get(auditRef);
        if (auditSnap.exists) {
          const prior = auditSnap.data() as {
            cauris_after?: number;
            wallet_version_after?: number;
          };
          // Replay : no-op idempotent, on renvoie l'état déjà persisté. Ne
          // ré-incrémente PAS le compteur journalier (sinon un retry réseau
          // consommerait à tort le quota).
          return {
            kind: "replayed" as const,
            cauris: prior.cauris_after ?? 0,
            version: prior.wallet_version_after ?? 0,
            amount: 0,
          };
        }
      }

      const walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Wallet non initialisé. Appeler bootstrapWallet d'abord."
        );
      }

      // Backstop fréquence : nombre de crédits de cette source aujourd'hui
      // (jour UTC). Lecture AVANT écriture. Le compteur se réinitialise
      // paresseusement au changement de jour (utc_day différent → counts {}).
      const counterSnap = await tx.get(counterRef);
      const counterData = counterSnap.exists
        ? (counterSnap.data() as CreditCounters)
        : undefined;
      const counts =
        counterData && counterData.utc_day === today
          ? { ...counterData.counts }
          : {};
      const currentCount = counts[source] ?? 0;
      if (dailyCountMax !== undefined && currentCount >= dailyCountMax) {
        // Quota journalier atteint → rejet. On sort de la transaction sans
        // écrire ; l'audit + le throw sont gérés hors transaction.
        return {
          kind: "rate_limited" as const,
          count: currentCount,
          limit: dailyCountMax,
        };
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

      // Incrémente le compteur journalier de la source (créé/écrasé avec le
      // jour UTC courant — gère le reset paresseux au passage de minuit UTC).
      counts[source] = currentCount + 1;
      tx.set(counterRef, {
        utc_day: today,
        counts,
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
        kind: "applied" as const,
        cauris: newCauris,
        version: newVersion,
        amount: effectiveCredit,
      };
    });

    if (result.kind === "rate_limited") {
      logger.warn("creditCauris: daily count cap reached (possible farming)", {
        uid,
        source,
        count: result.count,
        limit: result.limit,
      });
      // Audit best-effort hors transaction (la tx a été abandonnée).
      auditCollectionRef(uid)
        .doc()
        .set({
          type: "rate_limited",
          source,
          amount,
          actor_uid: uid,
          timestamp: FieldValue.serverTimestamp(),
          details: {
            reason: "credit_daily_count_exceeds_cap",
            count: result.count,
            limit: result.limit,
            reference,
          },
        })
        .catch(() => {});
      throw new HttpsError(
        "resource-exhausted",
        `Limite quotidienne de crédits "${source}" atteinte (${result.limit}/jour).`
      );
    }

    logger.info("creditCauris: success", {
      uid,
      source,
      requestedAmount: amount,
      effectiveCredit: result.amount,
      newBalance: result.cauris,
      replayed: result.kind === "replayed",
    });

    return {
      cauris: result.cauris,
      version: result.version,
      amount: result.amount,
    };
  }
);
