#!/usr/bin/env node
/**
 * Publie un post de la file `instagram_queue` DEPUIS TA MACHINE.
 * Lit Firestore via ADC (gcloud auth application-default login) et publie via
 * l'API Instagram avec le token passé en variable d'environnement.
 *
 * Usage :
 *   IG_ACCESS_TOKEN=ton_token node functions/scripts/publish_now.js --id j01
 *   IG_ACCESS_TOKEN=ton_token node functions/scripts/publish_now.js          # 1er non publié
 *   ... --dry-run    # n'envoie rien, montre ce qui serait publié
 */
const admin = require("firebase-admin");

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "kilimandjaro-dev";
const TOKEN = process.env.IG_ACCESS_TOKEN;
const IG_USER_ID = process.env.IG_USER_ID || "17841423397309250";
const HOST = process.env.GRAPH_HOST || "graph.instagram.com";
const VER = process.env.GRAPH_VERSION || "v21.0";
const BASE = `https://${HOST}/${VER}`;

const args = process.argv.slice(2);
const DRY = args.includes("--dry-run");
const idIdx = args.indexOf("--id");
const WANT_ID = idIdx >= 0 ? args[idIdx + 1] : null;

async function igPost(path, params) {
  const body = new URLSearchParams({ ...params, access_token: TOKEN });
  const res = await fetch(`${BASE}/${path}`, { method: "POST", body });
  const json = await res.json();
  if (!res.ok || !json.id) throw new Error(`POST ${path} → ${res.status}: ${JSON.stringify(json)}`);
  return json;
}
async function igGet(path, params) {
  const qs = new URLSearchParams({ ...params, access_token: TOKEN });
  const res = await fetch(`${BASE}/${path}?${qs}`);
  const json = await res.json();
  if (!res.ok) throw new Error(`GET ${path} → ${res.status}: ${JSON.stringify(json)}`);
  return json;
}
async function waitReady(containerId, tries = 20, delayMs = 3000) {
  for (let i = 0; i < tries; i += 1) {
    const st = await igGet(containerId, { fields: "status_code" });
    if (st.status_code === "FINISHED") return;
    if (st.status_code === "ERROR") throw new Error(`Conteneur en ERROR: ${JSON.stringify(st)}`);
    process.stdout.write(".");
    await new Promise((r) => setTimeout(r, delayMs));
  }
  throw new Error("Conteneur pas prêt à temps.");
}

async function publishImage(url, caption) {
  const c = await igPost(`${IG_USER_ID}/media`, { image_url: url, caption });
  await waitReady(c.id);
  return igPost(`${IG_USER_ID}/media_publish`, { creation_id: c.id });
}
async function publishCarousel(urls, caption) {
  const ids = [];
  for (const u of urls) {
    const child = await igPost(`${IG_USER_ID}/media`, { image_url: u, is_carousel_item: "true" });
    ids.push(child.id);
  }
  const cont = await igPost(`${IG_USER_ID}/media`, { media_type: "CAROUSEL", children: ids.join(","), caption });
  await waitReady(cont.id);
  return igPost(`${IG_USER_ID}/media_publish`, { creation_id: cont.id });
}

async function main() {
  if (!TOKEN) throw new Error("IG_ACCESS_TOKEN manquant (passe-le en variable d'environnement).");
  admin.initializeApp({ projectId: PROJECT });
  const db = admin.firestore();

  let doc;
  if (WANT_ID) {
    doc = await db.collection("instagram_queue").doc(WANT_ID).get();
    if (!doc.exists) throw new Error(`Post '${WANT_ID}' introuvable.`);
  } else {
    const snap = await db.collection("instagram_queue")
      .where("posted", "==", false).orderBy("date", "asc").limit(1).get();
    if (snap.empty) throw new Error("Aucun post non publié.");
    doc = snap.docs[0];
  }

  const item = doc.data();
  console.log(`Post: ${doc.id} · ${item.type} · ${item.date}`);
  console.log(`Légende: ${(item.caption || "").slice(0, 80)}…`);

  if (DRY) {
    console.log("[dry-run] rien publié.");
    return;
  }

  let res;
  if (item.type === "image") res = await publishImage(item.url, item.caption || "");
  else if (item.type === "carousel") res = await publishCarousel(item.urls, item.caption || "");
  else throw new Error(`Type '${item.type}' non géré par ce script (reels = vidéo requise).`);

  await doc.ref.update({
    posted: true,
    postedAt: admin.firestore.FieldValue.serverTimestamp(),
    mediaId: res.id,
  });
  console.log(`\n✅ Publié ! mediaId = ${res.id}`);
  console.log("Va voir sur le compte Instagram @defi_kilimandjaro.");
}

main().catch((e) => { console.error("Erreur:", e.message); process.exit(1); });
