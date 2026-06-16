/**
 * devinettesCache — module partage entre requestMatch et requestRematch.
 *
 * Cache memoire des devinettes Firestore groupees par difficulte.
 * TTL 5 min — invalide automatiquement apres expiration.
 */

import { getFirestore } from "firebase-admin/firestore";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DevinetteDoc {
  id: string;
  answer: string;
  letters_pool: string[];
  riddle: string;
  explanation: string;
  proverb: string;
  difficulty: "easy" | "medium" | "hard";
}

export interface RoundPayload {
  answer: string;
  letters_pool: string[];
  riddle: string;
  explanation: string;
  proverb: string;
  difficulty: string;
  devinette_id: string;
}

export type DifficultyCache = Map<"easy" | "medium" | "hard", DevinetteDoc[]>;

// ---------------------------------------------------------------------------
// Fallback pool (utilise si Firestore est indisponible au cold start).
// Minimum 2 entrees par difficulte pour eviter les doublons dans un match.
// ---------------------------------------------------------------------------

export const SAMPLE_DEVINETTES: DevinetteDoc[] = [
  {
    id: "sample_easy_1",
    answer: "KORA",
    letters_pool: ["K", "O", "R", "A"],
    riddle: "Vingt et une cordes, une calebasse, une voix de l'ame.",
    explanation:
      "La kora est un instrument a cordes ouest-africain a 21 cordes.",
    proverb: "Celui qui tient la kora tient l'histoire.",
    difficulty: "easy",
  },
  {
    id: "sample_easy_2",
    answer: "GRIOT",
    letters_pool: ["G", "R", "I", "O", "T"],
    riddle: "Je garde la memoire de ton peuple dans ma gorge et mes doigts.",
    explanation:
      "Le griot est le gardien de la tradition orale en Afrique de l'Ouest.",
    proverb: "Quand un vieux meurt, une bibliotheque brule.",
    difficulty: "easy",
  },
  {
    id: "sample_medium_1",
    answer: "SAVANE",
    letters_pool: ["S", "A", "V", "A", "N", "E"],
    riddle:
      "Je suis la plaine d'herbes hautes ou dansent les acacia et les elephants.",
    explanation:
      "La savane africaine couvre environ 40 % du continent.",
    proverb:
      "L'enfant qui n'a pas voyage pense que sa mere est la meilleure cuisiniere.",
    difficulty: "medium",
  },
  {
    id: "sample_medium_2",
    answer: "BAOBAB",
    letters_pool: ["B", "A", "O", "B", "A", "B"],
    riddle: "Je suis l'arbre dont les racines pointent vers le ciel.",
    explanation:
      "Le baobab est surnomme 'arbre a l'envers' car ses branches ressemblent a des racines.",
    proverb: "Le baobab ne pousse pas en un jour.",
    difficulty: "medium",
  },
  {
    id: "sample_hard_1",
    answer: "CALEBASSE",
    letters_pool: ["C", "A", "L", "E", "B", "A", "S", "S", "E"],
    riddle: "Je suis la fille du champ, la mere de la cuisine.",
    explanation:
      "La calebasse est une courge sechee utilisee comme recipient en Afrique de l'Ouest.",
    proverb: "La calebasse ne se moque pas du pot de terre casse.",
    difficulty: "hard",
  },
  {
    id: "sample_hard_2",
    answer: "DJEMBEFOLA",
    letters_pool: ["D", "J", "E", "M", "B", "E", "F", "O", "L", "A"],
    riddle: "Je suis le maitre du tambour qui fait danser les ancetres.",
    explanation:
      "Le djembefola est le joueur expert du djembe, percussionniste de haut rang.",
    proverb: "Le tambour qui parle fort parle pour tous.",
    difficulty: "hard",
  },
];

// ---------------------------------------------------------------------------
// Cache memoire — TTL 5 min.
// ---------------------------------------------------------------------------

const CACHE_TTL_MS = 5 * 60 * 1000;

