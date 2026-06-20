/**
 * Autopilote Instagram — publication planifiée.
 *
 * Lit la file `instagram_queue` (Firestore) et publie le premier post « dû »
 * (date <= aujourd'hui, non publié), via l'API Instagram. Le token est stocké
 * en secret Firebase (`IG_ACCESS_TOKEN`).
 *
 * Déploiement / config : voir `docs/instagram_cloud_function.md`.
 *
 * Schéma d'un document `instagram_queue/{id}` :
 *   {
 *     date: "2026-06-08",                // yyyy-mm-dd, date de publication souhaitée
 *     type: "image" | "carousel" | "reel",
 *     url?: string,                      // image ou vidéo (type image/reel)
 *     urls?: string[],                   // carrousel (2 à 10)
 *     cover?: string,                    // reel : image de couverture (optionnel)
 *     caption: string,
 *     posted: boolean,                   // false au départ
 *     postedAt?: Timestamp,              // rempli après publication
 *     mediaId?: string                   // id du média publié
 *   }
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { defineSecret, defineString } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { requireAdmin } from "../utils/auth";
import {
  IgConfig,
  publishImage,
  publishCarousel,
  publishReel,
} from "./igClient";

const IG_ACCESS_TOKEN = defineSecret("INSTAGRAM_SOCIAL_TOKEN");
const IG_USER_ID = defineString("IG_USER_ID", { default: "17841423397309250" });
const IG_GRAPH_HOST = defineString("IG_GRAPH_HOST", {
  default: "graph.instagram.com",
});
const IG_GRAPH_VERSION = defineString("IG_GRAPH_VERSION", { default: "v21.0" });

const QUEUE = "instagram_queue";

interface QueueItem {
  date: string;
  type: "image" | "carousel" | "reel";
  url?: string;
  urls?: string[];
  cover?: string;
  caption?: string;
  posted: boolean;
}

function cfgFromParams(): IgConfig {
  return {
    userId: IG_USER_ID.value(),
    token: IG_ACCESS_TOKEN.value(),
    host: IG_GRAPH_HOST.value(),
    version: IG_GRAPH_VERSION.value(),
  };
}

/**
 * Publie le post dû le plus ancien. Retourne l'id du média ou "no-op".
 * Si `force` est vrai, publie le 1ᵉʳ post non publié sans tenir compte de la date
 * (utile pour lancer / tester immédiatement).
 */
async function publishDuePost(force = false): Promise<string> {
  const db = getFirestore();
  const today = new Date().toISOString().slice(0, 10);

  let query = db
    .collection(QUEUE)
    .where("posted", "==", false) as FirebaseFirestore.Query;
  if (!force) {
    query = query.where("date", "<=", today);
  }
  // On récupère un petit lot et on ignore les posts « mosaïque » : ils ne doivent
  // JAMAIS partir à l'unité via l'autopilote (sinon la grille du profil se décale).
  const snap = await query.orderBy("date", "asc").limit(25).get();
  if (snap.empty) {
    logger.info("instagram: aucun post dû aujourd'hui, no-op.");
    return "no-op";
  }
  const doc = snap.docs[0];
  // Mosaïque INTÉGRÉE au planning : si le plus ancien dû est une rangée mosaïque,
  // on publie la RANGÉE entière (3 posts) pour garder l'alignement de la grille,
  // puis le planning reprend normalement les jours suivants.
  const mz = (doc.data() as Record<string, { group: string; row: number }>).mosaic;
  if (mz) {
    const ids = await publishRowOf(mz.group, mz.row);
    logger.info(`instagram: rangée mosaïque ${mz.group} r${mz.row} publiée (${ids.length} posts)`, { ids });
    return ids[0] ?? "no-op";
  }

  const item = doc.data() as QueueItem;
  const cfg = cfgFromParams();
  const caption = item.caption ?? "";

  let result: { id: string };
  if (item.type === "image") {
    if (!item.url) throw new Error(`Post ${doc.id}: 'url' manquante.`);
    result = await publishImage(cfg, item.url, caption);
  } else if (item.type === "carousel") {
    if (!item.urls?.length) throw new Error(`Post ${doc.id}: 'urls' manquantes.`);
    result = await publishCarousel(cfg, item.urls, caption);
  } else if (item.type === "reel") {
    if (!item.url) throw new Error(`Post ${doc.id}: 'url' (vidéo) manquante.`);
    result = await publishReel(cfg, item.url, caption, item.cover);
  } else {
    throw new Error(`Post ${doc.id}: type inconnu '${item.type}'.`);
  }

  await doc.ref.update({
    posted: true,
    postedAt: FieldValue.serverTimestamp(),
    mediaId: result.id,
  });
  logger.info(`instagram: publié ${doc.id} (${item.type})`, {
    mediaId: result.id,
  });
  return result.id;
}

