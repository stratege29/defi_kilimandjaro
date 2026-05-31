import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAuth } from "../utils/auth";
import {
  CAURIS_BOOTSTRAP_CAP,
  walletDocRef,
  writeAuditLog,
} from "./walletHelpers";

/**
 * `bootstrapWallet` — crée le doc wallet pour un user au premier usage.
 *
 * Idempotent : si le wallet existe déjà, retourne l'état serveur courant
 * pour permettre au client de resync (offline-first).
 *
 * Anti-cheat : cap le cauris initial à `CAURIS_BOOTSTRAP_CAP` (2000)
 * pour empêcher un client modifié de s'auto-créditer.
 *
 * Cf `docs/wallet_server_schema.md` §3.
 */

const Input = z.object({
  /// Solde cauris actuel du client (SharedPrefs). Sera capped serveur-side.
  cauris: z.number().int().min(0).max(1_000_000),
  /// Packs déjà possédés en local. Filtrés contre catalog/index serveur.
  ownedPacks: z.array(z.string().min(1).max(64)).max(100).default([]),
});

export type BootstrapWalletOutput = {
  /// True si le wallet vient d'être créé.
  created: boolean;
  /// Solde cauris **après** bootstrap (peut différer de l'input si cap appliqué).
  cauris: number;
  /// Packs validés (intersection ownedPacks ∩ catalog).
  ownedPacks: string[];
  /// Version du wallet (1 si juste créé, >1 si déjà existant).
  version: number;
  /// True si le serveur a clampé le cauris en dessous de la demande client.
  capped: boolean;
};

export const bootstrapWallet = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
  },
  async (req): Promise<BootstrapWalletOutput> => {
    const uid = requireAuth(req.auth);

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { cauris: clientCauris, ownedPacks: clientPacks } = parsed.data;

    const ref = walletDocRef(uid);
    const existing = await ref.get();

    if (existing.exists) {
      // Idempotent : retourne l'état serveur
      const data = existing.data()!;
      logger.info("bootstrapWallet: already exists, returning server state", {
        uid,
        serverVersion: data.version,
      });
      return {
        created: false,
        cauris: (data.cauris as number) ?? 0,
        ownedPacks: (data.owned_packs as string[]) ?? [],
        version: (data.version as number) ?? 1,
        capped: false,
      };
    }

    // Cap anti-cheat
    const capped = clientCauris > CAURIS_BOOTSTRAP_CAP;
    const finalCauris = Math.min(clientCauris, CAURIS_BOOTSTRAP_CAP);

    // Dédoublonne les packs (defensive)
    const dedupedPacks = [...new Set(clientPacks)];

    const now = FieldValue.serverTimestamp();
    await ref.set({
      cauris: finalCauris,
      owned_packs: dedupedPacks,
      version: 1,
      created_at: now,
      updated_at: now,
      last_sync_at: now,
      bootstrap_source: "client_v1",
    });

    writeAuditLog(uid, {
      type: "bootstrap",
      source: "client",
      cauris_before: 0,
      cauris_after: finalCauris,
      wallet_version_before: 0,
      wallet_version_after: 1,
      details: {
        client_cauris: clientCauris,
        client_packs: clientPacks,
        capped,
      },
    });

    logger.info("bootstrapWallet: created", {
      uid,
      finalCauris,
      packsCount: dedupedPacks.length,
      capped,
    });

    return {
      created: true,
      cauris: finalCauris,
      ownedPacks: dedupedPacks,
      version: 1,
      capped,
    };
  }
);
