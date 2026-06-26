/**
 * Prompts système + JSON Schemas (sortie structurée) pour le Pack Creator.
 *
 * Contexte produit : Kilimandjaro est un Word Connect culturel africain
 * (focus Côte d'Ivoire). Une « question » = une réponse en UN seul mot (4-12
 * lettres) + une énigme (`riddle`) qui ne contient pas la réponse + une
 * explication culturelle. Difficulté 1 (facile, mot court) → 4 (difficile).
 */

/** Préfixe system stable (mis en cache prompt) commun à toutes les générations. */
export function packSystemPrefix(topic: string, tagWhitelist: string[]): string {
  const tags =
    tagWhitelist.length > 0
      ? `Tags autorisés (utilise UNIQUEMENT ceux-ci) : ${tagWhitelist.join(", ")}.`
      : "Choisis 1 à 3 tags courts en minuscules (thèmes) par question.";
  return [
    "Tu es un expert du jeu de lettres culturel ivoirien « Kilimandjaro ».",
    `Sujet du pack à produire : « ${topic} ».`,
    "",
    "Règles ABSOLUES pour chaque question :",
    "- `answer` : UN SEUL mot, 4 à 12 lettres, MAJUSCULES, sans espace ni tiret,",
    "  sans chiffre. Accents tolérés (É È À Ï Ç…). Pertinent culturellement.",
    "- `riddleFr` : énigme/devinette en français qui fait deviner la réponse,",
    "  SANS jamais contenir le mot réponse (ni une de ses formes évidentes).",
    "- `explanationFr` : 1 à 2 phrases factuelles expliquant la réponse.",
    "- `difficulty` : 1 (facile, mot court/connu) à 4 (difficile, mot long/pointu).",
    `- ${tags}`,
    "- `country` : code ISO 2 lettres (par défaut « ci »).",
    "",
    "Équilibrage : respecte STRICTEMENT le quota par niveau de difficulté demandé.",
    "Authenticité : pas d'invention. Faits réels, vérifiables. Pas de contenu",
    "sensible (sexuel, haineux, insultes). Évite les doublons de réponses.",
  ].join("\n");
}

/** Schéma de sortie : plan de recherche. */
export function planSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      subThemes: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            name: { type: "string" },
            targetCount: { type: "integer" },
            tags: { type: "array", items: { type: "string" } },
          },
          required: ["name", "targetCount", "tags"],
        },
      },
      difficultyDistribution: {
        type: "object",
        additionalProperties: false,
        properties: {
          "1": { type: "integer" },
          "2": { type: "integer" },
          "3": { type: "integer" },
          "4": { type: "integer" },
        },
        required: ["1", "2", "3", "4"],
      },
      rationale: { type: "string" },
    },
    required: ["subThemes", "difficultyDistribution", "rationale"],
  };
}

export function planUserPrompt(topic: string, targetTotal: number): string {
  return [
    `Conçois un plan de recherche pour un pack de ${targetTotal} questions sur « ${topic} ».`,
    "Découpe en 4 à 10 sous-thèmes complémentaires (chacun avec un targetCount).",
    `La somme des targetCount DOIT faire ${targetTotal}.`,
    "Propose une répartition par niveau de difficulté (clés 1,2,3,4) dont la somme",
    `DOIT aussi faire ${targetTotal} (ex. ~30% niveau 1, 30% niveau 2, 25% niveau 3, 15% niveau 4).`,
    "Donne un court `rationale` (2-3 phrases) sur l'équilibrage.",
  ].join("\n");
}

/** Schéma de sortie : un lot de questions générées. */
export function batchSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      questions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            answer: { type: "string" },
            country: { type: "string" },
            riddleFr: { type: "string" },
            explanationFr: { type: "string" },
            difficulty: { type: "integer", enum: [1, 2, 3, 4] },
            subTheme: { type: "string" },
            tags: { type: "array", items: { type: "string" } },
          },
          required: [
            "answer",
            "country",
            "riddleFr",
            "explanationFr",
            "difficulty",
            "subTheme",
            "tags",
          ],
        },
      },
    },
    required: ["questions"],
  };
}

/**
 * Prompt utilisateur (volatile) : quota restant par niveau + réponses interdites.
 * Placé APRÈS le préfixe caché pour préserver le cache prompt.
 */
export function batchUserPrompt(args: {
  count: number;
  remainingByDifficulty: Record<string, number>;
  forbiddenAnswers: string[];
  subThemes: Array<{ name: string; tags: string[] }>;
}): string {
  const quota = Object.entries(args.remainingByDifficulty)
    .filter(([, n]) => n > 0)
    .map(([d, n]) => `niveau ${d}: ${n}`)
    .join(", ");
  const themes = args.subThemes
    .map((s) => `- ${s.name} (tags: ${s.tags.join(", ")})`)
    .join("\n");
  const forbidden =
    args.forbiddenAnswers.length > 0
      ? `Réponses DÉJÀ utilisées (à NE PAS réutiliser) : ${args.forbiddenAnswers.join(", ")}.`
      : "Aucune réponse interdite pour l'instant.";
  return [
    `Génère exactement ${args.count} questions NOUVELLES.`,
    `Respecte le quota restant par niveau de difficulté : ${quota || "libre"}.`,
    "Répartis sur ces sous-thèmes (choisis ceux encore peu couverts) :",
    themes,
    forbidden,
    "Renvoie l'objet { questions: [...] }.",
  ].join("\n");
}

/** Schéma de sortie : vérification/sourcing d'un lot de candidats. */
export function verifySchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      results: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            index: { type: "integer" },
            verdict: { type: "string", enum: ["pass", "uncertain", "fail"] },
            confidence: { type: "number" },
            notes: { type: "string" },
            sources: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  title: { type: "string" },
                  url: { type: "string" },
                },
                required: ["title", "url"],
              },
            },
          },
          required: ["index", "verdict", "confidence", "notes", "sources"],
        },
      },
    },
    required: ["results"],
  };
}

export function verifySystemPrompt(): string {
  return [
    "Tu es vérificateur factuel pour un jeu de culture ivoirienne.",
    "Pour chaque question (answer + riddleFr + explanationFr), vérifie via la",
    "recherche web que la réponse et l'explication sont factuellement exactes et",
    "que l'énigme désigne bien cette réponse.",
    "Rends un verdict par index : `pass` (exact, sourcé), `uncertain` (douteux),",
    "`fail` (faux/non vérifiable). Donne 1 à 3 sources (titre + URL réelles) et",
    "une note courte. Sois strict : en cas de doute → `uncertain`.",
  ].join("\n");
}

export function verifyUserPrompt(
  items: Array<{ index: number; answer: string; riddleFr: string; explanationFr: string }>
): string {
  const list = items
    .map(
      (q) =>
        `#${q.index} — réponse: ${q.answer} | énigme: ${q.riddleFr} | explication: ${q.explanationFr}`
    )
    .join("\n");
  return [
    "Vérifie chacune de ces questions et renvoie { results: [...] } avec un objet par index :",
    list,
  ].join("\n");
}
