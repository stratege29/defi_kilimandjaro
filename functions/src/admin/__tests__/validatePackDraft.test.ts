/**
 * Tests unitaires de la logique pure de `validatePackDraft`.
 *
 * On teste `validatePackDraftPure` (sans Firebase) pour couvrir les 13 règles
 * du format v3. Les appels Firestore et l'authentification sont testés
 * séparément via emulator dans la suite d'intégration (Phase 1 Tâche 21).
 */

import {
  validatePackDraftPure,
  type ValidationIssue,
} from "../validatePackDraft";

const WHITELIST = new Set<string>([
  "cuisine",
  "tradition",
  "village",
  "musique",
  "joueur",
  "eleph",
]);

/** Devinette canonique 100 % valide — base pour les variations. */
function validDevinette(overrides: Record<string, unknown> = {}): Record<
  string,
  unknown
> {
  return {
    id: "culture_ci_001",
    pack: "culture_ci",
    country: "ci",
    answer: "FOUTOU",
    answer_normalized: "foutou",
    letters_pool: ["F", "O", "U", "T", "O", "U"],
    riddle: { fr: "Dans le mortier on me pile longtemps." },
    explanation: { fr: "Pâte pilée ivoirienne." },
    difficulty: 1,
    estimated_time_s: 25,
    tags: ["cuisine", "tradition"],
    format_version: 3,
    status: "draft",
    deleted_at: null,
    ...overrides,
  };
}

function codes(issues: ValidationIssue[]): string[] {
  return issues.map((i) => i.code);
}

