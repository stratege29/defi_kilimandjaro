import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

import { requireAdmin } from "../utils/auth";
import {
  PACK_DEFAULT_LANG,
  PACK_FORMAT_VERSION_V3,
  PACK_MIN_APP_VERSION,
  buildPackArtifact,
  uploadPackArtifact,
  type DevinetteV3,
} from "./packArtifact";
import { validatePackDraftPure } from "./validatePackDraft";

/**
 * `publishPack` — publie une nouvelle version d'un pack en production.
 *
 * Séquence (cf `docs/backoffice_schema.md` §4) :
 *  1. Guard requireAdmin
 *  2. Lit toutes les devinettes du pack (status IN draft|published, deleted_at null)
 *  3. Charge `catalog/tags_whitelist`, valide en interne via validatePackDraftPure
 *     → bloque si erreurs (failed-precondition)
 *  4. Calcule nextVersion = (meta.latest_published_version ?? 0) + 1
 *  5. Sérialise format v3 idempotent + gzip + SHA256
 *  6. Upload Storage `packs/v2/<id>/<id>-vN.json.gz`
 *  7. Écritures Firestore (séquentielles, set merge — quasi-idempotent) :
 *     - packs/<id>/versions/<N>          (status='active')
 *     - packs/<id>/versions/<N-1>        (status='archived', si existe)
 *     - content_packs/<id>               (manifest courant)
 *     - content_index/global             (arrayUnion <id>)
 *     - catalog/index                    (bump catalog_version)
 *     - packs/<id>/meta                  (latest_published_version, next_draft_version)
 *     - packs/<id>/audit/<auto>          (type='publish')
 *  8. Batch updates devinettes :
 *     - status='draft'                   → status='published', published_version=N, draft_version=null
 *     - status='archived' + deleted_at   → status='deleted'
 *
 * Pas de transaction globale : volume potentiellement > 500 ops (limite Firestore).
 * Toutes les écritures sont idempotentes (set merge ou update conditionnel),
 * donc une re-run produit le même état final.
 */

const Input = z.object({
  packId: z.string().regex(/^[a-z][a-z0-9_]{1,31}$/, "packId invalide"),
  /** Optionnel : force une version cible (défaut = auto-increment). */
  forceVersion: z.number().int().min(1).max(9999).optional(),
});

export type PublishPackOutput = {
  packId: string;
  version: number;
  count: number;
  hashSha256: string;
  sizeBytes: number;
  storagePath: string;
  downloadUrl: string;
  catalogVersion: number;
};

// ---------------------------------------------------------------------------
// Helpers — extraits pour testabilité
// ---------------------------------------------------------------------------

/**
 * Lit toutes les devinettes éligibles à un export du pack.
 *
 * Critères : status ∈ {draft, published} ET deleted_at == null.
 * Trié par `id` croissant pour idempotence du hash de l'export.
 */
async function fetchPackDevinettes(
  packId: string
): Promise<{ raw: FirebaseFirestore.QueryDocumentSnapshot[]; payload: DevinetteV3[] }> {
  const snap = await getFirestore()
    .collection("packs")
    .doc(packId)
    .collection("devinettes")
    .where("status", "in", ["draft", "published"])
    .get();

  const raw: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  const all: DevinetteV3[] = [];

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.deleted_at != null) continue;
    raw.push(doc);
    all.push(toDevinetteV3(data));
  }

  // Tri par id pour idempotence.
  raw.sort((a, b) => a.id.localeCompare(b.id));
  all.sort((a, b) => a.id.localeCompare(b.id));

  return { raw, payload: all };
}

/**
 * Strip les champs de cycle de vie backoffice (status, draft_version…)
 * pour ne garder que les champs du format v3 publié.
 */
function toDevinetteV3(data: FirebaseFirestore.DocumentData): DevinetteV3 {
  return {
    id: data.id,
    pack: data.pack,
    country: data.country,
    answer: data.answer,
    answer_normalized: data.answer_normalized,
    letters_pool: data.letters_pool,
    riddle: data.riddle,
    explanation: data.explanation,
    difficulty: data.difficulty,
    estimated_time_s: data.estimated_time_s ?? 30,
    tags: data.tags ?? [],
    format_version: PACK_FORMAT_VERSION_V3,
  };
}

