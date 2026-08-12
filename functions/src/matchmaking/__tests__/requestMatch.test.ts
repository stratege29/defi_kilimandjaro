/**
 * Tests de requestMatch — matchmaking classé /lobby.
 * Couvre surtout l'appariement anti-course porté de requestArenaMatch :
 * symétrie par uid + réclamation atomique de `lobby/{adversaire}/matched_to`.
 * RTDB et Firestore mockés ; devinettesCache mocké pour éviter Firestore.
 */

export {};

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
    transaction: async (fn: (cur: unknown) => unknown) => {
      const cur = rtdbData.has(path) ? rtdbData.get(path) : undefined;
      const next = fn(cur);
      if (next === undefined) {
        return { committed: false, snapshot: { val: () => cur } };
      }
      rtdbData.set(path, next);
      return { committed: true, snapshot: { val: () => next } };
    },
  };
}

jest.mock("firebase-admin/database", () => ({
  getDatabase: () => ({ ref: (p?: string) => dbRef(p ?? "") }),
  ServerValue: { TIMESTAMP: 1 },
}));

// --- Firestore mock (profils ELO) ---
const fsData = new Map<
  string,
  { exists: boolean; data: () => Record<string, unknown> }
>();
function fsRef(path: string): {
  path: string;
  collection: (c: string) => ReturnType<typeof fsRef>;
  doc: (d: string) => ReturnType<typeof fsRef>;
  get: () => Promise<{ exists: boolean; data: () => Record<string, unknown> }>;
  set: (data: Record<string, unknown>, opts?: unknown) => Promise<void>;
} {
  return {
    path,
    collection: (c: string) => fsRef(`${path}/${c}`),
    doc: (d: string) => fsRef(`${path}/${d}`),
    get: async () => fsData.get(path) ?? { exists: false, data: () => ({}) },
    set: async (data: Record<string, unknown>) => {
      fsData.set(path, { exists: true, data: () => data });
    },
  };
}
jest.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({ collection: (c: string) => fsRef(c) }),
  FieldValue: {
    increment: (n: number) => ({ __inc: n }),
    serverTimestamp: () => "TS",
  },
}));

// --- devinettesCache mock ---
jest.mock("../devinettesCache", () => ({
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
const { requestMatch } = require("../requestMatch");

function setProfile(uid: string, elo: number) {
  fsData.set(`profiles/${uid}`, { exists: true, data: () => ({ elo }) });
}

function setWaitingOpponent(uid: string, mmr: number) {
  const now = Date.now();
  rtdbData.set("lobby", { [uid]: { mmr, ts: now, request_id: "rx" } });
  rtdbData.set("presence", { [uid]: { ts: now } });
}

async function call(uid: string, requestId = "r1") {
  return requestMatch({
    auth: { uid },
    data: { request_id: requestId, protocol_version: 2 },
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  rtdbData.clear();
  fsData.clear();
  updateCalls.length = 0;
  removed.length = 0;
});

describe("requestMatch — anti-course", () => {
  test("pas d'adversaire -> waiting, entrée lobby écrite champ par champ (préserve matched_to)", async () => {
    setProfile("me", 1000);

    const res = await call("me");

    expect(res.status).toBe("waiting");
    const lobbyWrite = updateCalls.find((u) => "lobby/me/mmr" in u)!;
    expect(lobbyWrite).toBeDefined();
    expect(lobbyWrite["lobby/me/mmr"]).toBe(1000);
    expect(lobbyWrite["lobby/me/ts"]).toBeDefined();
    expect(lobbyWrite["lobby/me/request_id"]).toBe("r1");
    // Jamais de `set` du nœud entier : un matched_to concurrent survivrait.
    expect(updateCalls.find((u) => "lobby/me" in u)).toBeUndefined();
  });

  test("uid plus petit que l'adversaire -> crée le match et le réclame atomiquement", async () => {
    setProfile("aaa", 1000);
    setWaitingOpponent("zzz", 1010);

    const res = await call("aaa");

    expect(res.status).toBe("matched");
    expect(res.matchId).toBeDefined();
    // La réclamation a posé le pointeur pour le joueur passif.
    expect(rtdbData.get("lobby/zzz/matched_to")).toBe(res.matchId);
    // Le match + les réponses serveur-only ont été écrits.
    const matchWrite = updateCalls.find((u) => `matches/${res.matchId}` in u)!;
    expect(matchWrite).toBeDefined();
    expect(matchWrite[`match_answers/${res.matchId}`]).toBeDefined();
    // L'entrée lobby du créateur est retirée.
    expect(removed).toContain("lobby/aaa");
    expect(Object.keys(res.matchData.players)).toEqual(
      expect.arrayContaining(["aaa", "zzz"])
    );
  });

  test("symétrie : uid plus grand ne crée pas, attend en lobby", async () => {
    setProfile("zzz", 1000);
    setWaitingOpponent("aaa", 1010);

    const res = await call("zzz");

    expect(res.status).toBe("waiting");
    expect(
      updateCalls.find((u) =>
        Object.keys(u).some((k) => k.startsWith("matches/"))
      )
    ).toBeUndefined();
    expect(updateCalls.find((u) => "lobby/zzz/mmr" in u)).toBeDefined();
  });

  test("réclamation perdue (adversaire déjà réclamé) -> match pré-créé annulé + waiting", async () => {
    setProfile("aaa", 1000);
    setWaitingOpponent("zzz", 1010);
    // Un créateur concurrent a déjà réclamé zzz.
    rtdbData.set("lobby/zzz/matched_to", "OTHER1");

    const res = await call("aaa");

    expect(res.status).toBe("waiting");
    // Le pointeur du concurrent n'a pas été écrasé.
    expect(rtdbData.get("lobby/zzz/matched_to")).toBe("OTHER1");
    // Le match pré-créé a été annulé (matches/{id} + match_answers/{id} -> null).
    const rollback = updateCalls.find((u) =>
      Object.entries(u).some(
        ([k, v]) => k.startsWith("matches/") && v === null
      )
    )!;
    expect(rollback).toBeDefined();
    expect(
      Object.entries(rollback).some(
        ([k, v]) => k.startsWith("match_answers/") && v === null
      )
    ).toBe(true);
    // Et l'appelant est retombé en attente.
    expect(updateCalls.find((u) => "lobby/aaa/mmr" in u)).toBeDefined();
  });

  test("joueur passif notifié via matched_to -> matched direct sans nouveau match", async () => {
    setProfile("me", 1000);
    rtdbData.set("lobby/me", { ts: Date.now(), request_id: "r1", matched_to: "M1" });
    rtdbData.set("matches/M1", { phase: "countdown", match_id: "M1" });

    const res = await call("me");

    expect(res.status).toBe("matched");
    expect(res.matchId).toBe("M1");
    expect(removed).toContain("lobby/me");
    expect(
      updateCalls.find((u) =>
        Object.keys(u).some((k) => k.startsWith("matches/"))
      )
    ).toBeUndefined();
  });
});
