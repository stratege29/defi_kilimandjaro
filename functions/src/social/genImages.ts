/**
 * Génération d'images de marque via OpenAI (gpt-image-1), côté serveur.
 * Style signature cohérent. Stocke sur Storage (URL publique) et renvoie les URLs.
 * Clé OpenAI en secret Firebase : OPENAI_API_KEY.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getStorage } from "firebase-admin/storage";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { randomUUID } from "crypto";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

const STYLE =
  "Modern editorial vector illustration with a subtle risograph grain and warm golden-hour " +
  "light. Cohesive brand palette: deep night green (#0C1712), warm gold (#E9B949), terracotta " +
  "and cream. Subtle African textile patterns (kente, adinkra) softly in the background. " +
  "Authentic West African mood, premium, warm and optimistic. Bold simple shapes, clean " +
  "composition, vertical framing with calm empty space toward the bottom. No text, no letters, " +
  "no logo, no watermark.";

const SPECS: Record<string, string> = {
  abidjan: "Aerial view of Abidjan skyline and the Ébrié lagoon at golden hour, Plateau towers reflecting on the water",
  dakar: "Coastal Dakar Senegal at sunset, the African Renaissance Monument on a green hill above the ocean",
  lagos: "Lagos Nigeria skyline at dusk over the lagoon, dense modern towers with warm lit windows",
  marrakech: "Marrakech medina and the Koutoubia minaret at sunset, warm red city, palm trees",
  yamoussoukro: "The Basilica of Our Lady of Peace in Yamoussoukro, grand white dome and colonnade under a soft sky",
  kilimandjaro: "Mount Kilimanjaro snow-capped peak above the savanna at dawn, a lone acacia tree in the foreground",
  baobab: "A lone majestic baobab tree silhouette at sunset over the African savanna, big warm sun",
  balafon: "Close-up of a traditional African balafon, wooden xylophone with gourd resonators and two mallets",
  masque: "A stylized Senufo Ivorian ceremonial mask, frontal symmetrical, elegant lighting",
  attieke: "An appetizing plate of attiéké, Ivorian fermented cassava couscous, with grilled fish, tomato and onion, top-down",
  alloco: "An appetizing plate of alloco, Ivorian fried sweet plantains with spicy onion sauce, top-down",
  player: "A joyful young West African person smiling while playing a word puzzle game on a smartphone, cozy warm light",
  friends: "A group of West African friends laughing together around a smartphone, warm celebratory mood",
  duel: "Two climbers racing up opposite slopes of a single snowy peak toward a flag at the summit, sunrise",
};

function assertOwner(auth: { token?: Record<string, unknown> } | undefined): void {
  const t = auth?.token ?? {};
  const ok = t["role"] === "admin" || (t["email"] === "arnaudkossea@gmail.com" && t["email_verified"] === true);
  if (!ok) throw new HttpsError("permission-denied", "Accès réservé au propriétaire.");
}

async function generateOne(key: string, quality: string): Promise<string> {
  const subject = SPECS[key];
  if (!subject) throw new Error(`Sujet inconnu: ${key}`);
  const res = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY.value()}`,
    },
    body: JSON.stringify({
      model: "gpt-image-1",
      prompt: `${subject}. ${STYLE}`,
      size: "1024x1536",
      quality,
      n: 1,
    }),
  });
  const json = (await res.json()) as { data?: { b64_json?: string }[]; error?: { message?: string } };
  if (!res.ok || !json.data?.[0]?.b64_json) {
    throw new Error(`OpenAI ${res.status}: ${JSON.stringify(json.error ?? json)}`);
  }
  const buffer = Buffer.from(json.data[0].b64_json as string, "base64");
  const token = randomUUID();
  const dest = `social/ai/${key}.png`;
  const bucket = getStorage().bucket();
  await bucket.file(dest).save(buffer, {
    metadata: { contentType: "image/png", metadata: { firebaseStorageDownloadTokens: token } },
  });
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
  await getFirestore().collection("ai_images").doc(key).set(
    { key, subject, url, createdAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return url;
}

/** Génère une ou plusieurs images IA (propriétaire/admin). req.data.keys = string[] */
export const igGenerateImages = onCall(
  {
    region: "europe-west1",
    enforceAppCheck: false,
    cors: true,
    secrets: [OPENAI_API_KEY],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (req): Promise<{ ok: true; images: { key: string; url: string }[]; subjects: string[] }> => {
    assertOwner(req.auth);
    const quality = (req.data?.quality as string) || "high";
    const keys: string[] = Array.isArray(req.data?.keys) && req.data.keys.length
      ? req.data.keys
      : Object.keys(SPECS);
    const images: { key: string; url: string }[] = [];
    for (const k of keys) {
      const url = await generateOne(k, quality);
      images.push({ key: k, url });
    }
    return { ok: true, images, subjects: Object.keys(SPECS) };
  },
);