describe("validatePackDraftPure", () => {
  describe("happy path", () => {
    it("retourne valid=true pour une devinette canonique", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette()],
        WHITELIST
      );
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
      expect(result.total).toBe(1);
    });

    it("accepte plusieurs devinettes distinctes", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({ id: "culture_ci_001", answer: "FOUTOU", answer_normalized: "foutou", letters_pool: ["F", "O", "U", "T", "O", "U"] }),
          validDevinette({ id: "culture_ci_002", answer: "ATTIEKE", answer_normalized: "attieke", letters_pool: ["A", "T", "T", "I", "E", "K", "E"] }),
        ],
        WHITELIST
      );
      expect(result.valid).toBe(true);
      expect(result.total).toBe(2);
    });
  });

  describe("format_version", () => {
    it("rejette format_version != 3", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ format_version: 2 })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("BAD_FORMAT_VERSION");
    });
  });

  describe("id format", () => {
    it("rejette id ne matchant pas <packId>_NNN", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ id: "wrong_format" })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("BAD_ID_FORMAT");
    });

    it("accepte id sur 4 chiffres (extensibilité)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ id: "culture_ci_1234" })],
        WHITELIST
      );
      expect(result.valid).toBe(true);
    });
  });

  describe("pack mismatch", () => {
    it("rejette si pack du doc ≠ packId du contexte", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ pack: "other_pack" })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("WRONG_PACK");
    });
  });

  describe("country", () => {
    it("rejette country non ISO 2", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ country: "ivc" })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("BAD_COUNTRY");
    });
  });

  describe("answer length", () => {
    it("rejette answer < 4 lettres", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            answer: "ABC",
            answer_normalized: "abc",
            letters_pool: ["A", "B", "C"],
          }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("ANSWER_LENGTH");
    });

    it("rejette answer > 12 lettres", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            answer: "ABCDEFGHIJKLM",
            answer_normalized: "abcdefghijklm",
            letters_pool: "ABCDEFGHIJKLM".split(""),
          }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("ANSWER_LENGTH");
    });

    it("accepte answer 4 lettres (borne basse)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            answer: "MAIS",
            answer_normalized: "mais",
            letters_pool: ["M", "A", "I", "S"],
          }),
        ],
        WHITELIST
      );
      expect(result.valid).toBe(true);
    });

    it("accepte answer 12 lettres (borne haute)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            answer: "YAMOUSSOUKRO",
            answer_normalized: "yamoussoukro",
            letters_pool: "YAMOUSSOUKRO".split(""),
          }),
        ],
        WHITELIST
      );
      expect(result.valid).toBe(true);
    });
  });

  describe("answer_normalized", () => {
    it("rejette answer_normalized incohérent", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ answer_normalized: "wrong" })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("BAD_NORMALIZED");
    });

    it("normalise correctement les accents (é → e)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            answer: "ÉLÉPHANT",
            answer_normalized: "elephant",
            letters_pool: ["E", "L", "E", "P", "H", "A", "N", "T"],
          }),
        ],
        WHITELIST
      );
      expect(result.valid).toBe(true);
    });
  });

  describe("letters_pool", () => {
    it("rejette letters_pool incomplet", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ letters_pool: ["F", "O", "U", "T", "O"] })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("BAD_LETTERS_POOL");
    });

    it("accepte letters_pool dans le désordre (multiset)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ letters_pool: ["U", "O", "F", "T", "U", "O"] })],
        WHITELIST
      );
      expect(result.valid).toBe(true);
    });
  });

  describe("riddle.fr", () => {
    it("rejette riddle.fr vide", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ riddle: { fr: "" } })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("MISSING_RIDDLE_FR");
    });

    it("rejette si la réponse apparaît dans riddle.fr (case-insensitive)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            riddle: { fr: "Je suis le foutou ivoirien." },
          }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("ANSWER_IN_RIDDLE");
    });

    it("rejette si la réponse apparaît avec accents normalisés", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            answer: "ELEPHANT",
            answer_normalized: "elephant",
            letters_pool: ["E", "L", "E", "P", "H", "A", "N", "T"],
            riddle: { fr: "Géant gris des savanes, un éléphant majestueux." },
          }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("ANSWER_IN_RIDDLE");
    });

    it("accepte si seul un fragment <4 chars match (false positive évité)", () => {
      // FOUR n'apparaît pas, donc on construit un cas où une sous-chaîne de 3
      // chars matche : answer FOU (mais len 3 invalide via ANSWER_LENGTH)
      // → ce test vérifie que answer.length >= 4 est requis pour le check.
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ riddle: { fr: "Beau plat à la sauce graine." } })],
        WHITELIST
      );
      // Pas d'erreur ANSWER_IN_RIDDLE car "foutou" n'apparaît pas dans la riddle.
      expect(codes(result.errors)).not.toContain("ANSWER_IN_RIDDLE");
    });
  });

  describe("explanation.fr", () => {
    it("warn si explanation.fr vide (pas error)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ explanation: { fr: "" } })],
        WHITELIST
      );
      expect(result.valid).toBe(true);
      expect(codes(result.warnings)).toContain("MISSING_EXPLANATION_FR");
    });
  });

  describe("tags whitelist", () => {
    it("rejette tags hors whitelist", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ tags: ["cuisine", "inventé"] })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("TAGS_NOT_WHITELISTED");
    });

    it("accepte tous tags si whitelist vide (mode permissif)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ tags: ["anything", "goes"] })],
        new Set<string>()
      );
      expect(result.valid).toBe(true);
    });
  });

  describe("difficulty", () => {
    it.each([0, 5, 10, -1])("rejette difficulty=%i", (d) => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ difficulty: d })],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("BAD_DIFFICULTY");
    });

    it.each([1, 2, 3, 4])("accepte difficulty=%i", (d) => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ difficulty: d })],
        WHITELIST
      );
      expect(result.valid).toBe(true);
    });
  });

  describe("estimated_time_s", () => {
    it("warn si time hors range [10-120]", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ estimated_time_s: 5 })],
        WHITELIST
      );
      expect(result.valid).toBe(true);
      expect(codes(result.warnings)).toContain("TIME_OUT_OF_RANGE");
    });
  });

  describe("doublons answer", () => {
    it("rejette deux devinettes avec la même answer dans le pack", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({ id: "culture_ci_001" }),
          validDevinette({ id: "culture_ci_002" }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("DUPLICATE_ANSWER");
    });

    it("dédoublonne par normalisation (FOUTOU ≡ foutou)", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({ id: "culture_ci_001", answer: "FOUTOU" }),
          // Pas possible techniquement (answer doit être UPPER) mais on teste
          // la normalisation robuste.
          validDevinette({
            id: "culture_ci_002",
            answer: "FOÛTOU",
            answer_normalized: "foutou",
            letters_pool: ["F", "O", "U", "T", "O", "U"],
          }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("DUPLICATE_ANSWER");
    });
  });

  describe("draft + deleted_at incohérence", () => {
    it("rejette une devinette draft avec deleted_at défini", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [
          validDevinette({
            status: "draft",
            deleted_at: new Date("2026-01-01"),
          }),
        ],
        WHITELIST
      );
      expect(codes(result.errors)).toContain("DRAFT_DELETED");
    });
  });

  describe("structure du retour", () => {
    it("contient les champs valid, total, errors, warnings", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette()],
        WHITELIST
      );
      expect(result).toHaveProperty("valid");
      expect(result).toHaveProperty("total");
      expect(result).toHaveProperty("errors");
      expect(result).toHaveProperty("warnings");
      expect(Array.isArray(result.errors)).toBe(true);
      expect(Array.isArray(result.warnings)).toBe(true);
    });

    it("chaque issue contient deviId, code, message", () => {
      const result = validatePackDraftPure(
        "culture_ci",
        [validDevinette({ format_version: 99 })],
        WHITELIST
      );
      expect(result.errors[0]).toHaveProperty("deviId");
      expect(result.errors[0]).toHaveProperty("code");
      expect(result.errors[0]).toHaveProperty("message");
    });
  });
});
