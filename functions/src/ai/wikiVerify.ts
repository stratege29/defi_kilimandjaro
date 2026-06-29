/**
 * Vérification hybride « quasi gratuit » : Wikipedia (FR) d'abord, puis Google
 * Search grounding (Gemini) en repli pour les candidats sans source fiable.
 *
 * 1. Pour chaque réponse, on récupère le résumé de l'article fr.wikipedia.
 * 2. Un appel Gemini structuré confronte (réponse + énigme + explication) au
 *    résumé Wikipedia → verdict + confiance + note (source = l'URL Wikipedia).
 * 3. Repli grounding : les candidats restés `uncertain` sans source passent par
 *    un appel Gemini + Google Search ; on récupère verdict + sources web.
 *
 * Wikipedia = gratuit/illimité ; grounding free tier = quotas généreux.
 */
import { geminiStructured, geminiGrounded } from "./geminiClient";
import { addUsage, EMPTY_USAGE, type AiUsage } from "./usage";
import { verifySchema } from "./prompts";

const WIKI_UA = "KilimandjaroPackCreator/1.0 (admin content pipeline)";

export type VerifyItem = {
  index: number;
  answer: string;
  riddleFr: string;
  explanationFr: string;
};
export type VerifyResult = {
  index: number;
  verdict: "pass" | "uncertain" | "fail";
  confidence: number;
  notes: string;
  sources: Array<{ title: string; url: string }>;
};

type WikiEvidence = { extract: string; url: string } | null;

async function wikiLookup(term: string): Promise<WikiEvidence> {
  try {
    const searchUrl =
      "https://fr.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=1&srsearch=" +
      encodeURIComponent(term);
    const s = await fetch(searchUrl, { headers: { "User-Agent": WIKI_UA } });
    if (!s.ok) return null;
    const sj = (await s.json()) as {
      query?: { search?: Array<{ title?: string }> };
    };
    const title = sj.query?.search?.[0]?.title;
    if (!title) return null;

    const sumUrl =
      "https://fr.wikipedia.org/api/rest_v1/page/summary/" +
      encodeURIComponent(title.replace(/ /g, "_"));
    const r = await fetch(sumUrl, { headers: { "User-Agent": WIKI_UA } });
    if (!r.ok) return null;
    const j = (await r.json()) as {
      extract?: string;
      content_urls?: { desktop?: { page?: string } };
    };
    const extract = j.extract ?? "";
    if (!extract) return null;
    const url =
      j.content_urls?.desktop?.page ??
      `https://fr.wikipedia.org/wiki/${encodeURIComponent(title.replace(/ /g, "_"))}`;
    return { extract: extract.slice(0, 800), url };
  } catch {
    return null;
  }
}

/** Concurrence limitée pour les lookups Wikipedia (poli envers l'API). */
async function mapLimit<A, B>(
  items: A[],
  limit: number,
  fn: (a: A) => Promise<B>
): Promise<B[]> {
  const out: B[] = new Array(items.length);
  let i = 0;
  async function worker(): Promise<void> {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await fn(items[idx]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker())
  );
  return out;
}

const VERIFY_SYSTEM =
  "Tu es vérificateur factuel pour un jeu de culture ivoirienne. Pour chaque " +
  "question, tu reçois la réponse, l'énigme, l'explication et un éventuel " +
  "extrait Wikipedia. Vérifie que la réponse et l'explication sont exactes et " +
  "que l'énigme désigne bien cette réponse. Verdict par index : `pass` (exact, " +
  "cohérent avec la source), `uncertain` (douteux ou source absente), `fail` " +
  "(faux). En cas de doute → `uncertain`. Donne une note courte. Le champ " +
  "sources peut rester vide (il sera complété côté serveur).";

/**
 * Vérification « éco quota » : Wikipedia uniquement, ZÉRO appel Gemini.
 * Chaque question est marquée `uncertain` (à valider en revue humaine), avec la
 * source Wikipedia attachée quand un article correspond. Économise le quota IA
 * (free tier 20 req/jour) : seule la génération consomme des appels.
 */
