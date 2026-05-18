/**
 * publishPack — HTTPS callable, region europe-west1.
 *
 * Reconstruit le pack `{packId}` à partir des questions stockées dans
 * Firestore (`content_packs/{packId}/questions/*`), génère le JSON v3,
 * gzippe, upload sur Cloud Storage à `packs/v2/{packId}/{packId}-v{N}.json.gz`,
 * met à jour le manifest Firestore `content_packs/{packId}` (current_version,
 * hash, size, count, download_url), et garantit que `content_index/global`
 * référence le packId.
 *
 * Auth : requiert `request.auth.token.role == "admin"`.
 *
 * v1 — bump systématique de la version à chaque appel (pas de détection de
 * "rien n'a changé"). Trivialement idempotent côté Storage (chemin unique
 * par version) ; côté Firestore le manifest est cohérent post-écriture.
 *
 * Erreurs :
 *   - unauthenticated : pas d'auth
 *   - permission-denied : claim role != admin
 *   - invalid-argument : packId manquant
 *   - not-found : aucune question dans le pack
 *   - failed-precondition : le doc content_packs/{packId} doit exister
 *     (créé via le backoffice avant la 1re publication)
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { gzipSync } from "zlib";
import { createHash } from "crypto";

const PACK_FORMAT_VERSION = 3;
const DEFAULT_LANG = "fr";
const MIN_APP_VERSION = "0.1.0";

interface QuestionDoc {
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
  format_version: number;
}

function requireAdmin(token: Record<string, unknown> | undefined): void {
  const role = token?.role;
  if (role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Le rôle admin est requis pour publier un pack."
    );
  }
}

function detectLangs(questions: QuestionDoc[]): string[] {
  const langs = new Set<string>();
  for (const q of questions) {
    for (const k of Object.keys(q.riddle ?? {})) langs.add(k);
    for (const k of Object.keys(q.explanation ?? {})) langs.add(k);
  }
  if (langs.size === 0) langs.add(DEFAULT_LANG);
  return [...langs].sort();
}

/**
 * Sérialise déterministiquement la liste de questions au format v3
 * exposé aux clients. Préserve l'ordre des questions (tri par id côté
 * lecture Firestore). Ne contient aucun timestamp pour la reproductibilité
 * du hash.
 */
function buildPackPayload(
  packId: string,
  packVersion: number,
  questions: QuestionDoc[]
): Record<string, unknown> {
  return {
    format_version: PACK_FORMAT_VERSION,
    pack_id: packId,
    pack_version: packVersion,
    langs: detectLangs(questions),
    default_lang: DEFAULT_LANG,
    min_app_version: MIN_APP_VERSION,
    count: questions.length,
    devinettes: questions,
  };
}

