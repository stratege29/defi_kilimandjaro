/**
 * Tests de requestArenaMatch — appariement par points dans un tournoi.
 * RTDB et Firestore mockés ; devinettesCache mocké pour éviter Firestore.
 */

// --- RTDB mock (arbre clé->valeur par path exact) ---
const rtdbData = new Map<string, unknown>();
const updateCalls: Array<Record<string, unknown>> = [];
const removed: string[] = [];

function dbRef(path = "") {
  return {
    get: async () => {
      const v = rtdbData.get(path);
      return { exists: () => v !== undefined && v !== null, val: () => v };
    },
    update: async (obj: Record<string, unknown>) => {
      updateCalls.push(obj);
    },
    remove: async () => {
      removed.push(path);
      rtdbData.delete(path);
    },
  };
}

jest.mock("firebase-admin/database", () => ({
  getDatabase: () => ({ ref: (p?: string) => dbRef(p ?? "") }),
  ServerValue: { TIMESTAMP: 1 },
}));

// --- Firestore mock (tournoi + participant) ---
const fsData = new Map<string, { exists: boolean; data: () => Record<string, unknown> }>();
function fsRef(path: string): {
  path: string;
  collection: (c: string) => ReturnType<typeof fsRef>;
  doc: (d: string) => ReturnType<typeof fsRef>;
  get: () => Promise<{ exists: boolean; data: () => Record<string, unknown> }>;
} {
  return {
    path,
    collection: (c: string) => fsRef(`${path}/${c}`),
    doc: (d: string) => fsRef(`${path}/${d}`),
    get: async () =>
      fsData.get(path) ?? { exists: false, data: () => ({}) },
  };
}
jest.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({ collection: (c: string) => fsRef(c) }),
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