export async function verifyWikipediaOnly(
  items: VerifyItem[]
): Promise<{ results: VerifyResult[]; usage: AiUsage; calls: number }> {
  if (items.length === 0) return { results: [], usage: EMPTY_USAGE, calls: 0 };
  const evidence = await mapLimit(items, 5, (q) => wikiLookup(q.answer));
  const results: VerifyResult[] = items.map((q, i) => {
    const ev = evidence[i];
    return {
      index: q.index,
      verdict: "uncertain",
      confidence: ev ? 0.5 : 0,
      notes: ev
        ? "Mode éco : source Wikipedia trouvée — à valider en revue."
        : "Mode éco : aucune source Wikipedia — à valider en revue.",
      sources: ev ? [{ title: "Wikipedia", url: ev.url }] : [],
    };
  });
  return { results, usage: EMPTY_USAGE, calls: 0 };
}

export async function verifyHybrid(
  items: VerifyItem[]
): Promise<{ results: VerifyResult[]; usage: AiUsage; calls: number }> {
  if (items.length === 0) return { results: [], usage: EMPTY_USAGE, calls: 0 };
  let calls = 0;

  // 1. Wikipedia.
  const evidence = await mapLimit(items, 5, (q) => wikiLookup(q.answer));

  // 2. Vérification structurée avec preuves.
  const userLines = items
    .map((q, i) => {
      const ev = evidence[i];
      const src = ev ? `Extrait Wikipedia: ${ev.extract}` : "Extrait Wikipedia: AUCUN";
      return `#${q.index} — réponse: ${q.answer} | énigme: ${q.riddleFr} | explication: ${q.explanationFr}\n${src}`;
    })
    .join("\n\n");

  let usage = EMPTY_USAGE;
  let results: VerifyResult[] = [];
  calls += 1; // appel de vérification structurée
  try {
    const out = await geminiStructured<{ results: VerifyResult[] }>({
      system: [{ text: VERIFY_SYSTEM }],
      user: `Vérifie chaque question, renvoie { results: [...] } (un objet par index).\n\n${userLines}`,
      schema: verifySchema(),
      effort: "low",
    });
    results = out.data.results ?? [];
    usage = addUsage(usage, out.usage);
  } catch {
    // Échec structuré → tout en uncertain (revue humaine).
    results = items.map((q) => ({
      index: q.index,
      verdict: "uncertain" as const,
      confidence: 0,
      notes: "Vérification automatique indisponible.",
      sources: [],
    }));
  }

  // Attache l'URL Wikipedia comme source quand on en a une.
  const byIndex = new Map<number, VerifyResult>();
  for (const r of results) byIndex.set(r.index, r);
  items.forEach((q, i) => {
    const ev = evidence[i];
    const r = byIndex.get(q.index);
    if (r && ev && (!r.sources || r.sources.length === 0)) {
      r.sources = [{ title: "Wikipedia", url: ev.url }];
    }
  });

  // 3. Repli grounding pour les uncertain sans source.
  const fallbackItems = items.filter((q, i) => {
    const r = byIndex.get(q.index);
    return !evidence[i] && (!r || r.verdict === "uncertain") && (!r?.sources?.length);
  });

  if (fallbackItems.length > 0) {
    calls += 1; // appel grounding de repli
    try {
      const list = fallbackItems
        .map(
          (q) =>
            `#${q.index} — réponse: ${q.answer} | explication: ${q.explanationFr}`
        )
        .join("\n");
      const g = await geminiGrounded(
        "Vérifie via la recherche web l'exactitude de chaque fait (réponse + " +
          "explication). Réponds UNIQUEMENT par des lignes `index|verdict` où " +
          "verdict ∈ pass|uncertain|fail.",
        list
      );
      usage = addUsage(usage, g.usage);
      for (const line of g.text.split("\n")) {
        const m = line.match(/#?(\d+)\s*\|\s*(pass|uncertain|fail)/i);
        if (!m) continue;
        const idx = parseInt(m[1], 10);
        const r = byIndex.get(idx);
        if (r) {
          r.verdict = m[2].toLowerCase() as VerifyResult["verdict"];
          if (g.sources.length > 0) r.sources = g.sources.slice(0, 3);
        }
      }
    } catch {
      /* repli best-effort : on garde les uncertain */
    }
  }

  return { results: Array.from(byIndex.values()), usage, calls };
}