/**
 * Planifié : chaque jour à 19h30 (Europe/Paris), publie le post dû.
 * Pour changer l'heure, ajuste `schedule`. Un seul post par exécution.
 */
export const publishScheduledInstagramPost = onSchedule(
  {
    schedule: "30 19 * * *",
    timeZone: "Europe/Paris",
    region: "europe-west1",
    secrets: [IG_ACCESS_TOKEN],
    timeoutSeconds: 540,
  },
  async () => {
    const snap = await getFirestore().doc("instagram_meta/config").get();
    const cfg = (snap.exists ? snap.data() : {}) as { autopilotEnabled?: boolean };
    if (cfg.autopilotEnabled === false) {
      logger.info("instagram: autopilote en pause, no-op.");
      return;
    }
    // Mosaïque intégrée : publishDuePost publie une rangée mosaïque quand elle est due.
    await publishDuePost();
  },
);

/** Owner/admin guard partagé. */
function assertOwner(auth?: { token?: Record<string, unknown> }): void {
  const t = auth?.token ?? {};
  const ok = t["role"] === "admin" || (t["email"] === "arnaudkossea@gmail.com" && t["email_verified"] === true);
  if (!ok) throw new HttpsError("permission-denied", "Accès réservé au propriétaire.");
}

/**
 * Publie la PROCHAINE rangée d'une mosaïque (3 posts), du bas vers le haut :
 * la rangée non publiée d'indice `row` le plus élevé, dans l'ordre des colonnes.
 * Garantit l'alignement de la grille (toujours par multiples de 3, bas→haut).
 */
/** Publie tous les posts non publiés d'une rangée précise (group, row), ordre des colonnes. */
async function publishRowOf(group: string, row: number): Promise<string[]> {
  const db = getFirestore();
  const snap = await db.collection(QUEUE).where("mosaic.group", "==", group).get();
  const rowDocs = snap.docs
    .filter((d) => {
      const x = d.data() as Record<string, unknown> & { posted?: boolean; mosaic?: { row?: number } };
      return x.posted === false && (x.mosaic?.row ?? -1) === row;
    })
    .sort((a, b) =>
      (((a.data() as Record<string, { col?: number }>).mosaic?.col ?? 0) -
       ((b.data() as Record<string, { col?: number }>).mosaic?.col ?? 0)));
  const ids: string[] = [];
  for (const d of rowDocs) ids.push(await publishOne(d.id));
  return ids;
}

/** Manuel : prochaine rangée d'un groupe = rangée non publiée d'indice le plus élevé (bas). */
async function publishMosaicRow(group: string): Promise<{ count: number; ids: string[]; row: number }> {
  const db = getFirestore();
  const snap = await db.collection(QUEUE).where("mosaic.group", "==", group).get();
  const unposted = snap.docs.filter((d) => (d.data() as QueueItem).posted === false);
  if (!unposted.length) return { count: 0, ids: [], row: -1 };
  let maxRow = -1;
  for (const d of unposted) {
    const r = ((d.data() as Record<string, { row?: number }>).mosaic?.row ?? -1) as number;
    if (r > maxRow) maxRow = r;
  }
  const ids = await publishRowOf(group, maxRow);
  return { count: ids.length, ids, row: maxRow };
}

