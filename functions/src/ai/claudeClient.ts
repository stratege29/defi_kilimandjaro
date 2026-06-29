/**
 * Client Anthropic Claude (Pack Creator) — appels structurés + recherche web.
 *
 * Modèle : `claude-opus-4-8` (adaptive thinking, effort réglable). Aucun
 * `temperature`/`top_p`/`budget_tokens` (400 sur Opus 4.8). Streaming +
 * `.finalMessage()` pour éviter les timeouts sur les gros `max_tokens`.
 *
 * Clé : lue depuis `process.env.ANTHROPIC_API_KEY` (résolution par défaut de
 * l'SDK). On N'appelle PAS `defineSecret` au chargement du module : sinon le
 * déploiement du stack gratuit (Gemini) réclamerait ce secret inutilement.
 * Pour le moteur premium claude : ajouter le nom "ANTHROPIC_API_KEY" à
 * AI_SECRETS (provider.ts) et poser le secret.
 *
 * Les types de l'SDK peuvent être en retard sur les champs récents
 * (`output_config`, `web_search_20260209`, thinking adaptatif) : on construit le
 * corps en objet libre et on caste à l'appel — le runtime transmet les champs.
 */
import Anthropic from "@anthropic-ai/sdk";
import { addUsage, EMPTY_USAGE, type AiUsage } from "./usage";

/** Modèle par défaut — voir docs claude-api : ne jamais suffixer de date. */
export const CLAUDE_MODEL = "claude-opus-4-8";

/** Tarifs Opus 4.8 ($/Mtok) : input 5, output 25, cache-write 1h ~10, cache-read ~0.5. */
function estimateUsd(u: {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}): number {
  const inp = u.input_tokens ?? 0;
  const out = u.output_tokens ?? 0;
  const cr = u.cache_read_input_tokens ?? 0;
  const cw = u.cache_creation_input_tokens ?? 0;
  return (inp * 5 + out * 25 + cr * 0.5 + cw * 10) / 1_000_000;
}

function usageFromMessage(msg: { usage?: Record<string, number> }): AiUsage {
  const u = msg.usage ?? {};
  return {
    inputTokens: u.input_tokens ?? 0,
    outputTokens: u.output_tokens ?? 0,
    cacheReadInputTokens: u.cache_read_input_tokens ?? 0,
    cacheCreationInputTokens: u.cache_creation_input_tokens ?? 0,
    estUsd: estimateUsd(u),
  };
}

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    // L'SDK lit ANTHROPIC_API_KEY depuis l'env (injecté si le secret est attaché).
    _client = new Anthropic();
  }
  return _client;
}

/** Bloc system avec cache prompt (préfixe stable, TTL 1h pour survivre au drain). */
export type SystemBlock = { text: string; cache?: boolean };

type CallParams = {
  /** Blocs system : mettre le préfixe stable en premier avec cache=true. */
  system: SystemBlock[];
  /** Contenu utilisateur (volatile : quotas, dédup…). */
  user: string;
  /** JSON Schema strict pour la sortie structurée (sans min/max — validés en code). */
  schema: Record<string, unknown>;
  /** Effort thinking : 'low' pour mécanique, 'high' pour qualité. */
  effort?: "low" | "medium" | "high";
  /** Active l'outil de recherche web serveur (vérification/sourcing). */
  webSearch?: boolean;
  maxTokens?: number;
};

function extractJson(content: Array<{ type: string; text?: string }>): unknown {
  for (const block of content) {
    if (block.type === "text" && typeof block.text === "string") {
      const t = block.text.trim();
      try {
        return JSON.parse(t);
      } catch {
        // Tolère un éventuel fence ```json … ```
        const m = t.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (m) {
          try {
            return JSON.parse(m[1].trim());
          } catch {
            /* continue */
          }
        }
      }
    }
  }
  throw new Error("Réponse Claude sans JSON parsable.");
}

/**
 * Appel Claude → sortie structurée validée par JSON Schema.
 * Gère `pause_turn` (boucle recherche web serveur, max 6 tours).
 * Retourne les données parsées + l'usage tokens cumulé.
 */
export async function callStructured<T>(
  params: CallParams
): Promise<{ data: T; usage: AiUsage }> {
  const c = client();
  const systemBlocks = params.system.map((b) =>
    b.cache
      ? {
          type: "text",
          text: b.text,
          cache_control: { type: "ephemeral", ttl: "1h" },
        }
      : { type: "text", text: b.text }
  );

  const tools = params.webSearch
    ? [{ type: "web_search_20260209", name: "web_search" }]
    : undefined;

  const messages: Array<{ role: string; content: unknown }> = [
    { role: "user", content: params.user },
  ];

  let usage = EMPTY_USAGE;
  let lastContent: Array<{ type: string; text?: string }> = [];

  // Boucle pause_turn (la recherche web serveur peut s'interrompre).
  for (let turn = 0; turn < 6; turn++) {
    const body = {
      model: CLAUDE_MODEL,
      max_tokens: params.maxTokens ?? 16000,
      thinking: { type: "adaptive" },
      output_config: {
        effort: params.effort ?? "high",
        format: { type: "json_schema", schema: params.schema },
      },
      ...(tools ? { tools } : {}),
      system: systemBlocks,
      messages,
    };

    // Streaming + finalMessage (protection timeout).
    const stream = (c.messages.stream as unknown as (b: unknown) => {
      finalMessage: () => Promise<{
        content: Array<{ type: string; text?: string }>;
        stop_reason?: string;
        usage?: Record<string, number>;
      }>;
    })(body);
    const msg = await stream.finalMessage();

    usage = addUsage(usage, usageFromMessage(msg));
    lastContent = msg.content;

    if (msg.stop_reason === "pause_turn") {
      // Re-soumet l'historique pour que le serveur reprenne la recherche.
      messages.push({ role: "assistant", content: msg.content });
      continue;
    }
    break;
  }

  return { data: extractJson(lastContent) as T, usage };
}