export const publishPack = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (req) => {
    const auth = req.auth;
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }
    requireAdmin(auth.token as Record<string, unknown>);

    const packId = req.data?.packId as string | undefined;
    if (!packId || typeof packId !== "string" || !/^[a-z][a-z0-9_]{1,40}$/.test(packId)) {
      throw new HttpsError(
        "invalid-argument",
        "packId manquant ou invalide (regex /^[a-z][a-z0-9_]{1,40}$/)."
      );
    }

    const db = getFirestore();
    const storage = getStorage();

    const stateRef = db.collection("content_packs").doc(packId);
    const stateSnap = await stateRef.get();
    if (!stateSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        `Le doc content_packs/${packId} n'existe pas — crée-le dans le ` +
          `backoffice avant de publier.`
      );
    }
    const state = stateSnap.data() ?? {};
    const currentVersion = (state.current_version as number | undefined) ?? 0;
    const nextVersion = currentVersion + 1;

    // Récupération des questions, triées par id pour déterminisme.
    const questionsSnap = await stateRef
      .collection("questions")
      .orderBy("id")
      .get();
    if (questionsSnap.empty) {
      throw new HttpsError(
        "not-found",
        `Aucune question trouvée pour le pack ${packId}.`
      );
    }

    const questions: QuestionDoc[] = questionsSnap.docs.map((d) => {
      const q = d.data() as Partial<QuestionDoc>;
      return {
        id: q.id ?? d.id,
        pack: q.pack ?? packId,
        country: q.country ?? "ci",
        answer: q.answer ?? "",
        answer_normalized: q.answer_normalized ?? "",
        letters_pool: Array.isArray(q.letters_pool) ? q.letters_pool : [],
        riddle: (q.riddle ?? {}) as Record<string, string>,
        explanation: (q.explanation ?? {}) as Record<string, string>,
        difficulty: q.difficulty ?? 3,
        estimated_time_s: q.estimated_time_s ?? 30,
        tags: Array.isArray(q.tags) ? q.tags : [],
        format_version: q.format_version ?? PACK_FORMAT_VERSION,
      };
    });

    // Build payload + hash + gzip.
    const payload = buildPackPayload(packId, nextVersion, questions);
    const encoded = Buffer.from(JSON.stringify(payload), "utf8");
    const hash = createHash("sha256").update(encoded).digest("hex");
    // Le client vérifie le hash après gunzip → hash du JSON exposé.
    const gz = gzipSync(encoded);

    const storagePath = `packs/v2/${packId}/${packId}-v${nextVersion}.json.gz`;
    const file = storage.bucket().file(storagePath);
    await file.save(gz, {
      contentType: "application/json",
      metadata: {
        contentEncoding: "gzip",
        cacheControl: "public, max-age=86400",
        metadata: {
          hashSha256: hash,
          packVersion: String(nextVersion),
          publishedBy: auth.uid,
        },
      },
    });

    const bucketName = storage.bucket().name;
    const downloadUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucketName}` +
      `/o/${encodeURIComponent(storagePath)}?alt=media`;

    // Préservation explicite des champs `image_*` (uploadés via backoffice).
    // On les ré-écrit identiques pour garantir qu'un futur set merge:true
    // ne les écrase pas par accident, et on n'inclut pas le champ s'il
    // est absent (évite d'écrire `undefined` dans Firestore).
    const imagePreserved: Record<string, unknown> = {};
    if (typeof state.image_url === "string") {
      imagePreserved.image_url = state.image_url;
    }
    if (typeof state.image_path === "string") {
      imagePreserved.image_path = state.image_path;
    }
    if (state.image_updated_at) {
      imagePreserved.image_updated_at = state.image_updated_at;
    }
    if (typeof state.image_hash === "string") {
      imagePreserved.image_hash = state.image_hash;
    }

    await stateRef.set(
      {
        pack: packId,
        current_version: nextVersion,
        format_version: PACK_FORMAT_VERSION,
        hash_sha256: hash,
        size_bytes: gz.length,
        count: questions.length,
        storage_path: storagePath,
        download_url: downloadUrl,
        min_app_version: MIN_APP_VERSION,
        langs: detectLangs(questions),
        default_lang: DEFAULT_LANG,
        enabled: state.enabled ?? true,
        last_published_at: FieldValue.serverTimestamp(),
        last_published_by: auth.uid,
        updated_at: FieldValue.serverTimestamp(),
        ...imagePreserved,
      },
      { merge: true }
    );

    // Garantit la présence du pack dans l'index global.
    await db
      .collection("content_index")
      .doc("global")
      .set(
        {
          packs: FieldValue.arrayUnion(packId),
          min_format_version: PACK_FORMAT_VERSION,
        },
        { merge: true }
      );

    logger.info(
      `publishPack[${packId}]: v${nextVersion} publié ` +
        `(${questions.length} questions, ${gz.length}B, hash=${hash.slice(0, 12)}…)`
    );

    return {
      success: true,
      version: nextVersion,
      count: questions.length,
      hash,
      sizeBytes: gz.length,
      storagePath,
    };
  }
);

// Export interne pour les tests unitaires (payload builder pur).
export const _internals = { buildPackPayload, detectLangs };
