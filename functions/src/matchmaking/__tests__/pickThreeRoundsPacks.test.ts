/**
 * Tests du scoping par packs de _pickThreeRounds (sélection de tournoi).
 * Fonction pure : aucun Firebase requis.
 */

import {
  _pickThreeRounds,
  type DevinetteDoc,
  type DifficultyCache,
} from "../devinettesCache";

function doc(id: string, pack: string, difficulty: DevinetteDoc["difficulty"]): DevinetteDoc {
  return {
    id,
    pack,
    answer: "MOT",
    letters_pool: ["M", "O", "T"],
    riddle: "r",
    explanation: "e",
    proverb: "",
    difficulty,
  };
}

function buildCache(): DifficultyCache {
  const c: DifficultyCache = new Map();
  c.set("easy", [doc("a_1", "a", "easy"), doc("b_1", "b", "easy")]);
  c.set("medium", [doc("a_2", "a", "medium"), doc("b_2", "b", "medium")]);
  c.set("hard", [doc("a_3", "a", "hard"), doc("b_3", "b", "hard")]);
  return c;
}

describe("_pickThreeRounds — scoping par packs", () => {
  test("packIds=['a'] → toutes les manches viennent du pack a", () => {
    for (let i = 0; i < 30; i++) {
      const rounds = _pickThreeRounds(buildCache(), ["a"]);
      expect(rounds).toHaveLength(3);
      for (const r of rounds) {
        expect(r.devinette_id.startsWith("a_")).toBe(true);
      }
    }
  });

  test("plusieurs packs : ne tire que dans a ou b (jamais hors scope)", () => {
    const cache = buildCache();
    cache.get("easy")!.push(doc("c_1", "c", "easy"));
    for (let i = 0; i < 30; i++) {
      const rounds = _pickThreeRounds(cache, ["a", "b"]);
      for (const r of rounds) {
        expect(r.devinette_id.startsWith("c_")).toBe(false);
      }
    }
  });

  test("pack inexistant pour une difficulté → fallback pool global (match jouable)", () => {
    // 'a' n'existe qu'en easy ; medium/hard n'ont que 'b'.
    const c: DifficultyCache = new Map();
    c.set("easy", [doc("a_1", "a", "easy")]);
    c.set("medium", [doc("b_2", "b", "medium")]);
    c.set("hard", [doc("b_3", "b", "hard")]);
    const rounds = _pickThreeRounds(c, ["a"]);
    expect(rounds).toHaveLength(3);
    // easy depuis a ; medium/hard retombent sur b (sinon match cassé).
    expect(rounds[0].devinette_id).toBe("a_1");
    expect(rounds[1].devinette_id).toBe("b_2");
    expect(rounds[2].devinette_id).toBe("b_3");
  });

  test("sans packIds → pool global complet", () => {
    const rounds = _pickThreeRounds(buildCache());
    expect(rounds).toHaveLength(3);
  });
});
