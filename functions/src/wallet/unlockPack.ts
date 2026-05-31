import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAuth } from "../utils/auth";
import {
  walletDocRef,
  auditCollectionRef,
  type Wallet,
} from "./walletHelpers";

/**
 * `unlockPack` — débloque un pack en débitant le wallet du user.
 *
 * Transaction atomique Firestore :
 *   1. Lit `catalog/index`, trouve le pack, extrait `unlock_cost_cauris`
 *   2. Lit `users/{uid}/inventory/wallet` (FAIL si pas bootstrapped)
 *   3. Vérifie cauris >= cost (FAIL failed-precondition)
 *   4. Vérifie pack pas déjà owned (FAIL already-exists)
 *   5. Vérifie pack visible + dans availability window (FAIL precondition)
 *   6. Débit cauris + ajoute pack + bump version
 *   7. Écrit audit log
 *
 * Cf `docs/wallet_server_schema.md` §3 (cycle de vie).
 */

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
});

export type UnlockPackOutput = {
  packId: string;
  cauris: number; // nouveau solde après débit
  ownedPacks: string[]; // liste mise à jour
  version: number; // nouveau wallet version
  cost: number; // coût appliqué (audit-friendly UI)
};

export const unlockPack = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<UnlockPackOutput> => {
    const uid = requireAuth(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId } = parsed.data;

    const db = getFirestore();

    // 1. Lecture catalog/index (hors transaction — read-only)
    const catalogSnap = await db.collection("catalog").doc("index").get();
    if (!catalogSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Catalogue distant indisponible (catalog/index manquant)."
      );
    }
    const catalogData = catalogSnap.data();
    const packsList = catalogData?.packs as Array<Record<string, unknown>> | undefined;
    if (!packsList) {
      throw new HttpsError("failed-precondition", "Catalogue mal formé.");
    }
    const packEntry = packsList.find((p) => p.id === packId);
    if (!packEntry) {
      throw new HttpsError(
        "not-found",
        `Pack "${packId}" introuvable dans le catalogue.`
      );
    }

    const cost = (packEntry.unlock_cost_cauris as number | undefined) ?? 0;
    const visible = (packEntry.visible as boolean | undefined) ?? true;
    const availableFromRaw = packEntry.available_from as string | undefined;
    const availableUntilRaw = packEntry.available_until as string | undefined;

    if (!visible) {
      throw new HttpsError(
        "failed-precondition",
        `Pack "${packId}" non disponible (masqué).`
      );
    }
    if (cost <= 0) {
      throw new HttpsError(
        "failed-precondition",
        `Pack "${packId}" gratuit ou prix non défini — utiliser grantPack à la place.`
      );
    }
    const now = Date.now();
    if (availableFromRaw) {
      const from = Date.parse(availableFromRaw);
      if (!Number.isNaN(from) && now < from) {
        throw new HttpsError(
          "failed-precondition",
          `Pack "${packId}" pas encore disponible (available_from futur).`
        );
      }
    }
    if (availableUntilRaw) {
      const until = Date.parse(availableUntilRaw);
      if (!Number.isNaN(until) && now > until) {
        throw new HttpsError(
          "failed-precondition",
          `Pack "${packId}" n'est plus disponible (available_until passé).`
        );
      }
    }

    // 2. Transaction atomique sur le wallet
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
      const currentPacks = wallet.owned_packs;
      const currentVersion = wallet.version;

      if (currentPacks.includes(packId)) {
        throw new HttpsError(
          "already-exists",
          `Pack "${packId}" déjà possédé.`
        );
      }
      if (currentCauris < cost) {
        throw new HttpsError(
          "failed-precondition",
          `Solde insuffisant : ${currentCauris} cauris, requis ${cost}.`
        );
      }

      const newCauris = currentCauris - cost;
      const newPacks = [...currentPacks, packId];
      const newVersion = currentVersion + 1;

      tx.update(walletRef, {
        cauris: newCauris,
        owned_packs: newPacks,
        version: newVersion,
        updated_at: FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, {
        type: "unlock_pack",
        source: "unlock",
        amount: -cost,
        pack_id: packId,
        product_id: null,
        cauris_before: currentCauris,
        cauris_after: newCauris,
        wallet_version_before: currentVersion,
        wallet_version_after: newVersion,
        actor_uid: uid,
        timestamp: FieldValue.serverTimestamp(),
        details: {},
      });

      return {
        packId,
        cauris: newCauris,
        ownedPacks: newPacks,
        version: newVersion,
        cost,
      };
    });

    logger.info("unlockPack: success", {
      uid,
      packId,
      cost,
      newBalance: result.cauris,
      newVersion: result.version,
    });

    return result;
  }
);
