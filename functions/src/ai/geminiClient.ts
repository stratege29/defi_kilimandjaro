/**
 * Client Google Gemini (Pack Creator) — génération structurée + grounding web.
 *
 * Cible « quasi gratuit » : `gemini-2.5-flash` (free tier AI Studio). Le cron
 * lent (1 lot / 2 min) reste sous les quotas free tier. estUsd calculé aux
 * tarifs payants Flash (≈ 0 sur free tier) pour donner un ordre de grandeur.
 *
 * Clé en secret Firebase : GEMINI_API_KEY.
 */
import { GoogleGenAI } from "@google/genai";
import { defineSecret } from "firebase-functions/params";
import { type AiUsage } from "./usage";
import { type SystemBlock } from "./claudeClient";

export const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
export const GEMINI_MODEL = "gemini-2.5-flash";

/** Tarifs indicatifs Flash ($/Mtok) : input 0.30, output 2.50, cache-read 0.075. */
function estimateUsd(input: number, output: number, cacheRead: number): number {
  return (input * 0.3 + output * 2.5 + cacheRead * 0.075) / 1_000_000;
}

type GenResponse = {
  text?: string;
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    thoughtsTokenCount?: number;
    cachedContentTokenCount?: number;
  };
  candidates?: Array<{
    groundingMetadata?: {
      groundingChunks?: Array<{ web?: { uri?: string; title?: string } }>;
    };
  }>;
};

function usageFrom(res: GenResponse): AiUsage {
  const u = res.usageMetadata ?? {};
  const input = u.promptTokenCount ?? 0;
  const output = (u.candidatesTokenCount ?? 0) + (u.thoughtsTokenCount ?? 0);
  const cacheRead = u.cachedContentTokenCount ?? 0;
  return {
    inputTokens: input,
    outputTokens: output,
    cacheReadInputTokens: cacheRead,
    cacheCreationInputTokens: 0,
    estUsd: estimateUsd(input, output, cacheRead),
  };
}

let _client: GoogleGenAI | null = null;
function client(): GoogleGenAI {
  if (!_client) _client = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  return _client;
}

/** Convertit notre JSON-Schema (sous-ensemble) au format Schema de Gemini. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function toGeminiSchema(s: any): any {
  const t = s?.type;
  if (t === "object") {
    const props: Record<string, unknown> = {};
    for (const k of Object.keys(s.properties ?? {})) {
      props[k] = toGeminiSchema(s.properties[k]);
    }
    return { type: "OBJECT", properties: props, required: s.required ?? [] };
  }
  if (t === "array") return { type: "ARRAY", items: toGeminiSchema(s.items) };
  if (t === "string") {
    if (Array.isArray(s.enum)) {
      return { type: "STRING", format: "enum", enum: s.enum };
    }
    return { type: "STRING" };
  }
  // Gemini ne contraint pas les enums d'entiers : on laisse `INTEGER` libre et
  // on valide la plage (ex. difficulty ∈ 1..4) côté serveur (drainPackJobs).
  if (t === "integer") return { type: "INTEGER" };
  if (t === "number") return { type: "NUMBER" };
  if (t === "boolean") return { type: "BOOLEAN" };
  return { type: "STRING" };
}

function parseJson(text: string): unknown {
  const t = (text ?? "").trim();
  try {
    return JSON.parse(t);
  } catch {
    const m = t.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (m) return JSON.parse(m[1].trim());
    const a = t.indexOf("{");
    const b = t.lastIndexOf("}");
    if (a >= 0 && b > a) return JSON.parse(t.slice(a, b + 1));
    throw new Error("Réponse Gemini sans JSON parsable.");
  }
}

/** Génération structurée (JSON Schema → responseSchema). Pas d'outils. */
export async function geminiStructured<T>(params: {
  system: SystemBlock[];
  user: string;
  schema: Record<string, unknown>;
  effort?: "low" | "medium" | "high";
}): Promise<{ data: T; usage: AiUsage }> {
  const sys = params.system.map((b) => b.text).join("\n\n");
  const thinkingBudget = params.effort === "low" ? 0 : -1; // -1 = dynamique
  const res = (await client().models.generateContent({
    model: GEMINI_MODEL,
    contents: params.user,
    config: {
      systemInstruction: sys,
      responseMimeType: "application/json",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      responseSchema: toGeminiSchema(params.schema) as any,
      thinkingConfig: { thinkingBudget },
    },
  })) as GenResponse;
  return { data: parseJson(res.text ?? "") as T, usage: usageFrom(res) };
}

/** Appel avec Google Search grounding → texte + sources (pas de JSON strict). */
export async function geminiGrounded(
  system: string,
  user: string
): Promise<{ text: string; sources: Array<{ title: string; url: string }>; usage: AiUsage }> {
  const res = (await client().models.generateContent({
    model: GEMINI_MODEL,
    contents: user,
    config: {
      systemInstruction: system,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      tools: [{ googleSearch: {} }] as any,
    },
  })) as GenResponse;
  const chunks = res.candidates?.[0]?.groundingMetadata?.groundingChunks ?? [];
  const sources = chunks
    .map((c) => ({ title: c.web?.title ?? "", url: c.web?.uri ?? "" }))
    .filter((s) => s.url);
  return { text: res.text ?? "", sources, usage: usageFrom(res) };
}
