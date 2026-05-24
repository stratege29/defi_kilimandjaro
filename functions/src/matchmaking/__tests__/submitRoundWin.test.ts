/**
 * Tests unitaires de la logique de submitRoundWin.
 *
 * On teste ici la logique pure de calcul du vainqueur final et des transitions
 * de phase, sans Firebase (les appels admin SDK sont mockes).
 */

// ---------------------------------------------------------------------------
// Mock firebase-admin/database avant tout import de la CF.
// ---------------------------------------------------------------------------

const mockUpdate = jest.fn().mockResolvedValue(undefined);
const mockGet = jest.fn();
const mockRef = jest.fn().mockReturnValue({
  get: mockGet,
  update: mockUpdate,
});

jest.mock("firebase-admin/database", () => ({
  getDatabase: jest.fn(() => ({ ref: mockRef })),
}));

// firebase-functions/v2/https est mocke par un stub minimal.
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (_opts: unknown, fn: unknown) => fn,
  HttpsError: class HttpsError extends Error {
    constructor(public code: string, message: string) {
      super(message);
    }
  },
}));

// ---------------------------------------------------------------------------
// Helpers : construit un MatchState RTDB minimal.
// ---------------------------------------------------------------------------

function buildMatchState(overrides: {
  phase?: string;
  current_round?: number;
  total_rounds?: number;
  phase_started_at?: number;
  created_at?: number;
  winner_rounds_won?: number;
  winner_total_time?: number;
  loser_rounds_won?: number;
  loser_total_time?: number;
}) {
  const {
    phase = "active",
    current_round = 0,
    total_rounds = 3,
    phase_started_at = 1700000000000,
    created_at = 1700000000000,
    winner_rounds_won = 0,
    winner_total_time = 0,
    loser_rounds_won = 0,
    loser_total_time = 0,
  } = overrides;

  return {
    phase,
    current_round,
    total_rounds,
    phase_started_at,
    created_at,
    players: {
      winner_uid: {
        progress: 0.5,
        found: false,
        rounds_won: winner_rounds_won,
        total_time_ms: winner_total_time,
        rounds: {},
      },
      loser_uid: {
        progress: 0.2,
        found: false,
        rounds_won: loser_rounds_won,
        total_time_ms: loser_total_time,
        rounds: {},
      },
    },
  };
}

// ---------------------------------------------------------------------------
// Helper : appelle la CF en simulant une requete authentifiee.
// ---------------------------------------------------------------------------

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { submitRoundWin } = require("../submitRoundWin");

