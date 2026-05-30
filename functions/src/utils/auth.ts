import { HttpsError } from "firebase-functions/v2/https";

/**
 * Forme minimale du contexte d'auth attendu par les guards.
 *
 * Le token Firebase Auth peut transporter des custom claims qui hiérarchisent
 * les rôles backoffice :
 *   - admin     → tout (publish, rollback, gestion claims)
 *   - editor    → CRUD packs + devinettes, pas de publish
 *   - moderator → submissions UGC, lecture meta packs uniquement
 *
 * Les claims sont posés via la CF `setUserRole` (à venir) ou manuellement
 * par un admin via Admin SDK. Pas de claim → rôle "user" classique.
 *
 * Cf. `docs/backoffice_schema.md` §6 pour la matrice complète des permissions.
 */
// Type structurel permissif compatible avec `AuthData` de firebase-functions
// (dont `token` est un `DecodedIdToken` à signature d'index libre). On garde
// `token` en `Record<string, unknown>` pour rester compatible avec les
// anciens callers qui passaient `{ uid: string }` sans token.
type AuthLike = {
  uid: string;
  token?: Record<string, unknown>;
} | undefined;

/**
 * Vérifie que la requête callable est authentifiée.
 * Lève une erreur UNAUTHENTICATED si l'uid est absent.
 *
 * @param auth - contexte auth du callable request
 * @returns uid du joueur
 */
export function requireAuth(auth: AuthLike): string {
  if (!auth || !auth.uid) {
    throw new HttpsError(
      "unauthenticated",
      "Authentification requise pour accéder à cette fonction."
    );
  }
  return auth.uid;
}

/**
 * Vérifie que l'utilisateur a le claim `role: 'admin'`.
 *
 * Utilisé par les CFs sensibles (publishPack, rollbackPack, setUserRole).
 * Lève PERMISSION_DENIED si le claim manque ou est insuffisant.
 *
 * @param auth - contexte auth du callable request
 * @returns uid de l'admin
 */
export function requireAdmin(auth: AuthLike): string {
  const uid = requireAuth(auth);
  if (auth?.token?.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Privilèges admin requis pour cette opération."
    );
  }
  return uid;
}

/**
 * Vérifie que l'utilisateur a le claim `role: 'admin'` ou `'editor'`.
 *
 * Utilisé pour les CFs d'édition de contenu (upsertDevinette, bulkImport,
 * validatePackDraft). Un admin peut tout faire, un editor peut éditer sans
 * publier.
 *
 * @param auth - contexte auth du callable request
 * @returns uid de l'éditeur
 */
export function requireEditor(auth: AuthLike): string {
  const uid = requireAuth(auth);
  const role = auth?.token?.role;
  if (role !== "admin" && role !== "editor") {
    throw new HttpsError(
      "permission-denied",
      "Privilèges editor ou admin requis pour cette opération."
    );
  }
  return uid;
}
