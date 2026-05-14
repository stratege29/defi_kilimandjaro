/**
 * Filtre profanité minimal (FR + EN + Nouchi). Liste courte par design —
 * doit être étendue par Remote Config (`profanity_extra_words`) sans
 * redéploiement.
 *
 * Limites assumées : pas un anti-toxic complet. Pour un signal plus solide,
 * brancher Perspective API ou une LLM call dans `curateSubmission` (cf.
 * §F.5 du plan).
 */
const BASE_WORDS: ReadonlyArray<string> = [
  // FR
  "merde", "putain", "salope", "connard", "enculé", "enfoiré", "pute",
  // EN
  "fuck", "shit", "bitch", "asshole", "cunt",
  // Nouchi (sample)
  "gnata",
];

export interface ProfanityResult {
  flagged: boolean;
  hits: string[];
}

export function checkProfanity(
  text: string,
  extra: ReadonlyArray<string> = []
): ProfanityResult {
  const lower = text.toLowerCase();
  const hits: string[] = [];
  for (const w of [...BASE_WORDS, ...extra]) {
    if (!w) continue;
    const re = new RegExp(`\\b${w.toLowerCase()}\\b`, "i");
    if (re.test(lower)) hits.push(w);
  }
  return { flagged: hits.length > 0, hits };
}
