/**
 * matchAnswers — stockage serveur-only des réponses de duel.
 *
 * Anti-cheat (C2/C3) : les réponses ne sont JAMAIS écrites dans
 * `/matches/{matchId}` (lisible par les participants). Elles vivent dans
 * `/match_answers/{matchId}/rounds/{i}/answer`, un sous-arbre RTDB sans règle
 * d'accès → refusé par défaut côté client, lu uniquement par les Cloud
 * Functions via l'Admin SDK (qui bypass les security rules).
 *
 * La réponse d'une manche est « révélée » (copiée dans
 * `/matches/{matchId}/rounds/{round}/answer`) UNIQUEMENT quand la manche se
 * termine (roundEnd / finished / forfait / résolution stale), pour permettre
 * l'affichage du mot dans les overlays de fin de manche et l'écran résultat.
 */

import { getDatabase } from "firebase-admin/database";

/** Chemin du nœud serveur-only des réponses d'un match. */
export function matchAnswersPath(matchId: string): string {
  return `match_answers/${matchId}`;
}

/**
 * Écrit les 3 réponses dans le nœud serveur-only.
 * `answers` = { 0: "KORA", 1: "SAVANE", 2: "CALEBASSE" }.
 */
export function buildAnswersNode(
  answers: Record<number, string>
): Record<string, unknown> {
  return {
    rounds: {
      0: { answer: answers[0] },
      1: { answer: answers[1] },
      2: { answer: answers[2] },
    },
  };
}

/** Lit la réponse d'une manche depuis le nœud serveur-only (null si absente). */
export async function readAnswer(
  matchId: string,
  round: number
): Promise<string | null> {
  const snap = await getDatabase()
    .ref(`match_answers/${matchId}/rounds/${round}/answer`)
    .get();
  return snap.exists() ? (snap.val() as string) : null;
}

/**
 * Normalise un mot pour comparaison anti-cheat : trim + majuscules.
 * Le client envoie le mot formé ; le serveur le compare à la réponse stockée.
 */
export function normalizeWord(word: unknown): string {
  if (typeof word !== "string") return "";
  return word.trim().toUpperCase();
}
