import { HttpsError } from "firebase-functions/v2/https";

/**
 * Vérifie que la requête callable est authentifiée.
 * Lève une erreur UNAUTHENTICATED si l'uid est absent.
 *
 * @param auth - contexte auth du callable request
 * @returns uid du joueur
 */
export function requireAuth(
  auth: { uid: string } | undefined
): string {
  if (!auth || !auth.uid) {
    throw new HttpsError(
      "unauthenticated",
      "Authentification requise pour accéder à cette fonction."
    );
  }
  return auth.uid;
}
