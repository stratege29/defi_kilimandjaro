/**
 * scoring — logique PURE du tournoi « arène » (testable sans Firebase).
 *
 * Le scoring du tournoi est en POINTS D'ARÈNE, indépendant de l'ELO global
 * (un match de tournoi ne modifie jamais l'ELO). Barème par défaut façon
 * chess.com : victoire +3, nul +1, défaite 0, avec bonus de série (« on fire »)
 * qui multiplie les points de victoire à partir de la N-ième victoire d'affilée.
 *
 * Toutes les fonctions ici sont déterministes et sans I/O — voir
 * `awardTournamentPoints.ts` et `tournamentTicker.ts` pour l'application en base.
 */

export type MatchOutcome = "win" | "draw" | "loss";

/** Barème configurable par tournoi (champs du doc Firestore `tournaments/{id}`). */
export interface TournamentScoringConfig {
  /** Points pour une victoire (hors bonus de série). */
  points_win: number;
  /** Points pour un nul. */
  points_draw: number;
  /** Longueur de série (victoires consécutives) à partir de laquelle le bonus
   *  s'applique. Ex : 2 => la 2e victoire consécutive et les suivantes sont
   *  multipliées. */
  streak_min: number;
  /** Multiplicateur appliqué aux points de victoire quand la série est active. */
  streak_mult: number;
}

export const DEFAULT_SCORING: TournamentScoringConfig = {
  points_win: 3,
  points_draw: 1,
  streak_min: 2,
  streak_mult: 2,
};

/** Normalise une config partielle (doc Firestore) en config complète. */
export function resolveScoringConfig(
  raw: Partial<TournamentScoringConfig> | undefined | null
): TournamentScoringConfig {
  const r = raw ?? {};
  return {
    points_win: numOr(r.points_win, DEFAULT_SCORING.points_win),
    points_draw: numOr(r.points_draw, DEFAULT_SCORING.points_draw),
    streak_min: numOr(r.streak_min, DEFAULT_SCORING.streak_min),
    streak_mult: numOr(r.streak_mult, DEFAULT_SCORING.streak_mult),
  };
}

function numOr(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

/**
 * Points gagnés et nouvelle série après UN match, en fonction du résultat et de
 * la série en cours AVANT ce match.
 *
 * - win  : `points_win` (×`streak_mult` si la nouvelle série ≥ `streak_min`),
 *          série incrémentée.
 * - draw : `points_draw`, série remise à 0.
 * - loss : 0 point, série remise à 0.
 */
export function pointsForOutcome(
  outcome: MatchOutcome,
  priorStreak: number,
  cfg: TournamentScoringConfig
): { points: number; newStreak: number } {
  if (outcome === "win") {
    const newStreak = priorStreak + 1;
    const onFire = newStreak >= cfg.streak_min;
    const points = onFire
      ? cfg.points_win * cfg.streak_mult
      : cfg.points_win;
    return { points, newStreak };
  }
  if (outcome === "draw") {
    return { points: cfg.points_draw, newStreak: 0 };
  }
  return { points: 0, newStreak: 0 };
}

/** Déduit le résultat d'un joueur à partir du vainqueur enregistré (null = nul). */
export function outcomeFor(
  uid: string,
  winnerUid: string | null
): MatchOutcome {
  if (winnerUid === null) return "draw";
  return uid === winnerUid ? "win" : "loss";
}

// ---------------------------------------------------------------------------
// Classement final
// ---------------------------------------------------------------------------

export interface ParticipantScore {
  uid: string;
  points: number;
  wins: number;
  /** Timestamp (ms) du dernier match joué — départage à égalité (qui a atteint
   *  son score en premier passe devant). 0 si aucun match. */
  last_match_at: number;
}

export interface RankedParticipant extends ParticipantScore {
  rank: number;
}

/**
 * Classe les participants : points desc, puis nombre de victoires desc, puis
 * dernier match le plus tôt (a atteint son score en premier), puis uid pour un
 * ordre stable et déterministe. Le rang est 1-indexé (ex aequo non gérés :
 * chaque participant a un rang distinct, cohérent avec un classement « arène »).
 */
export function rankParticipants(
  parts: ParticipantScore[]
): RankedParticipant[] {
  const sorted = [...parts].sort(
    (a, b) =>
      b.points - a.points ||
      b.wins - a.wins ||
      a.last_match_at - b.last_match_at ||
      (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0)
  );
  return sorted.map((p, i) => ({ ...p, rank: i + 1 }));
}

// ---------------------------------------------------------------------------
// Récompenses par rang
// ---------------------------------------------------------------------------

export interface RewardTier {
  rank_min: number;
  rank_max: number;
  cauris?: number;
  badge_id?: string | null;
}

export interface ResolvedReward {
  cauris: number;
  badge_id: string | null;
}

/** Récompense (cauris + badge) pour un rang donné, ou rien si aucun palier ne
 *  couvre ce rang. Le premier palier correspondant gagne. */
export function rewardForRank(
  rank: number,
  tiers: RewardTier[] | undefined | null
): ResolvedReward {
  for (const t of tiers ?? []) {
    if (rank >= t.rank_min && rank <= t.rank_max) {
      return {
        cauris: typeof t.cauris === "number" && t.cauris > 0 ? t.cauris : 0,
        badge_id: t.badge_id ?? null,
      };
    }
  }
  return { cauris: 0, badge_id: null };
}
