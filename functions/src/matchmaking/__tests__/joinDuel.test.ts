/**
 * Tests de joinDuel — jointure d'un duel ami / rematch.
 * Couvre la réclamation atomique de la place de 2e joueur (anti match à 3),
 * le contrôle `target_uid` (défi ciblé) et le nettoyage du match tronqué
 * quand le créateur supprime pendant le join.
 * RTDB mocké (arbre clé->valeur par path exact).
 */

export {};

// --- RTDB mock ---
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
      // Simule l'application des writes sur le noeud du match : nécessaire
      // car joinDuel re-lit le match après son update.
      const cur = (rtdbData.get(path) as Record<string, unknown>) ?? {};
      const next = { ...cur };
      for (const [k, v] of Object.entries(obj)) {
        if (k.includes("/")) {
          // Chemin imbriqué type players/{uid} : on ne matérialise que le
          // premier niveau (suffisant pour ces tests).
          const [head] = k.split("/");
          next[head] = { ...((next[head] as object) ?? {}), __nested: true };
        } else {
          next[k] = v;
        }
      }
      rtdbData.set(path, next);
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
const { joinDuel } = require("../joinDuel");

const MID = "ABC123";

function setMatch(overrides: Record<string, unknown> = {}) {
  rtdbData.set(`matches/${MID}`, {
    match_id: MID,
    created_by: "creator",
    phase: "waiting",
    secret: "S3CRET",
    rounds: { 0: { riddle: "r" } },
    players: { creator: { rounds_won: 0 } },
    ...overrides,
  });
}

async function call(uid: string, secret?: string) {
  return joinDuel({
    auth: { uid },
    data: { matchId: MID, secret, protocol_version: 2 },
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  rtdbData.clear();
  updateCalls.length = 0;
  removed.length = 0;
});

describe("joinDuel", () => {
  test("jointure normale -> countdown + joueur ajouté + claim posé", async () => {
    setMatch();

    const res = await call("friend", "S3CRET");

    expect(res.ok).toBe(true);
    expect(rtdbData.get(`matches/${MID}/joiner_uid`)).toBe("friend");
    const write = updateCalls.find((u) => u.phase === "countdown")!;
    expect(write).toBeDefined();
    expect(write["players/friend"]).toBeDefined();
  });

  test("créateur ou joueur déjà présent -> no-op idempotent", async () => {
    setMatch();

    const res = await call("creator");
    expect(res.ok).toBe(true);
    expect(updateCalls).toHaveLength(0);
    expect(rtdbData.get(`matches/${MID}/joiner_uid`)).toBeUndefined();
  });

  test("secret invalide -> permission-denied", async () => {
    setMatch();
    await expect(call("friend", "WRONG")).rejects.toMatchObject({
      code: "permission-denied",
    });
  });

  test("match introuvable -> duel_not_found", async () => {
    await expect(call("friend")).rejects.toMatchObject({
      code: "not-found",
    });
  });

  test("défi ciblé : seul le destinataire peut rejoindre", async () => {
    setMatch({ target_uid: "invitee" });

    await expect(call("intruder")).rejects.toMatchObject({
      code: "permission-denied",
      message: "duel_reserved",
    });

    const res = await call("invitee");
    expect(res.ok).toBe(true);
  });

  test("match plein (2 joueurs) -> duel_full", async () => {
    setMatch({ players: { creator: {}, friend: {} } });
    await expect(call("third")).rejects.toMatchObject({
      code: "failed-precondition",
      message: "duel_full",
    });
  });

  test("course : place déjà réclamée par un autre uid -> duel_full, pas d'écriture", async () => {
    setMatch();
    // Un 2e ami a passé le check players.length en même temps et a réclamé
    // la place juste avant nous.
    rtdbData.set(`matches/${MID}/joiner_uid`, "friend1");

    await expect(call("friend2")).rejects.toMatchObject({
      code: "failed-precondition",
      message: "duel_full",
    });
    expect(updateCalls).toHaveLength(0);
    expect(rtdbData.get(`matches/${MID}/joiner_uid`)).toBe("friend1");
  });

  test("retry réseau : claim déjà à notre uid -> continue normalement", async () => {
    setMatch();
    rtdbData.set(`matches/${MID}/joiner_uid`, "friend");

    const res = await call("friend", "S3CRET");
    expect(res.ok).toBe(true);
    expect(updateCalls.find((u) => u.phase === "countdown")).toBeDefined();
  });

  test("créateur supprime pendant le join -> nettoyage du nœud tronqué + duel_expired", async () => {
    setMatch();
    // Simule la suppression entre la lecture initiale et l'update : le get
    // initial voit le match, puis on vide le nœud AVANT que l'update du join
    // ne le recrée tronqué. On intercepte via un état sans `rounds`.
    rtdbData.set(`matches/${MID}`, {
      // Nœud tel que recréé par un update sur un chemin supprimé : seuls les
      // champs écrits par joinDuel existent.
      phase: "waiting",
      players: { creator: {} },
      created_by: "creator",
      secret: "S3CRET",
      // pas de rounds
    });

    await expect(call("friend", "S3CRET")).rejects.toMatchObject({
      code: "failed-precondition",
      message: "duel_expired",
    });
    expect(removed).toContain(`matches/${MID}`);
  });
});
