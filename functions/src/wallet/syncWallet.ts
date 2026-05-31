import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { requireAuth } from "../utils/auth";
import { walletDocRef, type Wallet } from "./walletHelpers";

/**
 * `syncWallet` — retourne le wallet serveur courant pour pull-down client.
 *
 * Use cases :
 *   - Pull au boot si client offline plus de 24h
 *   - Resync forcé après détection de divergence (tamper warning)
 *   - Restore cross-device après réinstall
 *
 * Pas de mutation. Si wallet n'existe pas → not-found (client devra appeler
 * bootstrapWallet en fallback).
 */

export type SyncWalletOutput = {
  cauris: number;
  ownedPacks: string[];
  version: number;
  updatedAtMs: number | null;
};

export const syncWallet = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<SyncWalletOutput> => {
    const uid = requireAuth(req.auth);

    const snap = await walletDocRef(uid).get();
    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        "Wallet pas encore initialisé pour cet utilisateur."
      );
    }
    const wallet = snap.data() as Wallet;

    logger.info("syncWallet", { uid, version: wallet.version });

    return {
      cauris: wallet.cauris,
      ownedPacks: wallet.owned_packs,
      version: wallet.version,
      updatedAtMs: wallet.updated_at?.toMillis() ?? null,
    };
  }
);