async function callSubmitRoundWin(data: {
  match_id: string;
  round: number;
  winner_uid: string;
}) {
  return submitRoundWin({
    auth: { uid: data.winner_uid },
    data,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("submitRoundWin — transitions de phase", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("round 0 sur 3 -> next_phase=countdown, roundEnd", async () => {
    const state = buildMatchState({ current_round: 0 });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    const result = await callSubmitRoundWin({
      match_id: "MATCH1",
      round: 0,
      winner_uid: "winner_uid",
    });

    expect(result.ok).toBe(true);
    expect(result.next_phase).toBe("countdown");
    expect(result.current_round).toBe(1);

    // Doit ecrire roundEnd (pas finished).
    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ phase: "roundEnd" })
    );
    expect(mockUpdate).not.toHaveBeenCalledWith(
      expect.objectContaining({ phase: "finished" })
    );
  });

  test("round 1 sur 3 -> next_phase=countdown, roundEnd", async () => {
    const state = buildMatchState({ current_round: 1 });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    const result = await callSubmitRoundWin({
      match_id: "MATCH2",
      round: 1,
      winner_uid: "winner_uid",
    });

    expect(result.next_phase).toBe("countdown");
    expect(result.current_round).toBe(2);
  });

  test("round 2 (dernier) -> next_phase=finished, winner calcule", async () => {
    const state = buildMatchState({
      current_round: 2,
      winner_rounds_won: 2,
      loser_rounds_won: 0,
    });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    const result = await callSubmitRoundWin({
      match_id: "MATCH3",
      round: 2,
      winner_uid: "winner_uid",
    });

    expect(result.next_phase).toBe("finished");
    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        phase: "finished",
        winner: "winner_uid",
      })
    );
  });

  test("tiebreaker en cas d'egalite de rounds : gagne celui qui a le moins de temps", async () => {
    // winner a 2 rounds mais avec 5000ms de total
    // loser a aussi 2 rounds mais avec 3000ms (plus rapide, donc gagne le tiebreaker)
    const state = buildMatchState({
      current_round: 2,
      winner_rounds_won: 1, // sera 2 apres ce round
      winner_total_time: 5000,
      loser_rounds_won: 2, // loser a deja 2 rounds
      loser_total_time: 3000,
    });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    const result = await callSubmitRoundWin({
      match_id: "MATCH4",
      round: 2,
      winner_uid: "winner_uid",
    });

    // Egalite 2-2, loser a un temps cumule plus court -> loser gagne le tiebreaker.
    expect(result.next_phase).toBe("finished");
    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        phase: "finished",
        winner: "loser_uid",
      })
    );
  });

  test("idempotence : appel 2x avec memes inputs -> no-op au 2e appel", async () => {
    const stateWithAlreadyFound = {
      phase: "roundEnd", // phase a deja change
      current_round: 0,
      total_rounds: 3,
      created_at: 1700000000000,
      players: {
        winner_uid: {
          rounds_won: 1,
          total_time_ms: 5000,
          found: true,
          progress: 1,
          rounds: {
            "0": { progress: 1.0, found: true, finished_at: 1700000005000, time_taken_ms: 5000 },
          },
        },
        loser_uid: { rounds_won: 0, total_time_ms: 0, found: false, progress: 0, rounds: {} },
      },
    };
    mockGet.mockResolvedValueOnce({
      exists: () => true,
      val: () => stateWithAlreadyFound,
    });

    // La phase n'est plus "active" -> doit lancer une erreur failed-precondition.
    await expect(
      callSubmitRoundWin({ match_id: "MATCH5", round: 0, winner_uid: "winner_uid" })
    ).rejects.toMatchObject({ code: "failed-precondition" });

    // Aucun update ne doit avoir ete ecrit.
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  test("refus si le joueur declare une victoire pour un autre uid", async () => {
    await expect(
      submitRoundWin({
        auth: { uid: "attacker_uid" },
        data: { match_id: "M", round: 0, winner_uid: "victim_uid" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("refus si round != current_round", async () => {
    const state = buildMatchState({ current_round: 1 });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    await expect(
      callSubmitRoundWin({ match_id: "M6", round: 0, winner_uid: "winner_uid" })
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("refus si match introuvable", async () => {
    mockGet.mockResolvedValueOnce({ exists: () => false, val: () => null });

    await expect(
      callSubmitRoundWin({ match_id: "NOTFOUND", round: 0, winner_uid: "winner_uid" })
    ).rejects.toMatchObject({ code: "not-found" });
  });
});

// ---------------------------------------------------------------------------
// Tests supplementaires : calcul du rounds_won incremental.
// ---------------------------------------------------------------------------

describe("submitRoundWin — mise a jour des compteurs", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("rounds_won incremente de 1 apres victoire", async () => {
    const state = buildMatchState({ current_round: 0, winner_rounds_won: 0 });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    await callSubmitRoundWin({ match_id: "M7", round: 0, winner_uid: "winner_uid" });

    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        "players/winner_uid/rounds_won": 1,
      })
    );
  });

  test("round result ecrit dans players/winner_uid/rounds/0", async () => {
    const state = buildMatchState({ current_round: 0 });
    mockGet.mockResolvedValueOnce({ exists: () => true, val: () => state });

    await callSubmitRoundWin({ match_id: "M8", round: 0, winner_uid: "winner_uid" });

    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        "players/winner_uid/rounds/0": expect.objectContaining({
          found: true,
          progress: 1.0,
        }),
      })
    );
  });
});
