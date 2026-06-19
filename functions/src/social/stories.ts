/**
 * Stories Instagram — automatisation (image/vidéo 9:16, expire 24 h).
 *
 * File dédiée `instagram_stories/{id}` (séparée du feed pour ne pas polluer la
 * grille) :
 *   { kind, mediaType:"image"|"video", url, storyAt: Timestamp,
 *     posted: boolean, postedAt?, mediaId?, label? }
 *
 * Cadence : un cron 2×/jour (matin + soir, heure d'Abidjan) publie la story
 * « due » la plus ancienne, SI le drapeau `instagram_meta/config.storiesAuto`
 * est à true (OFF par défaut). L'API ne permet ni sticker, ni sondage, ni lien.
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { defineSecret, defineString } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { IgConfig, publishStory } from "./igClient";

const IG_ACCESS_TOKEN = defineSecret("INSTAGRAM_SOCIAL_TOKEN");
const IG_USER_ID = defineString("IG_USER_ID", { default: "17841423397309250" });
const IG_GRAPH_HOST = defineString("IG_GRAPH_HOST", { default: "graph.instagram.com" });
const IG_GRAPH_VERSION = defineString("IG_GRAPH_VERSION", { default: "v21.0" });
const STORIES = "instagram_stories";

function cfg(): IgConfig {
  return { userId: IG_USER_ID.value(), token: IG_ACCESS_TOKEN.value(), host: IG_GRAPH_HOST.value(), version: IG_GRAPH_VERSION.value() };
}
function assertOwner(auth?: { token?: Record<string, unknown> }): void {
  const t = auth?.token ?? {};
  const ok = t["role"] === "admin" || (t["email"] === "arnaudkossea@gmail.com" && t["email_verified"] === true);
  if (!ok) throw new HttpsError("permission-denied", "Accès réservé au propriétaire.");
}

async function publishStoryDoc(docId: string): Promise<string> {
  const ref = getFirestore().collection(STORIES).doc(docId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error(`Story '${docId}' introuvable.`);
  const s = snap.data() as { url?: string; mediaType?: string; posted?: boolean };
  if (s.posted === true) return "already";
  if (!s.url) throw new Error(`Story ${docId}: url manquante.`);
  const res = await publishStory(cfg(), s.url, s.mediaType === "video");
  await ref.update({ posted: true, postedAt: FieldValue.serverTimestamp(), mediaId: res.id });
  logger.info(`stories: publié ${docId}`, { mediaId: res.id });
  return res.id;
}

/** Publie la story due (storyAt <= now) la plus ancienne. Index-free (tri en code). */
async function publishOldestDueStory(force = false): Promise<string> {
  const snap = await getFirestore().collection(STORIES).where("posted", "==", false).get();
  const now = Date.now();
  const due = snap.docs
    .map((d) => ({ id: d.id, at: (d.data().storyAt as { toMillis?: () => number })?.toMillis?.() ?? 0 }))
    .filter((x) => force || x.at <= now)
    .sort((a, b) => a.at - b.at);
  if (!due.length) { logger.info("stories: aucune story due, no-op."); return "no-op"; }
  return publishStoryDoc(due[0].id);
}

/** Cron : 07:30 (énigme) + 13:30 (Coupe du Monde) + 20:30 (réponse), Abidjan.
 *  Publie 1 story due (la plus ancienne) à chaque créneau si storiesAuto=ON. */
export const igPublishDueStories = onSchedule(
  { schedule: "30 7,13,20 * * *", timeZone: "Africa/Abidjan", region: "europe-west1", secrets: [IG_ACCESS_TOKEN], timeoutSeconds: 300 },
  async () => {
    const c = (await getFirestore().doc("instagram_meta/config").get()).data() as { storiesAuto?: boolean } | undefined;
    if (!c || c.storiesAuto !== true) { logger.info("stories: auto OFF, no-op."); return; }
    await publishOldestDueStory();
  },
);

/** Manuel : publie une story précise (id) ou la plus ancienne due (force). */
export const igPublishStoryNow = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true, secrets: [IG_ACCESS_TOKEN], timeoutSeconds: 300 },
  async (req): Promise<{ ok: true; id: string }> => {
    assertOwner(req.auth);
    const id = (req.data?.id as string) || "";
    try {
      const mediaId = id ? await publishStoryDoc(id) : await publishOldestDueStory(true);
      return { ok: true, id: mediaId };
    } catch (e) {
      throw new HttpsError("internal", (e as Error).message);
    }
  },
);

/** Active/désactive l'autopilote stories (indépendant du feed). */
export const igSetStoriesAuto = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; storiesAuto: boolean }> => {
    assertOwner(req.auth);
    const enabled = req.data?.enabled === true;
    await getFirestore().doc("instagram_meta/config").set({ storiesAuto: enabled }, { merge: true });
    return { ok: true, storiesAuto: enabled };
  },
);