// --- devinettesCache mock ---
jest.mock("../../matchmaking/devinettesCache", () => ({
  _loadDevinettesCache: jest.fn().mockResolvedValue(new Map()),
  _pickThreeRounds: jest.fn().mockReturnValue([
    { answer: "KORA", letters_pool: ["K"], riddle: "r0", explanation: "e", proverb: "", difficulty: "easy", devinette_id: "d0" },
    { answer: "SAVANE", letters_pool: ["S"], riddle: "r1", explanation: "e", proverb: "", difficulty: "medium", devinette_id: "d1" },
    { answer: "CALEBASSE", letters_pool: ["C"], riddle: "r2", explanation: "e", proverb: "", difficulty: "hard", devinette_id: "d2" },
  ]),
  answersFromRounds: jest.fn().mockReturnValue({ 0: "KORA", 1: "SAVANE", 2: "CALEBASSE" }),
  toPublicRound: (r: Record<string, unknown>) => {
    const { answer: _a, ...rest } = r;
    void _a;
    return rest;
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
const { requestArenaMatch } = require("../requestArenaMatch");

const TID = "T1";

function setLiveTournament() {
  fsData.set(`tournaments/${TID}`, {
    exists: true,
    data: () => ({
      status: "live",
      start_at: 1,
      end_at: 10_000_000_000_000,
    }),
  });
}
function setParticipant(uid: string, points: number) {
  fsData.set(`tournaments/${TID}/participants/${uid}`, {
    exists: true,
    data: () => ({ points }),
  });
}

async function call(uid: string, requestId = "r1", step = 0) {
  return requestArenaMatch({
    auth: { uid },
    data: {
      tournament_id: TID,
      request_id: requestId,
      expansion_step: step,
      protocol_version: 2,
    },
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  rtdbData.clear();
  fsData.clear();
  updateCalls.length = 0;
  removed.length = 0;
});

describe("requestArenaMatch", () => {
  test("pas d'adversaire -> waiting + entrée pool écrite", async () => {
    setLiveTournament();
    setParticipant("me", 5);

    const res = await call("me");

    expect(res.status).toBe("waiting");
    const poolWrite = updateCalls.find((u) => `arena/${TID}/pool/me` in u);
    expect(poolWrite).toBeDefined();
    expect((poolWrite as Record<string, { points: number }>)[`arena/${TID}/pool/me`].points).toBe(5);
  });

  test("adversaire frais dans la bande -> match créé (tournament_id, is_ranked false)", async () => {
    setLiveTournament();
    setParticipant("me", 6);
    const now = Date.now();
    // opponent dans le pool, points proches (diff 2 <= band 4) + présence fraîche
    rtdbData.set(`arena/${TID}/pool`, {
      opp: { points: 8, ts: now },
    });
    rtdbData.set("presence", { opp: { ts: now } });

    const res = await call("me");

    expect(res.status).toBe("matched");
    expect(res.matchId).toBeDefined();
    expect(res.matchData.tournament_id).toBe(TID);
    expect(res.matchData.is_ranked).toBe(false);
    expect(res.matchData.phase).toBe("countdown");
    expect(Object.keys(res.matchData.players)).toEqual(
      expect.arrayContaining(["me", "opp"])
    );

    // L'écriture atomique retire les 2 du pool et pose les pointeurs actifs.
    const atomic = updateCalls.find((u) => `matches/${res.matchId}` in u)!;
    expect(atomic[`arena/${TID}/pool/me`]).toBeNull();
    expect(atomic[`arena/${TID}/pool/opp`]).toBeNull();
    expect(atomic[`arena/${TID}/active/me`]).toBe(res.matchId);
    expect(atomic[`arena/${TID}/active/opp`]).toBe(res.matchId);
  });

  test("adversaire hors bande -> waiting (pas de match)", async () => {
    setLiveTournament();
    setParticipant("me", 0);
    const now = Date.now();
    rtdbData.set(`arena/${TID}/pool`, { opp: { points: 100, ts: now } }); // diff 100 > band 4
    rtdbData.set("presence", { opp: { ts: now } });

    const res = await call("me");
    expect(res.status).toBe("waiting");
  });

  test("adversaire périmé (présence absente) -> waiting + nettoyage ghost", async () => {
    setLiveTournament();
    setParticipant("me", 5);
    rtdbData.set(`arena/${TID}/pool`, { ghost: { points: 5, ts: 1 } });
    rtdbData.set("presence", {}); // ghost pas frais

    const res = await call("me");
    expect(res.status).toBe("waiting");
    const cleanup = updateCalls.find((u) => `arena/${TID}/pool/ghost` in u);
    expect(cleanup).toBeDefined();
    expect((cleanup as Record<string, unknown>)[`arena/${TID}/pool/ghost`]).toBeNull();
  });

  test("match actif en cours -> rejoin idempotent (pas de nouveau match)", async () => {
    setLiveTournament();
    setParticipant("me", 5);
    rtdbData.set(`arena/${TID}/active/me`, "OLD123");
    rtdbData.set("matches/OLD123", { phase: "active", tournament_id: TID });

    const res = await call("me");
    expect(res.status).toBe("matched");
    expect(res.matchId).toBe("OLD123");
    // Aucun nouveau match écrit.
    expect(updateCalls.find((u) => Object.keys(u).some((k) => k.startsWith("matches/") && k !== "matches/OLD123"))).toBeUndefined();
  });

  test("refus si participant non inscrit", async () => {
    setLiveTournament();
    // pas de participant "me"
    await expect(call("me")).rejects.toMatchObject({
      code: "failed-precondition",
    });
  });

  test("refus si tournoi pas live", async () => {
    fsData.set(`tournaments/${TID}`, {
      exists: true,
      data: () => ({ status: "scheduled", start_at: 1, end_at: 10_000_000_000_000 }),
    });
    setParticipant("me", 0);
    await expect(call("me")).rejects.toMatchObject({
      code: "failed-precondition",
    });
  });
});
