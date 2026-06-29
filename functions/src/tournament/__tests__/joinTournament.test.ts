/**
 * Tests de joinTournament — inscription + plafond max_participants.
 * Firestore mocké (profil hors tx + transaction).
 */

export {};

type FakeRef = {
  path: string;
  collection: (c: string) => FakeRef;
  doc: (d: string) => FakeRef;
  get: () => Promise<{ exists: boolean; data: () => Record<string, unknown> }>;
};

const fsData = new Map<
  string,
  { exists: boolean; data: () => Record<string, unknown> }
>();
const txSet = jest.fn();
const txUpdate = jest.fn();

function makeRef(path: string): FakeRef {
  return {
    path,
    collection: (c: string) => makeRef(`${path}/${c}`),
    doc: (d: string) => makeRef(`${path}/${d}`),
    get: async () => fsData.get(path) ?? { exists: false, data: () => ({}) },
  };
}

const fakeDb = {
  collection: (c: string) => makeRef(c),
  runTransaction: async (fn: (tx: unknown) => Promise<unknown>) => {
    const tx = {
      get: async (ref: FakeRef) =>
        fsData.get(ref.path) ?? { exists: false, data: () => ({}) },
      set: txSet,
      update: txUpdate,
    };
    return fn(tx);
  },
};

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: () => fakeDb,
  FieldValue: {
    increment: (n: number) => ({ __inc: n }),
    serverTimestamp: () => "TS",
  },
  Timestamp: class {
    constructor(public ms: number) {}
    toMillis() {
      return this.ms;
    }
  },
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: (_opts: unknown, fn: unknown) => fn,
  HttpsError: class HttpsError extends Error {
    constructor(public code: string, message: string) {
      super(message);
    }
  },
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { joinTournament } = require("../joinTournament");

const TID = "T1";
const UID = "U1";
const FAR_FUTURE = 10_000_000_000_000;

function setTournament(over: Record<string, unknown> = {}) {
  fsData.set(`tournaments/${TID}`, {
    exists: true,
    data: () => ({
      status: "live",
      end_at: FAR_FUTURE,
      participant_count: 0,
      max_participants: 200,
      ...over,
    }),
  });
}
function setProfile() {
  fsData.set(`profiles/${UID}`, {
    exists: true,
    data: () => ({ display_name: "Kacou", avatar_id: "a1" }),
  });
}
function call(uid = UID) {
  return joinTournament({ auth: { uid }, data: { tournament_id: TID } });
}

beforeEach(() => {
  jest.clearAllMocks();
  fsData.clear();
});

describe("joinTournament", () => {
  test("inscription normale : crée le participant + incrémente le compteur", async () => {
    setTournament({ participant_count: 5 });
    setProfile();

    const res = await call();
    expect(res).toMatchObject({ joined: true, already: false });
    expect(txSet).toHaveBeenCalledWith(
      expect.objectContaining({ path: `tournaments/${TID}/participants/${UID}` }),
      expect.objectContaining({ uid: UID, display_name: "Kacou", points: 0 }),
    );
    expect(txUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ path: `tournaments/${TID}` }),
      expect.objectContaining({ participant_count: { __inc: 1 } }),
    );
  });

  test("plafond atteint : refus resource-exhausted", async () => {
    setTournament({ participant_count: 200, max_participants: 200 });
    setProfile();

    await expect(call()).rejects.toMatchObject({ code: "resource-exhausted" });
    expect(txSet).not.toHaveBeenCalled();
  });

  test("déjà inscrit : idempotent même si plafond atteint", async () => {
    setTournament({ participant_count: 200, max_participants: 200 });
    setProfile();
    fsData.set(`tournaments/${TID}/participants/${UID}`, {
      exists: true,
      data: () => ({ uid: UID, points: 4 }),
    });

    const res = await call();
    expect(res).toMatchObject({ joined: true, already: true });
    expect(txSet).not.toHaveBeenCalled();
  });

  test("tournoi terminé : refus failed-precondition", async () => {
    setTournament({ status: "finished" });
    setProfile();
    await expect(call()).rejects.toMatchObject({ code: "failed-precondition" });
  });
});
