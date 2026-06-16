/**
 * Client minimal pour l'API Instagram (content publishing).
 *
 * Voie « Instagram login » : host `graph.instagram.com`, token longue durée.
 * Publication en 2 temps : création d'un conteneur média (URL publique) puis
 * publication. Utilise le `fetch` global de Node 20 (aucune dépendance ajoutée).
 */

export interface IgConfig {
  userId: string;
  token: string;
  host: string; // ex. graph.instagram.com
  version: string; // ex. v21.0
}

export type QueueItemType = "image" | "carousel" | "reel";

function baseUrl(cfg: IgConfig): string {
  return `https://${cfg.host}/${cfg.version}`;
}

async function igPost(
  cfg: IgConfig,
  path: string,
  params: Record<string, string>,
): Promise<{ id: string }> {
  const body = new URLSearchParams({ ...params, access_token: cfg.token });
  const res = await fetch(`${baseUrl(cfg)}/${path}`, { method: "POST", body });
  const json = (await res.json()) as { id?: string; error?: unknown };
  if (!res.ok || !json.id) {
    throw new Error(`IG API POST ${path} → ${res.status}: ${JSON.stringify(json)}`);
  }
  return { id: json.id };
}

async function igGet(
  cfg: IgConfig,
  path: string,
  params: Record<string, string>,
): Promise<Record<string, unknown>> {
  const qs = new URLSearchParams({ ...params, access_token: cfg.token });
  const res = await fetch(`${baseUrl(cfg)}/${path}?${qs.toString()}`);
  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(`IG API GET ${path} → ${res.status}: ${JSON.stringify(json)}`);
  }
  return json;
}

/** Vérifie le token et retourne l'identité du compte. */
export async function whoami(cfg: IgConfig): Promise<Record<string, unknown>> {
  return igGet(cfg, "me", { fields: "user_id,username" });
}

/** Publie une image simple. */
export async function publishImage(
  cfg: IgConfig,
  imageUrl: string,
  caption: string,
): Promise<{ id: string }> {
  const container = await igPost(cfg, `${cfg.userId}/media`, {
    image_url: imageUrl,
    caption,
  });
  await waitContainerReady(cfg, container.id);
  return igPost(cfg, `${cfg.userId}/media_publish`, { creation_id: container.id });
}

/** Publie un carrousel (2 à 10 images). */
export async function publishCarousel(
  cfg: IgConfig,
  imageUrls: string[],
  caption: string,
): Promise<{ id: string }> {
  const childIds: string[] = [];
  for (const url of imageUrls) {
    const child = await igPost(cfg, `${cfg.userId}/media`, {
      image_url: url,
      is_carousel_item: "true",
    });
    childIds.push(child.id);
  }
  const container = await igPost(cfg, `${cfg.userId}/media`, {
    media_type: "CAROUSEL",
    children: childIds.join(","),
    caption,
  });
  await waitContainerReady(cfg, container.id);
  return igPost(cfg, `${cfg.userId}/media_publish`, { creation_id: container.id });
}

/** Publie un Reel (vidéo 9:16 hébergée publiquement). */
export async function publishReel(
  cfg: IgConfig,
  videoUrl: string,
  caption: string,
  coverUrl?: string,
): Promise<{ id: string }> {
  const params: Record<string, string> = {
    media_type: "REELS",
    video_url: videoUrl,
    caption,
  };
  if (coverUrl) params["cover_url"] = coverUrl;
  const container = await igPost(cfg, `${cfg.userId}/media`, params);
  await waitContainerReady(cfg, container.id);
  return igPost(cfg, `${cfg.userId}/media_publish`, { creation_id: container.id });
}

/** Attend qu'un conteneur vidéo/reel soit FINISHED avant publication. */
async function waitContainerReady(
  cfg: IgConfig,
  containerId: string,
  tries = 30,
  delayMs = 5000,
): Promise<void> {
  for (let i = 0; i < tries; i += 1) {
    const status = await igGet(cfg, containerId, { fields: "status_code" });
    const code = status["status_code"];
    if (code === "FINISHED") return;
    if (code === "ERROR") {
      throw new Error(`Conteneur en ERROR: ${JSON.stringify(status)}`);
    }
    await new Promise((r) => setTimeout(r, delayMs));
  }
  throw new Error("Conteneur média pas prêt dans le temps imparti.");
}
