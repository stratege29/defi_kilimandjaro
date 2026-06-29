/**
 * Usage tokens + estimation de coût, partagé entre providers IA (Claude/Gemini).
 */
import { logger } from "firebase-functions/v2";

export type AiUsage = {
  inputTokens: number;
  outputTokens: number;
  cacheReadInputTokens: number;
  cacheCreationInputTokens: number;
  /** Coût estimé en USD (0 sur free tier Gemini). */
  estUsd: number;
};

export const EMPTY_USAGE: AiUsage = {
  inputTokens: 0,
  outputTokens: 0,
  cacheReadInputTokens: 0,
  cacheCreationInputTokens: 0,
  estUsd: 0,
};

export function addUsage(a: AiUsage, b: AiUsage): AiUsage {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
    cacheReadInputTokens: a.cacheReadInputTokens + b.cacheReadInputTokens,
    cacheCreationInputTokens:
      a.cacheCreationInputTokens + b.cacheCreationInputTokens,
    estUsd: a.estUsd + b.estUsd,
  };
}

export function logUsage(label: string, usage: AiUsage): void {
  logger.info(`ai:${label}`, {
    inputTokens: usage.inputTokens,
    outputTokens: usage.outputTokens,
    cacheReadInputTokens: usage.cacheReadInputTokens,
    estUsd: Number(usage.estUsd.toFixed(4)),
  });
}
