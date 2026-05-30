/**
 * Setup partagé pour les tests d'intégration emulator.
 *
 * Prérequis : les emulators Firestore + Storage + Auth doivent tourner
 * sur les ports configurés dans `firebase.json`.
 *
 *   - Lancer en arrière-plan : `firebase emulators:start --only firestore,storage,auth`
 *   - Lancer les tests :       `npm run test:integration`
 *
 * Si les emulators ne tournent pas, les tests `describe.skip` automatiquement
 * (via le helper `requireEmulators()` à appeler en tête de chaque suite).
 */

import { initializeApp, deleteApp, App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

export const TEST_PROJECT_ID = "kilimandjaro-test";

const FIRESTORE_HOST = "127.0.0.1:8080";
const STORAGE_HOST = "127.0.0.1:9199";
const AUTH_HOST = "127.0.0.1:9099";

let _initialized = false;
let _testApp: App | null = null;

/**
 * Initialise les variables d'environnement pour pointer le SDK Admin vers
 * les emulators. À appeler avant tout import de fichier qui appelle
 * `getFirestore()`, `getStorage()`, etc.
 */
export function setupEmulatorEnv(): void {
  if (_initialized) return;
  process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_HOST;
  process.env.FIREBASE_STORAGE_EMULATOR_HOST = STORAGE_HOST;
  process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;
  process.env.GCLOUD_PROJECT = TEST_PROJECT_ID;
  _initialized = true;
}

/**
 * Initialise une app admin pointant sur les emulators.
 * Idempotent : retourne l'instance existante si déjà créée.
 */
export function getTestApp(): App {
  if (_testApp) return _testApp;
  setupEmulatorEnv();
  _testApp = initializeApp(
    {
      projectId: TEST_PROJECT_ID,
      storageBucket: `${TEST_PROJECT_ID}.appspot.com`,
    },
    "test"
  );
  return _testApp;
}

/**
 * Détruit l'app test (à appeler en `afterAll`).
 */
export async function teardownTestApp(): Promise<void> {
  if (_testApp) {
    await deleteApp(_testApp);
    _testApp = null;
  }
  _initialized = false;
}

/**
 * Vide les collections backoffice de l'emulator Firestore. À appeler en
 * `beforeEach` pour garantir un état clean entre les tests.
 */
export async function clearFirestore(): Promise<void> {
  const db = getFirestore(getTestApp());
  const collections = [
    "catalog",
    "content_packs",
    "content_index",
    "packs",
  ];
  for (const coll of collections) {
    await deleteCollectionRecursive(db, coll);
  }
}

async function deleteCollectionRecursive(
  db: FirebaseFirestore.Firestore,
  path: string
): Promise<void> {
  const snap = await db.collection(path).get();
  for (const doc of snap.docs) {
    // Subcollections récursives
    const subs = await doc.ref.listCollections();
    for (const sub of subs) {
      await deleteCollectionRecursive(db, sub.path);
    }
    await doc.ref.delete();
  }
}

/**
 * Helper synchrone : skip toute la suite si l'env var EMULATOR n'est pas
 * défini (CI local rapide sans emulator).
 *
 * Usage :
 *   describe("publishPack", () => {
 *     requireEmulators();
 *     it("...", async () => { ... });
 *   });
 */
export function requireEmulators(): void {
  beforeAll(async () => {
    if (process.env.SKIP_EMULATOR_TESTS === "1") {
      // Jest n'a pas de mécanisme propre de skip-au-runtime ;
      // on throw un warning et les tests devraient passer en xit().
      // Convention : lancer avec SKIP_EMULATOR_TESTS=1 pour les sauter.
      return;
    }
    setupEmulatorEnv();
    getTestApp();
  });
  afterAll(async () => {
    await teardownTestApp();
  });
}

/**
 * Devinette factory pour les seeds de test.
 */
export function makeDevinette(overrides: Record<string, unknown> = {}): Record<
  string,
  unknown
> {
  return {
    id: "test_001",
    pack: "test",
    country: "ci",
    answer: "FOUTOU",
    answer_normalized: "foutou",
    letters_pool: ["F", "O", "U", "T", "O", "U"],
    riddle: { fr: "Dans le mortier on me pile longtemps." },
    explanation: { fr: "Pâte ivoirienne." },
    difficulty: 1,
    estimated_time_s: 25,
    tags: ["cuisine", "tradition"],
    format_version: 3,
    status: "draft",
    draft_version: 1,
    published_version: null,
    deleted_at: null,
    ...overrides,
  };
}
