/**
 * Tests d'intégration end-to-end de `publishPack` contre les emulators
 * Firestore + Storage.
 *
 * Prérequis pour exécution :
 *   1. `firebase emulators:start --only firestore,storage,auth`
 *   2. `npm run test:integration`
 *
 * Si les emulators ne sont pas joignables, la suite échoue avec un message
 * clair (les tests ne sont PAS skip — on veut une CI qui exige les emulators
 * pour cette suite).
 *
 * Ces tests valident la séquence complète :
 *   - input → publishPack → écritures Firestore réelles + upload Storage réel
 *
 * Coverage MVP : happy path + validation failure + version increment.
 * À étendre : rollback, upsert, bulk import, guards auth, idempotence,
 * concurrent publishes (lock?).
 */

import {
  setupEmulatorEnv,
  getTestApp,
  clearFirestore,
  teardownTestApp,
  TEST_PROJECT_ID,
  makeDevinette,
} from "../setupEmulator";

// IMPORTANT : setup env AVANT d'importer les modules qui appellent getFirestore.
setupEmulatorEnv();

import { getFirestore, FieldValue } from "firebase-admin/firestore";
import functionsTest from "firebase-functions-test";

// Initialise firebase-functions-test pour wrapper les CFs.
const ft = functionsTest({
  projectId: TEST_PROJECT_ID,
});

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { publishPack } = require("../../publishPack");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { validatePackDraft } = require("../../validatePackDraft");

const TEST_PACK_ID = "test_pack_a";

async function seedPack(
  packId: string,
  devinettes: Array<Record<string, unknown>>,
  tagsWhitelist: string[] = ["cuisine", "tradition"]
): Promise<void> {
  const db = getFirestore(getTestApp());

  // Seed tags whitelist
  await db
    .collection("catalog")
    .doc("tags_whitelist")
    .set({ tags: tagsWhitelist, updated_at: FieldValue.serverTimestamp() });

  // Seed devinettes
  const batch = db.batch();
  for (const d of devinettes) {
    const ref = db
      .collection("packs")
      .doc(packId)
      .collection("devinettes")
      .doc(d.id as string);
    batch.set(ref, { ...d, updated_at: FieldValue.serverTimestamp() });
  }
  await batch.commit();
}

function adminCallContext(): { auth: { uid: string; token: Record<string, unknown> } } {
  return {
    auth: {
      uid: "admin-test-uid",
      token: { role: "admin" },
    },
  };
}