let _cache: DifficultyCache | null = null;
let _cacheLoadedAt = 0;

function _buildFallbackCache(): DifficultyCache {
  const cache: DifficultyCache = new Map();
  cache.set("easy", []);
  cache.set("medium", []);
  cache.set("hard", []);
  for (const d of SAMPLE_DEVINETTES) {
    cache.get(d.difficulty)!.push(d);
  }
  return cache;
}

export async function _loadDevinettesCache(): Promise<DifficultyCache> {
  const now = Date.now();
  if (_cache !== null && now - _cacheLoadedAt < CACHE_TTL_MS) {
    return _cache;
  }

  try {
    const db = getFirestore();
    const snap = await db
      .collection("devinettes")
      .where("enabled_for_duel", "==", true)
      .where("status", "==", "approved")
      .get();

    const cache: DifficultyCache = new Map();
    cache.set("easy", []);
    cache.set("medium", []);
    cache.set("hard", []);

    for (const doc of snap.docs) {
      const data = doc.data() as Omit<DevinetteDoc, "id">;
      const difficulty = data.difficulty;
      if (!["easy", "medium", "hard"].includes(difficulty)) continue;
      cache.get(difficulty as "easy" | "medium" | "hard")!.push({
        id: doc.id,
        ...data,
      });
    }

    // Completer les difficultes vides avec les samples.
    for (const diff of ["easy", "medium", "hard"] as const) {
      if (cache.get(diff)!.length === 0) {
        cache.set(
          diff,
          SAMPLE_DEVINETTES.filter((d) => d.difficulty === diff)
        );
      }
    }

    _cache = cache;
    _cacheLoadedAt = now;
    return cache;
  } catch (err) {
    console.warn(
      "[devinettesCache] Firestore indisponible, fallback samples:",
      err
    );
    return _buildFallbackCache();
  }
}

// ---------------------------------------------------------------------------
// Selection de 3 rounds sans doublon (une par difficulte).
// ---------------------------------------------------------------------------

function _shuffleArr<T>(arr: T[]): T[] {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

export function _pickThreeRounds(cache: DifficultyCache): RoundPayload[] {
  const usedIds = new Set<string>();

  const pick = (diff: "easy" | "medium" | "hard"): DevinetteDoc => {
    const pool = cache.get(diff)!;
    const available = pool.filter((d) => !usedIds.has(d.id));
    const source = available.length > 0 ? available : pool;
    const chosen = source[Math.floor(Math.random() * source.length)];
    usedIds.add(chosen.id);
    return chosen;
  };

  const r0 = pick("easy");
  const r1 = pick("medium");
  const r2 = pick("hard");

  return [r0, r1, r2].map((d) => ({
    answer: d.answer,
    letters_pool: _shuffleArr(d.letters_pool),
    riddle: d.riddle,
    explanation: d.explanation,
    proverb: d.proverb ?? "",
    difficulty: d.difficulty,
    devinette_id: d.id,
  }));
}

// ---------------------------------------------------------------------------
// Anti-cheat (C3) : séparation payload public / réponses serveur-only.
// ---------------------------------------------------------------------------

/**
 * Payload public d'une manche : tout SAUF la réponse. Le client a besoin de
 * `letters_pool` (dont la longueur == longueur de la réponse) pour rendre la
 * grille, mais ne doit jamais recevoir `answer` pendant la manche.
 */
export function toPublicRound(r: RoundPayload): Omit<RoundPayload, "answer"> {
  // Déstructuration explicite pour garantir qu'`answer` ne fuite pas.
  const { answer: _omit, ...publicFields } = r;
  void _omit;
  return publicFields;
}

/** Map des réponses indexée par numéro de manche (pour match_answers). */
export function answersFromRounds(
  rounds: RoundPayload[]
): Record<number, string> {
  return { 0: rounds[0].answer, 1: rounds[1].answer, 2: rounds[2].answer };
}
