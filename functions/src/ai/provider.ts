/**
 * Sélecteur de provider IA pour le Pack Creator.
 *
 * Moteur par défaut : **Gemini 2.5 Flash** (free tier) pour la génération.
 * La **vérification** est TOUJOURS Wikipedia→grounding (Gemini) quel que soit
 * le moteur : `PACK_AI_ENGINE=claude` ne change QUE la génération, donc le
 * moteur claude nécessite AUSSI `GEMINI_API_KEY`.
 * Moteur premium optionnel : Claude Opus 4.8 via `PACK_AI_ENGINE=claude`
 * (nécessite d'ajouter ANTHROPIC_API_KEY à AI_SECRETS + poser le secret).
 *
 * Les CFs qui génèrent attachent `AI_SECRETS`.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { type AiUsage } from "./usage";
import { type SystemBlock, callStructured } from "./claudeClient";
import { GEMINI_API_KEY, geminiStructured } from "./geminiClient";
import {
  verifyHybrid,
  verifyWikipediaOnly,
  type VerifyItem,
  type VerifyResult,
} from "./wikiVerify";

export const PACK_AI_ENGINE = defineString("PACK_AI_ENGINE", {
  default: "gemini",
});

/**
 * Secrets à attacher aux CFs IA. Par défaut : GEMINI uniquement (stack gratuit).
 * Pour activer le moteur Claude : ajouter le nom de secret "ANTHROPIC_API_KEY"
 * ici (v2 accepte les chaînes), puis `firebase functions:secrets:set` + redéployer.
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
    // Le secret Claude n'est attaché (donc injecté en env) que si on l'a ajouté
    // à AI_SECRETS. On détecte son absence et on rend l'erreur actionnable
    // plutôt que de laisser l'SDK échouer sans clé.
    if (!process.env.ANTHROPIC_API_KEY) {
      throw new HttpsError(
        "failed-precondition",
        "PACK_AI_ENGINE=claude mais ANTHROPIC_API_KEY n'est pas attaché : " +
          "ajoutez ANTHROPIC_API_KEY à AI_SECRETS (provider.ts), posez le secret " +
          "et redéployez, ou repassez PACK_AI_ENGINE=gemini."
      );
    }
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

/**
 * Vérification + sourcing.
 * - normal : Wikipedia d'abord, puis grounding Gemini (qualité max).
 * - eco    : Wikipedia uniquement, 0 appel Gemini (économie de quota).
 */
export async function verifyBatch(
  items: VerifyItem[],
  eco = false
): Promise<{ results: VerifyResult[]; usage: AiUsage; calls: number }> {
  return eco ? verifyWikipediaOnly(items) : verifyHybrid(items);
}
