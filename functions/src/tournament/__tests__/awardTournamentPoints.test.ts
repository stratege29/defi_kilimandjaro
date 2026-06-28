/**
 * Tests de awardTournamentPoints — attribution transactionnelle des points
 * d'arène aux 2 joueurs. Firestore est mocké (transaction + refs).
 */

// --- Mock firebase-admin/firestore ---
type FakeRef = { path: string; collection: (c: string) => FakeRef; doc: (d: string) => FakeRef };
function makeRef(path: string): FakeRef {
  return {
    path,
    collection: (c: string) => makeRef(`${path}/${c}`),
    doc: (d: string) => makeRef(`${path}/${d}`),
  };
}

const snapMap = new Map<string, { exists: boolean; data: () => Record<string, unknown> }>();
const txUpdate = jest.fn();
const txSet = jest.fn();

const fakeDb = {
  collection: (c: string) => makeRef(c),
  runTransaction: async (fn: (tx: unknown) => Promise<void>) => {
    const tx = {
      get: async (ref: FakeRef) =>
        snapMap.get(ref.path) ?? { exists: false, data: () => ({}) },
      update: txUpdate,
      set: txSet,
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

jest.mock("firebase-functions/v2", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { awardTournamentPoints } = require("../awardTournamentPoints");

const TID = "T1";
const tPath = `tournaments/${TID}`;
const pPath = (uid: string) => `tournaments/${TID}/participants/${uid}`;

function setTournament(over: Record<string, unknown> = {}) {
  snapMap.set(tPath, {
    exists: true,
    data: () => ({
      status: "live",
      finalized: false,
      end_at: 10_000_000_000_000, // très loin dans le futur
      points_win: 3,
      points_draw: 1,
      streak_min: 2,
      streak_mult: 2,
      ...over,
    }),
  });
}

function setParticipant(uid: string, data: Record<string, unknown>) {
  snapMap.set(pPath(uid), { exists: true, data: () => data });
}

beforeEach(() => {
  jest.clearAllMocks();
  snapMap.clear();
});

describe("awardTournamentPoints", () => {
  test("victoire / défaite : winner +3 & wins, loser losses, séries mises à jour", async () => {
    setTournament();
    setParticipant("winner", { current_streak: 0 });
    setParticipant("loser", { current_streak: 1 });

    await awardTournamentPoints({
      tournamentId: TID,
      matchId: "M1",
      players: ["winner", "loser"],
      winnerUid: "winner",
      matchCreatedAt: 1000,
    });

    const winnerUpdate = txUpdate.mock.calls.find(
      (c) => (c[0] as FakeRef).path === pPath("winner")
    )?.[1];
    const loserUpdate = txUpdate.mock.calls.find(
      (c) => (c[0] as FakeRef).path === pPath("loser")
    )?.[1];

    expect(winnerUpdate).toMatchObject({
      points: { __inc: 3 },
      wins: { __inc: 1 },
      matches_played: { __inc: 1 },
      current_streak: 1,
    });
    expect(loserUpdate).toMatchObject({
      points: { __inc: 0 },
      losses: { __inc: 1 },
      current_streak: 0, // défaite remet la série à 0
    });
  });

  test("bonus de série : 2e victoire consécutive = +6", async () => {
    setTournament();
    setParticipant("winner", { current_streak: 1 });
    setParticipant("loser", { current_streak: 0 });

    await awardTournamentPoints({
      tournamentId: TID,
      matchId: "M2",
      players: ["winner", "loser"],
      winnerUid: "winner",
      matchCreatedAt: 1000,
    });

    const winnerUpdate = txUpdate.mock.calls.find(
      (c) => (c[0] as FakeRef).path === pPath("winner")
    )?.[1];
    expect(winnerUpdate).toMatchObject({
      points: { __inc: 6 },
      current_streak: 2,
    });
  });

  test("match nul : +1 chacun, séries à 0", async () => {
    setTournament();
    setParticipant("a", { current_streak: 3 });
    setParticipant("b", { current_streak: 0 });

    await awardTournamentPoints({
      tournamentId: TID,
      matchId: "M3",
      players: ["a", "b"],
      winnerUid: null,
      matchCreatedAt: 1000,
    });

    for (const uid of ["a", "b"]) {
      const u = txUpdate.mock.calls.find(
        (c) => (c[0] as FakeRef).path === pPath(uid)
      )?.[1];
      expect(u).toMatchObject({
        points: { __inc: 1 },
        draws: { __inc: 1 },
        current_streak: 0,
      });
    }
  });

  test("match hors fenêtre (créé après end_at) : aucun point", async () => {
    setTournament({ end_at: 5000 });
    setParticipant("winner", { current_streak: 0 });
    setParticipant("loser", { current_streak: 0 });

    await awardTournamentPoints({
      tournamentId: TID,
      matchId: "M4",
      players: ["winner", "loser"],
      winnerUid: "winner",
      matchCreatedAt: 6000, // >= end_at
    });

    expect(txUpdate).not.toHaveBeenCalled();
    expect(txSet).not.toHaveBeenCalled();
  });

  test("tournoi finalisé : aucun point", async () => {
    setTournament({ finalized: true });
    setParticipant("winner", { current_streak: 0 });
    setParticipant("loser", { current_streak: 0 });

    await awardTournamentPoints({
      tournamentId: TID,
      matchId: "M5",
      players: ["winner", "loser"],
      winnerUid: "winner",
      matchCreatedAt: 1000,
    });

    expect(txUpdate).not.toHaveBeenCalled();
  });

  test("participant absent : création d'une fiche minimale via set", async () => {
    setTournament();
    setParticipant("winner", { current_streak: 0 });
    // loser non inscrit (pas de snap)

    await awardTournamentPoints({
      tournamentId: TID,
      matchId: "M6",
      players: ["winner", "loser"],
      winnerUid: "winner",
      matchCreatedAt: 1000,
    });

    const loserSet = txSet.mock.calls.find(
      (c) => (c[0] as FakeRef).path === pPath("loser")
    );
    expect(loserSet).toBeDefined();
    expect(loserSet?.[1]).toMatchObject({ uid: "loser", losses: 1, points: 0 });
  });
});
