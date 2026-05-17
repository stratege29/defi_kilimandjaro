/**
 * Tests unitaires pour les helpers purs de publishPack.
 *
 * Les helpers Firestore/Storage ne sont pas testés ici — ils requièrent
 * l'émulateur Firebase. Le pipeline full s'execute en e2e via :
 *   firebase emulators:exec --only firestore,functions,storage 'npm test'
 */
import { _internals } from "../src/curation/publishPack";

const { buildPackPayload, detectLangs } = _internals;

describe("detectLangs", () => {
  it("returns ['fr'] when no entries", () => {
    expect(detectLangs([])).toEqual(["fr"]);
  });
  it("collects all languages from riddle/explanation", () => {
    const q = (riddle: Record<string, string>, explanation: Record<string, string>) => ({
      id: "x",
      pack: "p",
      country: "ci",
      answer: "TEST",
      answer_normalized: "test",
      letters_pool: ["T", "E", "S", "T"],
      riddle,
      explanation,
      difficulty: 1,
      estimated_time_s: 20,
      tags: [],
      format_version: 3,
    });
    const langs = detectLangs([
      q({ fr: "..." }, { fr: "..." }),
      q({ en: "..." }, { fr: "...", en: "..." }),
    ]);
    expect(langs).toEqual(["en", "fr"]);
  });
});

describe("buildPackPayload", () => {
  it("produces deterministic structure", () => {
    const questions = [
      {
        id: "foo_001",
        pack: "foo",
        country: "ci",
        answer: "BAOULE",
        answer_normalized: "baoule",
        letters_pool: ["B", "A", "O", "U", "L", "E"],
        riddle: { fr: "Énoncé du peuple Akan." },
        explanation: { fr: "Les Baoulés sont un peuple Akan." },
        difficulty: 3,
        estimated_time_s: 30,
        tags: ["peuple"],
        format_version: 3,
      },
    ];
    const payload = buildPackPayload("foo", 2, questions);
    expect(payload).toMatchObject({
      format_version: 3,
      pack_id: "foo",
      pack_version: 2,
      langs: ["fr"],
      default_lang: "fr",
      count: 1,
      devinettes: questions,
    });
    // Aucun timestamp pour permettre la reproductibilité.
    expect(Object.keys(payload)).not.toContain("generated_at");
  });
});