export const igPublishMosaicRow = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true, secrets: [IG_ACCESS_TOKEN], timeoutSeconds: 540 },
  async (req): Promise<{ ok: true; count: number; ids: string[]; row: number }> => {
    assertOwner(req.auth);
    const group = (req.data?.group as string) || "";
    if (!group) throw new HttpsError("invalid-argument", "group requis.");
    try {
      return { ok: true, ...(await publishMosaicRow(group)) };
    } catch (e) {
      throw new HttpsError("internal", (e as Error).message);
    }
  },
);

/** Active/met en pause l'autopilote quotidien (utile pendant une campagne mosaïque). */
export const igSetAutopilot = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; autopilotEnabled: boolean }> => {
    assertOwner(req.auth);
    const enabled = req.data?.enabled !== false;
    await getFirestore().doc("instagram_meta/config").set({ autopilotEnabled: enabled }, { merge: true });
    return { ok: true, autopilotEnabled: enabled };
  },
);

/**
 * Mode campagne mosaïque : ON => met l'autopilote normal en pause ET active
 * l'auto-publication d'une rangée mosaïque par jour. OFF => rétablit l'autopilote normal.
 */
export const igSetCampaign = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; campaignActive: boolean }> => {
    assertOwner(req.auth);
    // Déprécié : la mosaïque est désormais intégrée au planning auto (publiée à
    // sa date par l'autopilote). On garde le feed en marche, on neutralise l'ancien mode.
    await getFirestore().doc("instagram_meta/config")
      .set({ autopilotEnabled: true, mosaicAuto: false }, { merge: true });
    return { ok: true, campaignActive: false };
  },
);

/**
 * Déclenchement manuel (admin) — pour tester sans attendre l'heure planifiée.
 * Publie immédiatement le post dû le plus ancien.
 */
/** Publie un post précis de la file (par id de document). */
async function publishOne(docId: string): Promise<string> {
  const db = getFirestore();
  const ref = db.collection(QUEUE).doc(docId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error(`Post '${docId}' introuvable.`);
  const item = snap.data() as QueueItem;
  const cfg = cfgFromParams();
  const caption = item.caption ?? "";
  let result: { id: string };
  if (item.type === "image") result = await publishImage(cfg, item.url as string, caption);
  else if (item.type === "carousel") result = await publishCarousel(cfg, item.urls as string[], caption);
  else if (item.type === "reel") result = await publishReel(cfg, item.url as string, caption, item.cover);
  else throw new Error(`Type inconnu '${item.type}'.`);
  await ref.update({ posted: true, postedAt: FieldValue.serverTimestamp(), mediaId: result.id });
  logger.info(`instagram: publié à la demande ${docId}`, { mediaId: result.id });
  return result.id;
}

/** Publie immédiatement un post choisi dans le tableau de bord (propriétaire/admin). */
export const igPublishPost = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    secrets: [IG_ACCESS_TOKEN],
    timeoutSeconds: 300,
  },
  async (req): Promise<{ ok: true; id: string }> => {
    const t = (req.auth?.token ?? {}) as Record<string, unknown>;
    const ok = t["role"] === "admin" || (t["email"] === "arnaudkossea@gmail.com" && t["email_verified"] === true);
    if (!ok) throw new HttpsError("permission-denied", "Accès réservé au propriétaire.");
    const id = (req.data?.id as string) || "";
    if (!id) throw new HttpsError("invalid-argument", "id du post requis.");
    try {
      const mediaId = await publishOne(id);
      return { ok: true, id: mediaId };
    } catch (e) {
      throw new HttpsError("internal", (e as Error).message);
    }
  },
);

export const igPublishDueNow = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    secrets: [IG_ACCESS_TOKEN],
    timeoutSeconds: 300,
  },
  async (req): Promise<{ ok: true; id: string }> => {
    requireAdmin(req.auth);
    const force = req.data?.force === true;
    try {
      const id = await publishDuePost(force);
      return { ok: true, id };
    } catch (e) {
      throw new HttpsError("internal", (e as Error).message);
    }
  },
);
