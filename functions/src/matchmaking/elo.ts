/**
 * Calcul ELO standard pour Kilimandjaro — altitude en mètres.
 *
 * Formule :
 *   expected_winner = 1 / (1 + 10^((elo_loser - elo_winner) / 400))
 *   new_winner = elo_winner + K * (1 - expected_winner)
 *   new_loser  = elo_loser  + K * (0 - (1 - expected_winner))
 *
 * K-factor : 32 (volatilité haute, joueurs ressentent l'impact).
 * ELO initial : 1000 m (altitude de départ).
 * Titre spécial : 5895 m = "Maître du Kilimandjaro" (sommet du boss final).
 */

export const ELO_INITIAL = 1000;
export const ELO_K = 32;
export const ELO_MASTER = 5895;

export interface EloResult {
  /** Nouvel ELO du gagnant (arrondi à l'entier) */
  newWinnerElo: number;
  /** Nouvel ELO du perdant (arrondi à l'entier, min 0) */
  newLoserElo: number;
  /** Delta positif appliqué au gagnant (>0) */
  winnerDelta: number;
  /** Delta négatif appliqué au perdant (<0) */
  loserDelta: number;
}

/**
 * Calcule les nouveaux ELOs après un duel.
 *
 * @param winnerElo - ELO actuel du gagnant en mètres
 * @param loserElo  - ELO actuel du perdant en mètres
 * @param k         - K-factor (défaut 32)
 * @returns EloResult avec les nouveaux ELOs et les deltas
 */
export function calculateElo(
  winnerElo: number,
  loserElo: number,
  k: number = ELO_K
): EloResult {
  const expectedWinner =
    1 / (1 + Math.pow(10, (loserElo - winnerElo) / 400));

  const rawWinnerDelta = k * (1 - expectedWinner);
  const rawLoserDelta = k * (0 - (1 - expectedWinner));

  const winnerDelta = Math.round(rawWinnerDelta);
  const loserDelta = Math.round(rawLoserDelta);

  const newWinnerElo = winnerElo + winnerDelta;
  const newLoserElo = Math.max(0, loserElo + loserDelta);

  return {
    newWinnerElo,
    newLoserElo,
    winnerDelta,
    loserDelta,
  };
}

export interface DrawEloResult {
  newEloA: number;
  newEloB: number;
  deltaA: number;
  deltaB: number;
}

/**
 * Calcule les nouveaux ELOs après un match NUL (score réel 0.5 pour chacun).
 *
 *   delta = round(K * (0.5 - expected))
 *
 * Le joueur le mieux classé perd quelques points, le moins bien classé en
 * gagne quelques-uns (régression vers la moyenne). Si les deux ELOs sont
 * égaux, les deltas valent 0.
 */
export function calculateDrawElo(
  eloA: number,
  eloB: number,
  k: number = ELO_K
): DrawEloResult {
  const expectedA = 1 / (1 + Math.pow(10, (eloB - eloA) / 400));
  const expectedB = 1 - expectedA;

  const deltaA = Math.round(k * (0.5 - expectedA));
  const deltaB = Math.round(k * (0.5 - expectedB));

  return {
    newEloA: Math.max(0, eloA + deltaA),
    newEloB: Math.max(0, eloB + deltaB),
    deltaA,
    deltaB,
  };
}