async function loadTagsWhitelist(): Promise<Set<string>> {
  const snap = await getFirestore()
    .collection("catalog")
    .doc("tags_whitelist")
    .get();
  const raw = snap.exists ? snap.data() : null;
  const list = Array.isArray(raw?.tags) ? raw!.tags : [];
  return new Set<string>(list.filter((t: unknown) => typeof t === "string"));
}

async function loadCurrentPackVersion(packId: string): Promise<number> {
  const metaSnap = await getFirestore()
    .collection("packs")
    .doc(packId)
    .collection("meta")
    .doc("doc")
    .get();
  const v = metaSnap.exists ? (metaSnap.data()?.latest_published_version as
    | number
    | undefined) : undefined;
  return v ?? 0;
}

/**
 * Update les devinettes du pack pour refléter la nouvelle version publiée.
 *
 * Effectue les updates par batches de 400 (limite Firestore : 500 ops/batch).
 * Idempotent : re-jouer le batch produit le même état.
 */
async function applyDevinettesStatusTransition(
  packId: string,
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
  newVersion: number,
  actorUid: string
): Promise<{ promoted: number; archived: number }> {
  const db = getFirestore();
  let promoted = 0;
  let archived = 0;
  const BATCH_SIZE = 400;

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + BATCH_SIZE);

    for (const doc of chunk) {
      const data = doc.data();
      if (data.status === "draft") {
        batch.update(doc.ref, {
          status: "published",
          published_version: newVersion,
          draft_version: null,
          updated_at: FieldValue.serverTimestamp(),
          updated_by: actorUid,
        });
        promoted++;
      } else if (data.status === "archived" && data.deleted_at != null) {
        batch.update(doc.ref, {
          status: "deleted",
          updated_at: FieldValue.serverTimestamp(),
          updated_by: actorUid,
        });
        archived++;
      }
      // status='published' (inchangée depuis dernière version) : on ne touche pas.
    }

    await batch.commit();
  }

  return { promoted, archived };
}

// ---------------------------------------------------------------------------
// Pool de duel — miroir vers la collection racine `devinettes`
// ---------------------------------------------------------------------------

/**
 * Mappe la difficulté numérique (format asset/v3, 1-4) vers le tier duel
 * `easy|medium|hard`. Aligné sur `tools/scripts/seed_firestore_devinettes.mjs`
 * (1→easy, 2→medium, 3/4→hard).
 */
function mapDifficultyToDuelTier(n: number): "easy" | "medium" | "hard" {
  if (n === 1) return "easy";
  if (n === 2) return "medium";
  if (n === 3 || n === 4) return "hard";
  return "medium"; // fallback défensif
}

/** Extrait la chaîne FR d'un champ multilingue (fallback 1ère langue dispo). */
function pickFrench(field: Record<string, string> | undefined): string {
  if (!field) return "";
  if (typeof field.fr === "string") return field.fr;
  const first = Object.values(field)[0];
  return typeof first === "string" ? first : "";
}

/**
 * Mirror les devinettes publiées vers la collection **racine** `devinettes`,
 * source du **pool de duel** (cf `matchmaking/devinettesCache.ts`, requête
 * `enabled_for_duel == true && status == "approved"`).
 *
 * Sans ça, un pack n'apparaît jamais en duel tant qu'on n'a pas relancé le
 * seed manuel `seed_firestore_devinettes.mjs` (lequel ne lit en plus que les
 * fichiers bundlés `starter/`, donc rate les packs OTA-only comme football_ci).
 *
 * Idempotent (set merge), batché par 400 (limite Firestore 500 ops/batch).
 * Décision produit : **tous** les packs publiés sont éligibles au duel.
 *
 * NB : ne gère pas les suppressions (cohérent avec publishPack actuel qui ne
 * propage pas les soft-deletes) — un retrait de devinette nécessitera un
 * nettoyage dédié du pool.
 */
