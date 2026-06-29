/**
 * Tests de settleTournamentMatch — règlement serveur-autoritaire des points de
 * tournoi depuis tout chemin de finalisation. RTDB + awardTournamentPoints mockés.
 */

export {};

// État mutable piloté par chaque test.
const state: {
  match: Record<string, unknown> | null;
  settledCommitted: boolean;
} = { match: null, settledCommitted: true };

const settledSet = jest.fn();

jest.mock("firebase-admin/database", () => ({
  getDatabase: () => ({
    ref: (path: string) => {
      if (path.endsWith("/settled")) {
        return {
          transaction: async (fn: (cur: unknown) => unknown) => {
            // Simule le verrou : committed selon l'état du test.
            void fn(state.settledCommitted ? undefined : true);
            return { committed: state.settledCommitted };
          },
          set: settledSet,
        };
      }
      // ref(`matches/{id}`)
      return {
        get: async () => ({
          exists: () => state.match !== null,
          val: () => state.match,
        }),
      };
    },
  }),
}));

const awardMock = jest.fn();
jest.mock("../awardTournamentPoints", () => ({
  awardTournamentPoints: (...args: unknown[]) => awardMock(...args),
}));

jest.mock("firebase-functions/v2", () => ({
  logger: { error: jest.fn(), info: jest.fn(), warn: jest.fn() },
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { settleTournamentMatch } = require("../settleTournamentMatch");

beforeEach(() => {
  jest.clearAllMocks();
  state.match = null;
  state.settledCommitted = true;
});

describe("settleTournamentMatch", () => {
  test("no-op si match absent", async () => {
    state.match = null;
    await settleTournamentMatch("M");
    expect(awardMock).not.toHaveBeenCalled();
  });

  test("no-op si pas un match de tournoi (tournament_id absent)", async () => {
    state.match = {
      phase: "finished",
      winner: "a",
      players: { a: {}, b: {} },
    };
    await settleTournamentMatch("M");
    expect(awardMock).not.toHaveBeenCalled();
  });

  test("no-op si pas encore finished", async () => {
    state.match = {
      phase: "active",
      tournament_id: "T1",
      players: { a: {}, b: {} },
    };
    await settleTournamentMatch("M");
    expect(awardMock).not.toHaveBeenCalled();
  });

  test("match de tournoi finished → award appelé une fois avec le bon winner", async () => {
    state.match = {
      phase: "finished",
      tournament_id: "T1",
      winner: "a",
      created_at: 1000,
      players: { a: {}, b: {} },
    };
    state.settledCommitted = true;
    await settleTournamentMatch("M");
    expect(awardMock).toHaveBeenCalledTimes(1);
    expect(awardMock).toHaveBeenCalledWith(
      expect.objectContaining({
        tournamentId: "T1",
        matchId: "M",
        winnerUid: "a",
        matchCreatedAt: 1000,
      }),
    );
  });

  test("nul (winner vide) → winnerUid null", async () => {
    state.match = {
      phase: "finished",
      tournament_id: "T1",
      winner: "",
      players: { a: {}, b: {} },
    };
    await settleTournamentMatch("M");
    expect(awardMock).toHaveBeenCalledWith(
      expect.objectContaining({ winnerUid: null }),
    );
  });

  test("idempotence : verrou déjà posé → pas de second award", async () => {
    state.match = {
      phase: "finished",
      tournament_id: "T1",
      winner: "a",
      players: { a: {}, b: {} },
    };
    state.settledCommitted = false; // transaction n'obtient pas le verrou
    await settleTournamentMatch("M");
    expect(awardMock).not.toHaveBeenCalled();
  });
});
