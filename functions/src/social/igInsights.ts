/**
 * Statistiques Instagram pour le tableau de bord (callable, admin/propriétaire).
 * Lit le compte + les médias récents via l'API Instagram (token en secret).
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";

const IG_ACCESS_TOKEN = defineSecret("INSTAGRAM_SOCIAL_TOKEN");
const IG_USER_ID = defineString("IG_USER_ID", { default: "17841423397309250" });
const IG_GRAPH_HOST = defineString("IG_GRAPH_HOST", { default: "graph.instagram.com" });
const IG_GRAPH_VERSION = defineString("IG_GRAPH_VERSION", { default: "v21.0" });

const OWNER_EMAIL = "arnaudkossea@gmail.com";

function assertOwner(auth: { token?: Record<string, unknown> } | undefined): void {
  const t = auth?.token ?? {};
  const ok = t["role"] === "admin" || (t["email"] === OWNER_EMAIL && t["email_verified"] === true);
  if (!ok) throw new HttpsError("permission-denied", "Accès réservé au propriétaire de la page.");
}

async function igGet(path: string, params: Record<string, string>): Promise<Record<string, unknown>> {
  const base = `https://${IG_GRAPH_HOST.value()}/${IG_GRAPH_VERSION.value()}`;
  const qs = new URLSearchParams({ ...params, access_token: IG_ACCESS_TOKEN.value() });
  const res = await fetch(`${base}/${path}?${qs.toString()}`);
  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) throw new Error(`IG API ${path} → ${res.status}: ${JSON.stringify(json)}`);
  return json;
}

export const igInsights = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    secrets: [IG_ACCESS_TOKEN],
  },
  async (req) => {
    assertOwner(req.auth);
    const uid = IG_USER_ID.value();
    let account: Record<string, unknown> = {};
    let media: unknown[] = [];
    try {
      account = await igGet("me", {
        fields: "username,followers_count,follows_count,media_count,profile_picture_url",
      });
    } catch (e) {
      account = { error: (e as Error).message };
    }
    try {
      const r = await igGet(`${uid}/media`, {
        fields:
          "id,caption,media_type,media_url,thumbnail_url,permalink,timestamp,like_count,comments_count",
        limit: "30",
      });
      media = (r["data"] as unknown[]) ?? [];
    } catch (e) {
      media = [];
    }
    return { account, media, fetchedAt: new Date().toISOString() };
  },
);