async function syncDuelPool(payload: DevinetteV3[]): Promise<number> {
  const db = getFirestore();
  const BATCH_SIZE = 400;
  let written = 0;

  for (let i = 0; i < payload.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = payload.slice(i, i + BATCH_SIZE);
    for (const d of chunk) {
      const ref = db.collection("devinettes").doc(d.id);
      batch.set(
        ref,
        {
          answer: d.answer,
          letters_pool: d.letters_pool,
          riddle: pickFrench(d.riddle),
          explanation: pickFrench(d.explanation),
          proverb: "",
          difficulty: mapDifficultyToDuelTier(d.difficulty),
          pack: d.pack,
          country: d.country,
          enabled_for_duel: true,
          status: "approved",
        },
        { merge: true }
      );
    }
    await batch.commit();
    written += chunk.length;
  }

  return written;
}

// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------

export const publishPack = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (req): Promise<PublishPackOutput> => {
    const uid = requireAdmin(req.auth);
    // Libellé lisible du publieur (email si dispo, sinon uid).
    const publishedBy =
      (req.auth?.token?.email as string | undefined) || uid;

    const parsed = Input.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const { packId, forceVersion } = parsed.data;

    logger.info("publishPack: start", { uid, packId, forceVersion });

    // 1. Lire les devinettes du pack
    const { raw, payload } = await fetchPackDevinettes(packId);
    if (payload.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        `Pack "${packId}" ne contient aucune devinette éligible.`
      );
    }

    // 2. Valider strict (réutilise la logique pure de validatePackDraft)
    const tagsWhitelist = await loadTagsWhitelist();
    const validation = validatePackDraftPure(packId, payload, tagsWhitelist);
    if (!validation.valid) {
      logger.warn("publishPack: validation failed", {
        packId,
        errors: validation.errors.length,
        sample: validation.errors.slice(0, 5),
      });
      throw new HttpsError(
        "failed-precondition",
        `Validation échouée (${validation.errors.length} erreurs). Appeler validatePackDraft pour le détail.`,
        { validationErrors: validation.errors }
      );
    }

    // 3. Compute next version
    const currentVersion = await loadCurrentPackVersion(packId);
    const nextVersion = forceVersion ?? currentVersion + 1;
    if (forceVersion && forceVersion <= currentVersion) {
      throw new HttpsError(
        "invalid-argument",
        `forceVersion (${forceVersion}) doit être > version courante (${currentVersion}).`
      );
    }

    // 4. Build artefact (idempotent : même contenu → même hash)
    const artifact = buildPackArtifact(packId, nextVersion, payload);

    // 5. Upload Storage
    const { storagePath, downloadUrl } = await uploadPackArtifact(
      packId,
      nextVersion,
      artifact
    );

    const db = getFirestore();
    const packRef = db.collection("packs").doc(packId);

    // 6. Écritures Firestore — séquentielles, idempotentes (set merge).

    // 6a. packs/<id>/versions/<N> = active
    const versionDoc = {
      number: nextVersion,
      hash_sha256: artifact.hashSha256,
      size_bytes: artifact.sizeBytes,
      count: payload.length,
      storage_path: storagePath,
      download_url: downloadUrl,
      format_version: PACK_FORMAT_VERSION_V3,
      langs: artifact.payload.langs,
      default_lang: PACK_DEFAULT_LANG,
      min_app_version: PACK_MIN_APP_VERSION,
      published_at: FieldValue.serverTimestamp(),
      published_by: uid,
      status: "active",
      previous_version: currentVersion > 0 ? currentVersion : null,
    };
    await packRef
      .collection("versions")
      .doc(String(nextVersion))
      .set(versionDoc, { merge: true });

    // 6b. Archive l'ancienne version (si existe)
    if (currentVersion > 0) {
      await packRef
        .collection("versions")
        .doc(String(currentVersion))
        .set(
          {
            status: "archived",
            archived_at: FieldValue.serverTimestamp(),
            archived_by: uid,
          },
          { merge: true }
        );
    }

    // 6c. Manifest content_packs/<id> (rétrocompat OTA v0.2)
    await db.collection("content_packs").doc(packId).set(
      {
        pack: packId,
        current_version: nextVersion,
        format_version: PACK_FORMAT_VERSION_V3,
        hash_sha256: artifact.hashSha256,
        size_bytes: artifact.sizeBytes,
        count: payload.length,
        storage_path: storagePath,
        download_url: downloadUrl,
        min_app_version: PACK_MIN_APP_VERSION,
        langs: artifact.payload.langs,
        default_lang: PACK_DEFAULT_LANG,
        enabled: true,
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // 6d. content_index/global — arrayUnion idempotent
    await db
      .collection("content_index")
      .doc("global")
      .set(
        {
          packs: FieldValue.arrayUnion(packId),
          min_format_version: PACK_FORMAT_VERSION_V3,
        },
        { merge: true }
      );

    // 6e. catalog/index : bump catalog_version (cache-bust) + maj de l'entrée
    // du pack (count, version, dernière publication + publieur) lue par le
    // Catalogue admin.
    const catalogVersion = await bumpCatalogVersion({
      packId,
      count: payload.length,
      version: nextVersion,
      publishedBy,
    });

    // 6f. packs/<id>/meta
    await packRef.collection("meta").doc("doc").set(
      {
        id: packId,
        latest_published_version: nextVersion,
        next_draft_version: nextVersion + 1,
        pending_changes: 0,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: uid,
      },
      { merge: true }
    );

    // 7. Transitions de status des devinettes
    const { promoted, archived } = await applyDevinettesStatusTransition(
      packId,
      raw,
      nextVersion,
      uid
    );

    // 7b. Mirror vers le pool de duel (collection racine `devinettes`).
    // Sans ça, le pack n'est jamais tiré en duel (cf seed manuel historique).
    const duelSynced = await syncDuelPool(payload);

    // 8. Audit log
    await packRef.collection("audit").add({
      type: "publish",
      actor_uid: uid,
      timestamp: FieldValue.serverTimestamp(),
      details: {
        version: nextVersion,
        previous_version: currentVersion > 0 ? currentVersion : null,
        count: payload.length,
        hash_sha256: artifact.hashSha256,
        size_bytes: artifact.sizeBytes,
        promoted_drafts: promoted,
        archived_soft_deletes: archived,
        duel_pool_synced: duelSynced,
        warnings_count: validation.warnings.length,
      },
    });

    logger.info("publishPack: success", {
      packId,
      version: nextVersion,
      count: payload.length,
      hash: artifact.hashSha256,
      sizeBytes: artifact.sizeBytes,
      promoted,
      archived,
      duelSynced,
      warnings: validation.warnings.length,
    });

    return {
      packId,
      version: nextVersion,
      count: payload.length,
      hashSha256: artifact.hashSha256,
      sizeBytes: artifact.sizeBytes,
      storagePath,
      downloadUrl,
      catalogVersion,
    };
  }
);

