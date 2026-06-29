/**
 * notifyPackUpdate.ts — Broadcast FCM quand le catalogue de packs change.
 *
 * Déclencheur : écriture sur `catalog/index`. On n'envoie que lorsque
 * `catalog_version` a réellement changé (un publish/rollback le bump), pour
 * éviter de spammer sur les écritures intermédiaires (ex. `upsertPackMeta`).
 *
 * Envoie au topic `pack_updates` (auquel le client s'abonne au boot). Le détail
 * (quel pack est nouveau / à mettre à jour) est calculé côté client via le
 * catalogue + l'état local ; le push sert juste de réveil + deep-link.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { sendFcmToTopic } from "../utils/fcm";

interface CatalogPackEntry {
  id?: string;
}

/** Extrait l'ensemble des ids de packs d'un snapshot `catalog/index`. */
function packIdsOf(data: FirebaseFirestore.DocumentData | undefined): Set<string> {
  const raw = data?.["packs"];
  if (!Array.isArray(raw)) return new Set<string>();
  const ids = new Set<string>();
  for (const entry of raw as CatalogPackEntry[]) {
    if (entry && typeof entry.id === "string") ids.add(entry.id);
  }
  return ids;
}

export const notifyPackUpdate = onDocumentWritten(
  { document: "catalog/index", region: "europe-west1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // Doc supprimé ou inexistant → rien à annoncer.
    if (!after) return;

    const beforeVersion = (before?.["catalog_version"] as number | undefined) ?? -1;
    const afterVersion = (after["catalog_version"] as number | undefined) ?? -1;

    // N'envoyer que sur un vrai changement de version (publish/rollback).
    if (afterVersion === beforeVersion) {
      logger.debug("notifyPackUpdate: catalog_version inchangé, skip.");
      return;
    }

    // Détecte les packs nouvellement ajoutés (présents après, absents avant)
    // pour un message plus parlant si possible.
    const beforeIds = packIdsOf(before);
    const afterIds = packIdsOf(after);
    const addedIds = [...afterIds].filter((id) => !beforeIds.has(id));

    const title = addedIds.length > 0
      ? "Nouveau pack disponible"
      : "Nouveau contenu disponible";
    const body = addedIds.length > 0
      ? "Un nouveau pack vient d'arriver. Ouvre Mes packs pour le découvrir."
      : "De nouvelles énigmes t'attendent. Ouvre Mes packs pour les récupérer.";

    const sent = await sendFcmToTopic("pack_updates", title, body, {
      type: "pack_update",
    });

    logger.info("notifyPackUpdate", {
      beforeVersion,
      afterVersion,
      addedCount: addedIds.length,
      sent,
    });
  }
);
