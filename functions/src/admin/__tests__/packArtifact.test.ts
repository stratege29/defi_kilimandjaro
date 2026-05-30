/**
 * Tests unitaires des pure functions de `packArtifact.ts`.
 *
 * Couvre :
 *  - Sérialisation format v3 (clés, ordre, valeurs)
 *  - Hash SHA256 reproductible (idempotence)
 *  - Gzip déterministe (à contenu égal, bytes égaux)
 *  - Détection des langues (union riddle + explanation, trié)
 *
 * Pas de Firebase ni de Cloud Storage (testé via emulator en Tâche 21).
 */

import { gunzipSync } from "zlib";

import {
  PACK_DEFAULT_LANG,
  PACK_FORMAT_VERSION_V3,
  PACK_MIN_APP_VERSION,
  buildPackArtifact,
  buildPackPayloadV3,
  downloadUrlFor,
  storagePathFor,
  type DevinetteV3,
} from "../packArtifact";

function makeDevinette(overrides: Partial<DevinetteV3> = {}): DevinetteV3 {
  return {
    id: "test_001",
    pack: "test",
    country: "ci",
    answer: "FOUTOU",
    answer_normalized: "foutou",
    letters_pool: ["F", "O", "U", "T", "O", "U"],
    riddle: { fr: "Dans le mortier on me pile." },
    explanation: { fr: "Pâte ivoirienne." },
    difficulty: 1,
    estimated_time_s: 25,
    tags: ["cuisine"],
    format_version: 3,
    ...overrides,
  };
}

describe("buildPackPayloadV3", () => {
  it("inclut les champs canoniques v3", () => {
    const p = buildPackPayloadV3("test_pack", 2, [makeDevinette()]);
    expect(p.format_version).toBe(PACK_FORMAT_VERSION_V3);
    expect(p.pack_id).toBe("test_pack");
    expect(p.pack_version).toBe(2);
    expect(p.default_lang).toBe(PACK_DEFAULT_LANG);
    expect(p.min_app_version).toBe(PACK_MIN_APP_VERSION);
    expect(p.count).toBe(1);
    expect(p.devinettes).toHaveLength(1);
  });

  it("détecte les langues depuis les riddles et explanations", () => {
    const p = buildPackPayloadV3("test_pack", 1, [
      makeDevinette({
        riddle: { fr: "...", en: "..." },
        explanation: { fr: "..." },
      }),
      makeDevinette({
        id: "test_002",
        answer: "MAIS",
        answer_normalized: "mais",
        letters_pool: ["M", "A", "I", "S"],
        riddle: { fr: "...", de: "..." },
        explanation: { fr: "..." },
      }),
    ]);
    // Trié alphabétiquement : de, en, fr
    expect(p.langs).toEqual(["de", "en", "fr"]);
  });

  it("fallback sur ['fr'] si aucune langue détectée", () => {
    const p = buildPackPayloadV3("test_pack", 1, [
      // riddle/explanation vides
      makeDevinette({ riddle: {}, explanation: {} }),
    ]);
    expect(p.langs).toEqual(["fr"]);
  });

  it("ordre des clés stable (clé devinettes en dernier)", () => {
    const p = buildPackPayloadV3("test_pack", 1, [makeDevinette()]);
    const keys = Object.keys(p);
    expect(keys[keys.length - 1]).toBe("devinettes");
    // Les champs scalaires viennent avant
    expect(keys.indexOf("format_version")).toBeLessThan(keys.indexOf("devinettes"));
  });
});

