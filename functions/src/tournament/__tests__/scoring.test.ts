/**
 * Tests de la logique pure de scoring du tournoi (points, série, classement,
 * récompenses). Aucun Firebase requis.
 */

import {
  DEFAULT_SCORING,
  resolveScoringConfig,
  pointsForOutcome,
  outcomeFor,
  rankParticipants,
  rewardForRank,
  type ParticipantScore,
} from "../scoring";

describe("pointsForOutcome", () => {
  const cfg = DEFAULT_SCORING; // win 3, draw 1, streak_min 2, mult 2

  test("victoire simple (1re) = points_win, série -> 1", () => {
    expect(pointsForOutcome("win", 0, cfg)).toEqual({
      points: 3,
      newStreak: 1,
    });
  });

  test("2e victoire consécutive déclenche le bonus (×2)", () => {
    expect(pointsForOutcome("win", 1, cfg)).toEqual({
      points: 6,
      newStreak: 2,
    });
  });

  test("nul = points_draw, série remise à 0", () => {
    expect(pointsForOutcome("draw", 5, cfg)).toEqual({
      points: 1,
      newStreak: 0,
    });
  });

  test("défaite = 0 point, série remise à 0", () => {
    expect(pointsForOutcome("loss", 3, cfg)).toEqual({
      points: 0,
      newStreak: 0,
    });
  });

  test("config personnalisée respectée", () => {
    const custom = resolveScoringConfig({
      points_win: 5,
      streak_min: 3,
      streak_mult: 3,
    });
    expect(custom.points_draw).toBe(DEFAULT_SCORING.points_draw); // défaut conservé
    expect(pointsForOutcome("win", 1, custom)).toEqual({
      points: 5,
      newStreak: 2,
    }); // pas encore le bonus (streak_min 3)
    expect(pointsForOutcome("win", 2, custom)).toEqual({
      points: 15,
      newStreak: 3,
    }); // bonus ×3
  });
});

describe("outcomeFor", () => {
  test("vainqueur / perdant / nul", () => {
    expect(outcomeFor("A", "A")).toBe("win");
    expect(outcomeFor("B", "A")).toBe("loss");
    expect(outcomeFor("A", null)).toBe("draw");
  });
});

describe("rankParticipants", () => {
  test("trie par points desc, puis victoires, puis dernier match le plus tôt", () => {
    const parts: ParticipantScore[] = [
      { uid: "low", points: 5, wins: 1, last_match_at: 100 },
      { uid: "high", points: 12, wins: 4, last_match_at: 300 },
      { uid: "mid_late", points: 8, wins: 2, last_match_at: 500 },
      { uid: "mid_early", points: 8, wins: 2, last_match_at: 200 },
    ];
    const ranked = rankParticipants(parts);
    expect(ranked.map((p) => p.uid)).toEqual([
      "high",
      "mid_early", // même points/wins que mid_late mais a fini plus tôt
      "mid_late",
      "low",
    ]);
    expect(ranked.map((p) => p.rank)).toEqual([1, 2, 3, 4]);
  });

  test("départage par victoires à points égaux", () => {
    const ranked = rankParticipants([
      { uid: "fewer_wins", points: 10, wins: 2, last_match_at: 100 },
      { uid: "more_wins", points: 10, wins: 4, last_match_at: 100 },
    ]);
    expect(ranked[0].uid).toBe("more_wins");
  });
});

describe("rewardForRank", () => {
  const tiers = [
    { rank_min: 1, rank_max: 1, cauris: 500, badge_id: "gold" },
    { rank_min: 2, rank_max: 3, cauris: 250, badge_id: "silver" },
    { rank_min: 4, rank_max: 10, cauris: 100, badge_id: null },
  ];

  test("rang 1 -> palier or", () => {
    expect(rewardForRank(1, tiers)).toEqual({ cauris: 500, badge_id: "gold" });
  });
  test("rang 3 -> palier argent (intervalle)", () => {
    expect(rewardForRank(3, tiers)).toEqual({ cauris: 250, badge_id: "silver" });
  });
  test("rang hors paliers -> rien", () => {
    expect(rewardForRank(50, tiers)).toEqual({ cauris: 0, badge_id: null });
  });
  test("paliers absents -> rien", () => {
    expect(rewardForRank(1, undefined)).toEqual({ cauris: 0, badge_id: null });
  });
});