/**
 * Bump `catalog/index.catalog_version` atomiquement.
 *
 * Sert de cache-bust pour les clients qui lisent le catalogue distant
 * (cf docs/backoffice_schema.md §3.2). Retourne la nouvelle valeur.
 */
async function bumpCatalogVersion(opts: {
  packId: string;
  count: number;
  version: number;
  publishedBy: string;
}): Promise<number> {
  const db = getFirestore();
  const ref = db.collection("catalog").doc("index");
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() ?? {} : {};
    const next = ((data.catalog_version as number | undefined) ?? 0) + 1;

    // Maj de l'entrée du pack : count, version, dernière publication + publieur.
    // serverTimestamp() est interdit dans un élément de tableau → Timestamp.now().
    const packs: Array<Record<string, unknown>> = Array.isArray(data.packs)
      ? [...data.packs]
      : [];
    const patch = {
      count: opts.count,
      current_version: opts.version,
      last_published_at: Timestamp.now(),
      last_published_by: opts.publishedBy,
    };
    const idx = packs.findIndex((p) => p && p.id === opts.packId);
    if (idx >= 0) packs[idx] = { ...packs[idx], ...patch };
    else {
      packs.push({
        id: opts.packId,
        visible: false,
        bundled: false,
        ordering: packs.length + 100,
        ...patch,
      });
    }

    tx.set(
      ref,
      {
        packs,
        catalog_version: next,
        schema_version: 4,
        updated_at: FieldValue.serverTimestamp(),
        updated_by: opts.publishedBy,
      },
      { merge: true }
    );
    return next;
  });
}
