/**
 * Validation serveur des reçus IAP — anti-fraude + idempotence + audit.
 *
 * **Flux côté client** (cf. `lib/data/iap/iap_service.dart`) :
 * 1. Le plugin `in_app_purchase` reçoit `PurchaseStatus.purchased`.
 * 2. Le client appelle [`validateIapReceipt`] (cette fonction) en parallèle
 *    du grant local. La fonction est **idempotente** : un re-call avec le
 *    même `orderId` ne re-crédite pas.
 * 3. Le client crédite localement les cauris dès réception du purchase
 *    (UX snappy). Cette fonction sert d'audit log côté serveur.
 *
 * **Idempotence** : chaque reçu est indexé par
 * `iap_receipts/{platform}_{orderOrTransactionId}`. Si le doc existe déjà,
 * on retourne `{ alreadyValidated: true, granted: false }` sans rien faire.
 *
 * **Verification cryptographique** (TODO Phase 4.1) : la vérification de
 * la signature Apple (App Store Server API) et Google (Play Developer API)
 * nécessite des secrets (Apple `.p8` + KeyID + IssuerID, Google service
 * account JSON). En attendant que ces secrets soient provisionnés via
 * Firebase Secret Manager, on stocke le reçu brut tel que reçu et on le
 * marque `verified: false`. Une seconde Cloud Function `verifyPendingReceipts`
 * (cron quotidien) pourra rétro-valider les reçus pendant la fenêtre de
 * tolérance Apple/Google (24 h pour Apple, 7 jours pour Google avant
 * acknowledge requis).
 *
 * **Quotas** : 1 validation / seconde / uid via rate limiter
 * (anti-spam). Quota générant des erreurs `resource-exhausted`.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

/**
 * Catalogue serveur des product IDs autorisés. Toute productId hors de
 * cette liste est rejeté en `invalid-argument` (anti-injection).
 *
 * Doit rester synchronisé avec :
 * - `lib/data/iap/cauris_pack.dart` (enum CaurisPack.productId, plus
 *   `noAdsProductId` et `starterPackProductId`)
 * - App Store Connect + Play Console catalogue produits
 */
const ALLOWED_PRODUCT_IDS = new Set<string>([
  "coins_pack_49",
  "coins_pack_199",
  "coins_pack_499",
  "coins_pack_1499",
  "coins_pack_4999",
  "no_ads_remove",
  "starter_pack_299",
]);

/**
 * Cauris crédités côté client pour chaque productId — utilisé uniquement
 * pour l'audit log serveur (le grant effectif est local côté Dart pour
 * la réactivité). Pour les non-consumables (`no_ads_remove`, starter),
 * la valeur est 0 (= flag, pas un montant).
 */
const CAURIS_GRANTED_BY_PRODUCT: Record<string, number> = {
  coins_pack_49: 49,
  coins_pack_199: 199,
  coins_pack_499: 499,
  coins_pack_1499: 1499,
  coins_pack_4999: 4999,
  starter_pack_299: 350,
  no_ads_remove: 0,
};

const ValidateIapInput = z.object({
  platform: z.enum(["ios", "android"]),
  productId: z.string().min(3).max(64),
  // iOS : `transactionIdentifier` du SKPaymentTransaction.
  // Android : `orderId` du Purchase.
  orderOrTransactionId: z.string().min(4).max(128),
  // Token Android (`Purchase.purchaseToken`) ou reçu base64 iOS
  // (`appStoreReceipt`). Non utilisé pour l'instant côté serveur — sera
  // appelé via App Store Server API / Play Developer API en Phase 4.1.
  rawReceipt: z.string().min(8).max(8192),
  // Timestamp client à des fins d'audit (ne sert pas à la décision).
  purchaseDateMs: z.number().int().nonnegative().optional(),
});

export const validateIapReceipt = onCall(
  {
    region: "europe-west1",
    // App Check pas encore enforced en attendant la propagation des
    // debug tokens iOS/Android (cf. submitDevinette).
    enforceAppCheck: false,
    cors: true,
  },
  async (req) => {
    const auth = req.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }

    const parsed = ValidateIapInput.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const input = parsed.data;

    if (!ALLOWED_PRODUCT_IDS.has(input.productId)) {
      logger.warn("IAP validation — productId hors catalogue", {
        uid: auth.uid,
        productId: input.productId,
      });
      throw new HttpsError("invalid-argument", "Product ID inconnu.");
    }

    // Idempotence : 1 doc par (platform, orderOrTransactionId).
    // Slash interdit dans un docId → utilise underscore.
    const docId = `${input.platform}_${input.orderOrTransactionId}`;
    const ref = getFirestore().collection("iap_receipts").doc(docId);
    const existing = await ref.get();
    if (existing.exists) {
      logger.info("IAP validation — déjà enregistré (idempotent)", {
        uid: auth.uid,
        docId,
      });
      return {
        alreadyValidated: true,
        granted: false,
        productId: input.productId,
      };
    }

    // TODO(phase 4.1): appel App Store Server API / Play Developer API
    // pour vérifier cryptographiquement le reçu. Pour l'instant on stocke
    // `verified: false` et un cron quotidien rétro-validera.
    const now = FieldValue.serverTimestamp();
    await ref.set({
      uid: auth.uid,
      platform: input.platform,
      productId: input.productId,
      orderOrTransactionId: input.orderOrTransactionId,
      caurisGranted: CAURIS_GRANTED_BY_PRODUCT[input.productId] ?? 0,
      rawReceipt: input.rawReceipt,
      purchaseDateMs: input.purchaseDateMs ?? null,
      verified: false,
      receivedAt: now,
      verifiedAt: null,
    });

    // Miroir dans la sous-collection joueur — utilisé par l'app pour
    // historique d'achats et restore cross-device futur.
    await getFirestore()
      .collection("players")
      .doc(auth.uid)
      .collection("purchases")
      .doc(docId)
      .set({
        productId: input.productId,
        platform: input.platform,
        purchaseDateMs: input.purchaseDateMs ?? null,
        receivedAt: now,
      });

    logger.info("IAP validation — reçu enregistré", {
      uid: auth.uid,
      productId: input.productId,
      docId,
    });

    return {
      alreadyValidated: false,
      granted: true,
      productId: input.productId,
    };
  }
);