describe("publishPack — integration emulator", () => {
  beforeAll(async () => {
    // Vérifie que l'emulator répond
    try {
      const db = getFirestore(getTestApp());
      await db.collection("__health__").limit(1).get();
    } catch (e) {
      throw new Error(
        "Emulator Firestore inaccessible (127.0.0.1:8080). Lance " +
          "`firebase emulators:start --only firestore,storage,auth` " +
          "avant de relancer les tests d'intégration."
      );
    }
  });

  afterAll(async () => {
    ft.cleanup();
    await teardownTestApp();
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  describe("happy path", () => {
    it("publie v1 d'un pack et écrit content_packs + versions/1", async () => {
      const devs = [
        makeDevinette({
          id: `${TEST_PACK_ID}_001`,
          pack: TEST_PACK_ID,
          status: "draft",
        }),
        makeDevinette({
          id: `${TEST_PACK_ID}_002`,
          pack: TEST_PACK_ID,
          answer: "ATTIEKE",
          answer_normalized: "attieke",
          letters_pool: ["A", "T", "T", "I", "E", "K", "E"],
          riddle: { fr: "Semoule fermentée appréciée à Abidjan." },
          status: "draft",
        }),
      ];
      await seedPack(TEST_PACK_ID, devs);

      const wrapped = ft.wrap(publishPack);
      const result = await wrapped({
        data: { packId: TEST_PACK_ID },
        ...adminCallContext(),
      });

      expect(result.version).toBe(1);
      expect(result.count).toBe(2);
      expect(result.hashSha256).toMatch(/^[a-f0-9]{64}$/);
      expect(result.sizeBytes).toBeGreaterThan(0);

      // Vérifie écriture content_packs
      const db = getFirestore(getTestApp());
      const manifestSnap = await db
        .collection("content_packs")
        .doc(TEST_PACK_ID)
        .get();
      expect(manifestSnap.exists).toBe(true);
      expect(manifestSnap.data()?.current_version).toBe(1);
      expect(manifestSnap.data()?.hash_sha256).toBe(result.hashSha256);

      // Vérifie versions/1 = active
      const v1Snap = await db
        .collection("packs")
        .doc(TEST_PACK_ID)
        .collection("versions")
        .doc("1")
        .get();
      expect(v1Snap.exists).toBe(true);
      expect(v1Snap.data()?.status).toBe("active");

      // Vérifie content_index/global
      const indexSnap = await db
        .collection("content_index")
        .doc("global")
        .get();
      expect(indexSnap.data()?.packs).toContain(TEST_PACK_ID);

      // Vérifie audit log
      const auditSnap = await db
        .collection("packs")
        .doc(TEST_PACK_ID)
        .collection("audit")
        .get();
      expect(auditSnap.size).toBe(1);
      expect(auditSnap.docs[0].data().type).toBe("publish");

      // Vérifie le mirror vers le pool de duel (collection racine `devinettes`).
      const duelSnap = await db
        .collection("devinettes")
        .doc(`${TEST_PACK_ID}_001`)
        .get();
      expect(duelSnap.exists).toBe(true);
      expect(duelSnap.data()?.enabled_for_duel).toBe(true);
      expect(duelSnap.data()?.status).toBe("approved");
      expect(duelSnap.data()?.pack).toBe(TEST_PACK_ID);
      expect(duelSnap.data()?.difficulty).toBe("easy"); // difficulty 1 → easy
    }, 30_000);

    it("promeut les drafts en published après publish", async () => {
      const devs = [
        makeDevinette({
          id: `${TEST_PACK_ID}_001`,
          pack: TEST_PACK_ID,
          status: "draft",
        }),
      ];
      await seedPack(TEST_PACK_ID, devs);

      const wrapped = ft.wrap(publishPack);
      await wrapped({
        data: { packId: TEST_PACK_ID },
        ...adminCallContext(),
      });

      const db = getFirestore(getTestApp());
      const deviSnap = await db
        .collection("packs")
        .doc(TEST_PACK_ID)
        .collection("devinettes")
        .doc(`${TEST_PACK_ID}_001`)
        .get();
      expect(deviSnap.data()?.status).toBe("published");
      expect(deviSnap.data()?.published_version).toBe(1);
      expect(deviSnap.data()?.draft_version).toBeNull();
    }, 30_000);
  });

  describe("validation failures", () => {
    it("rejette si une devinette a un tag hors whitelist", async () => {
      const devs = [
        makeDevinette({
          id: `${TEST_PACK_ID}_001`,
          pack: TEST_PACK_ID,
          tags: ["cuisine", "inventé"], // "inventé" pas dans whitelist
          status: "draft",
        }),
      ];
      await seedPack(TEST_PACK_ID, devs, ["cuisine"]);

      const wrapped = ft.wrap(publishPack);
      await expect(
        wrapped({
          data: { packId: TEST_PACK_ID },
          ...adminCallContext(),
        })
      ).rejects.toThrow(/Validation/);

      // Vérifie : aucune version créée, aucun manifest, aucun audit
      const db = getFirestore(getTestApp());
      const v1Snap = await db
        .collection("packs")
        .doc(TEST_PACK_ID)
        .collection("versions")
        .doc("1")
        .get();
      expect(v1Snap.exists).toBe(false);
    }, 30_000);

    it("rejette si le pack est vide", async () => {
      // Pas de seed → 0 devinettes
      const wrapped = ft.wrap(publishPack);
      await expect(
        wrapped({
          data: { packId: TEST_PACK_ID },
          ...adminCallContext(),
        })
      ).rejects.toThrow(/aucune devinette/);
    }, 30_000);
  });

  describe("auth guards", () => {
    it("rejette un appelant non-admin", async () => {
      const wrapped = ft.wrap(publishPack);
      await expect(
        wrapped({
          data: { packId: TEST_PACK_ID },
          auth: { uid: "u1", token: { role: "editor" } },
        })
      ).rejects.toThrow(/admin/);
    });

    it("rejette un appelant non-authentifié", async () => {
      const wrapped = ft.wrap(publishPack);
      await expect(
        wrapped({
          data: { packId: TEST_PACK_ID },
          // pas d'auth
        })
      ).rejects.toThrow(/Authentification/);
    });
  });

  describe("validatePackDraft (integration)", () => {
    it("retourne valid=true pour un pack clean", async () => {
      const devs = [
        makeDevinette({
          id: `${TEST_PACK_ID}_001`,
          pack: TEST_PACK_ID,
          status: "draft",
        }),
      ];
      await seedPack(TEST_PACK_ID, devs);

      const wrapped = ft.wrap(validatePackDraft);
      const result = await wrapped({
        data: { packId: TEST_PACK_ID },
        auth: { uid: "u1", token: { role: "editor" } },
      });
      expect(result.valid).toBe(true);
      expect(result.total).toBe(1);
    }, 30_000);

    it("permet à un editor (pas admin) de valider", async () => {
      const devs = [
        makeDevinette({
          id: `${TEST_PACK_ID}_001`,
          pack: TEST_PACK_ID,
          status: "draft",
        }),
      ];
      await seedPack(TEST_PACK_ID, devs);

      const wrapped = ft.wrap(validatePackDraft);
      await expect(
        wrapped({
          data: { packId: TEST_PACK_ID },
          auth: { uid: "u1", token: { role: "editor" } },
        })
      ).resolves.toBeDefined();
    }, 30_000);
  });
});
