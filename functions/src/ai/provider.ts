/**
 * Sélecteur de provider IA pour le Pack Creator.
 *
 * Moteur par défaut : **Gemini 2.5 Flash** (free tier) pour la génération +
 * vérification hybride Wikipedia→grounding → coût quasi nul.
 * Moteur premium optionnel : Claude Opus 4.8 (qualité max, payant) via le
 * paramètre `PACK_AI_ENGINE=claude` (nécessite d'ajouter ANTHROPIC_API_KEY à
 * AI_SECRETS et de poser le secret).
 *
 * Les CFs qui génèrent attachent `AI_SECRETS`.
 */
import { defineString } from "firebase-functions/params";
import { type AiUsage } from "./usage";
import { type SystemBlock, callStructured } from "./claudeClient";
import { GEMINI_API_KEY, geminiStructured } from "./geminiClient";
import { verifyHybrid, type VerifyItem, type VerifyResult } from "./wikiVerify";

export const PACK_AI_ENGINE = defineString("PACK_AI_ENGINE", {
  default: "gemini",
});

/**
 * Secrets à attacher aux CFs IA. Par défaut : GEMINI uniquement (stack gratuit).
 * Pour activer le moteur Claude : ajouter ANTHROPIC_API_KEY ici + poser le secret.
 */
export const AI_SECRETS = [GEMINI_API_KEY];

export type { VerifyItem, VerifyResult };

/** Génération / plan structuré (route selon le moteur configuré). */
export async function generateStructured<T>(params: {
  system: SystemBlock[];
  user: string;
  schema: Record<string, unknown>;
  effort?: "low" | "medium" | "high";
  maxTokens?: number;
}): Promise<{ data: T; usage: AiUsage }> {
  if (PACK_AI_ENGINE.value() === "claude") {
    return callStructured<T>({
      system: params.system,
      user: params.user,
      schema: params.schema,
      effort: params.effort,
      maxTokens: params.maxTokens,
    });
  }
  return geminiStructured<T>({
    system: params.system,
    user: params.user,
    schema: params.schema,
    effort: params.effort,
  });
}

/** Vérification + sourcing (Wikipedia d'abord, puis grounding). */
export async function verifyBatch(
  items: VerifyItem[]
): Promise<{ results: VerifyResult[]; usage: AiUsage }> {
  return verifyHybrid(items);
}