describe("buildPackArtifact — idempotence", () => {
  it("produit le même hash et le même gzip pour le même contenu", () => {
    const devs = [makeDevinette(), makeDevinette({ id: "test_002", answer: "MAIS", answer_normalized: "mais", letters_pool: ["M", "A", "I", "S"] })];

    const a1 = buildPackArtifact("test", 1, devs);
    const a2 = buildPackArtifact("test", 1, devs);

    expect(a1.hashSha256).toBe(a2.hashSha256);
    expect(a1.sizeBytes).toBe(a2.sizeBytes);
    expect(Buffer.compare(a1.gz, a2.gz)).toBe(0);
  });

  it("hash change si on change la version", () => {
    const devs = [makeDevinette()];
    const a1 = buildPackArtifact("test", 1, devs);
    const a2 = buildPackArtifact("test", 2, devs);
    expect(a1.hashSha256).not.toBe(a2.hashSha256);
  });

  it("hash change si on ajoute une devinette", () => {
    const a1 = buildPackArtifact("test", 1, [makeDevinette()]);
    const a2 = buildPackArtifact("test", 1, [
      makeDevinette(),
      makeDevinette({ id: "test_002", answer: "MAIS", answer_normalized: "mais", letters_pool: ["M", "A", "I", "S"] }),
    ]);
    expect(a1.hashSha256).not.toBe(a2.hashSha256);
    expect(a2.payload.count).toBe(2);
  });

  it("hash change si on modifie le contenu d'une devinette", () => {
    const a1 = buildPackArtifact("test", 1, [makeDevinette()]);
    const a2 = buildPackArtifact("test", 1, [
      makeDevinette({ riddle: { fr: "Énigme modifiée." } }),
    ]);
    expect(a1.hashSha256).not.toBe(a2.hashSha256);
  });
});

describe("buildPackArtifact — payload structure", () => {
  it("inclut un champ hash_sha256 intermédiaire dans le payload", () => {
    // Le payload contient un PREMIER hash (sur le payload sans hash_sha256).
    // C'est différent de artifact.hashSha256 qui est le hash FINAL (du payload
    // avec ce champ intermédiaire inclus). Le client recalcule le hash final
    // sur le JSON décompressé complet et compare à manifest.hashSha256.
    // Cf docs/backoffice_schema.md §7 + RemoteDevinettePackDatasource.
    const a = buildPackArtifact("test", 1, [makeDevinette()]);
    expect(typeof a.payload.hash_sha256).toBe("string");
    expect((a.payload.hash_sha256 as string).length).toBe(64); // hex SHA256
    // Les deux hashes sont différents (l'un avec, l'autre sans le champ)
    expect(a.payload.hash_sha256).not.toBe(a.hashSha256);
  });

  it("gzip décompresse en un JSON valide hashable côté client", () => {
    const a = buildPackArtifact("test", 1, [makeDevinette()]);
    const decompressed = gunzipSync(a.gz);
    const parsed = JSON.parse(decompressed.toString("utf8"));
    expect(parsed.format_version).toBe(3);
    expect(parsed.pack_id).toBe("test");

    // Contrat : SHA256(décompressé) === artifact.hashSha256 (= manifest.hashSha256)
    // C'est ce que RemoteDevinettePackDatasource fait pour vérifier l'intégrité.
    const { createHash } = require("crypto") as typeof import("crypto");
    const recomputed = createHash("sha256").update(decompressed).digest("hex");
    expect(recomputed).toBe(a.hashSha256);
  });

  it("compression typique > 4x pour 100 devinettes similaires", () => {
    const devs = Array.from({ length: 100 }, (_, i) =>
      makeDevinette({
        id: `test_${String(i).padStart(3, "0")}`,
        answer: `WORD${String(i).padStart(2, "0")}`,
        answer_normalized: `word${String(i).padStart(2, "0")}`,
        letters_pool: ["W", "O", "R", "D", "0", "0"],
      })
    );
    const a = buildPackArtifact("test", 1, devs);
    const rawSize = Buffer.from(JSON.stringify(a.payload), "utf8").length;
    expect(rawSize / a.sizeBytes).toBeGreaterThan(4);
  });
});

describe("storagePathFor", () => {
  it("construit le chemin canonique", () => {
    expect(storagePathFor("culture_ci", 2)).toBe(
      "packs/v2/culture_ci/culture_ci-v2.json.gz"
    );
  });
});

describe("downloadUrlFor", () => {
  it("encode le chemin correctement", () => {
    const url = downloadUrlFor(
      "kilimandjaro-prod.firebasestorage.app",
      "packs/v2/culture_ci/culture_ci-v2.json.gz"
    );
    expect(url).toBe(
      "https://firebasestorage.googleapis.com/v0/b/kilimandjaro-prod.firebasestorage.app/o/packs%2Fv2%2Fculture_ci%2Fculture_ci-v2.json.gz?alt=media"
    );
  });
});
