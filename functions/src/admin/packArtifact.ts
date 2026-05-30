/**
 * Helper de génération d'artefacts pack v3 prêts à uploader.
 *
 * Logique extraite et adaptée de `curation/rebuildCommunityPack.ts` pour être
 * réutilisable par `publishPack` (admin) et tout futur pipeline OTA.
 *
 * Diff vs `rebuildCommunityPack` :
 *  - Format v3 (pas v2) — riddle/explanation = Map<lang, string>
 *  - **Idempotent** : pas de `generated_at` dans le payload (hash stable
 *    quand le contenu ne change pas — aligné sur le seed Dart
 *    `tool/seed_content_packs.dart`)
 *  - `hash_sha256` injecté dans le payload final (le client le re-vérifie
 *    après gunzip dans `RemoteDevinettePackDatasource.downloadAndParse`)
 *
 * Cf `docs/backoffice_schema.md` §5 (cycle de vie version) et §7 (Storage).
 */

import { getStorage } from "firebase-admin/storage";
import { gzipSync } from "zlib";
import { createHash } from "crypto";

export const PACK_FORMAT_VERSION_V3 = 3;
export const PACK_DEFAULT_LANG = "fr";
export const PACK_MIN_APP_VERSION = "0.1.0";

/** Devinette canonique format v3 (cf §3.2 du doc schéma). */
export type DevinetteV3 = {
  id: string;
  pack: string;
  country: string;
  answer: string;
  answer_normalized: string;
  letters_pool: string[];
  riddle: Record<string, string>;
  explanation: Record<string, string>;
  difficulty: number;
  estimated_time_s: number;
  tags: string[];
  format_version: 3;
};

export type PackArtifact = {
  /** Payload JSON final (avec hash_sha256 inclus). */
  payload: Record<string, unknown>;
  /** Hash SHA256 du JSON sérialisé (avant gzip). */
  hashSha256: string;
  /** Buffer gzippé prêt à uploader. */
  gz: Buffer;
  /** Taille gzippée en bytes. */
  sizeBytes: number;
};

/**
 * Détecte la liste des langues couvertes par les devinettes
 * (union des clés `riddle` + `explanation`). Trié alphabétiquement
 * pour idempotence.
 */
function detectLangs(devinettes: DevinetteV3[]): string[] {
  const langs = new Set<string>();
  for (const d of devinettes) {
    for (const k of Object.keys(d.riddle ?? {})) langs.add(k);
    for (const k of Object.keys(d.explanation ?? {})) langs.add(k);
  }
  if (langs.size === 0) return [PACK_DEFAULT_LANG];
  return [...langs].sort();
}

/**
 * Construit le payload pack v3 final (sans hash) — pure function.
 *
 * Ordre des clés est déterministe pour que `JSON.stringify` produise
 * la même chaîne à contenu équivalent (idempotence du hash).
 */
export function buildPackPayloadV3(
  packId: string,
  packVersion: number,
  devinettes: DevinetteV3[]
): Record<string, unknown> {
  const langs = detectLangs(devinettes);
  return {
    format_version: PACK_FORMAT_VERSION_V3,
    pack_id: packId,
    pack_version: packVersion,
    langs,
    default_lang: PACK_DEFAULT_LANG,
    min_app_version: PACK_MIN_APP_VERSION,
    count: devinettes.length,
    devinettes,
  };
}

/**
 * Sérialise + hash + gzip un pack v3.
 *
 * Le `hash_sha256` est calculé sur le JSON final (avec le champ
 * `hash_sha256` inclus, valeur de double-hash). C'est volontaire : le
 * client gunzippe puis recalcule le SHA256 du JSON complet pour valider
 * l'intégrité (cf `RemoteDevinettePackDatasource.downloadAndParse`).
 *
 * Reproductibilité : à contenu identique, hash + gz identiques. Aligné
 * avec `tool/seed_content_packs.dart`.
 */
export function buildPackArtifact(
  packId: string,
  packVersion: number,
  devinettes: DevinetteV3[]
): PackArtifact {
  const payload = buildPackPayloadV3(packId, packVersion, devinettes);

  // 1er hash : sur le JSON sans le champ hash_sha256.
  const encoded1 = Buffer.from(JSON.stringify(payload), "utf8");
  const hash1 = createHash("sha256").update(encoded1).digest("hex");
  (payload as Record<string, unknown>).hash_sha256 = hash1;

  // 2e hash : sur le JSON final (avec hash_sha256 inclus). C'est CELUI
  // qui est stocké dans le manifest Firestore et re-vérifié par le client.
  const encodedFinal = Buffer.from(JSON.stringify(payload), "utf8");
  const hashFinal = createHash("sha256").update(encodedFinal).digest("hex");

  const gz = gzipSync(encodedFinal);

  return {
    payload,
    hashSha256: hashFinal,
    gz,
    sizeBytes: gz.length,
  };
}

/**
 * Chemin Storage canonique pour une version donnée.
 *
 * Format : `packs/v2/<packId>/<packId>-v<N>.json.gz`
 * (la racine `packs/v2/` est partagée avec le rebuild community ; le numéro
 * v2 désigne la **génération du protocole de stockage**, pas la version
 * du pack lui-même qui est dans le nom de fichier.)
 */
export function storagePathFor(packId: string, packVersion: number): string {
  return `packs/v2/${packId}/${packId}-v${packVersion}.json.gz`;
}

/**
 * URL publique de téléchargement v0 (Firebase Storage download URL).
 *
 * Le bucket doit autoriser la lecture publique sur `packs/**` (cf
 * `storage.rules`). C'est le contrat OTA actuel — pas de signed URL.
 */
export function downloadUrlFor(bucket: string, storagePath: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(
    storagePath
  )}?alt=media`;
}

/**
 * Upload un artefact pack sur Cloud Storage avec les bons metadata
 * (contentEncoding gzip + cacheControl long + hash custom).
 *
 * @returns      `{ storagePath, downloadUrl, bucket }`
 */
export async function uploadPackArtifact(
  packId: string,
  packVersion: number,
  artifact: PackArtifact
): Promise<{ storagePath: string; downloadUrl: string; bucket: string }> {
  const storage = getStorage();
  const bucketRef = storage.bucket();
  const bucket = bucketRef.name;
  const storagePath = storagePathFor(packId, packVersion);

  const file = bucketRef.file(storagePath);
  await file.save(artifact.gz, {
    contentType: "application/json",
    metadata: {
      contentEncoding: "gzip",
      cacheControl: "public, max-age=86400",
      metadata: {
        hashSha256: artifact.hashSha256,
        packVersion: String(packVersion),
        formatVersion: String(PACK_FORMAT_VERSION_V3),
      },
    },
  });

  return {
    storagePath,
    downloadUrl: downloadUrlFor(bucket, storagePath),
    bucket,
  };
}
