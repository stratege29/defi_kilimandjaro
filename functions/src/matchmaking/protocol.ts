/**
 * Barrière de version min du Défi (gate serveur).
 *
 * Pourquoi côté serveur : un gate purement client ne protège PAS des apps déjà
 * installées (elles n'embarquent pas le code du gate). Seul le serveur peut
 * bloquer un vieux client. Or, depuis le durcissement anti-cheat :
 *   - C2 : `submitRoundWin` exige le mot formé (`word`) ;
 *   - C3 : la réponse n'est plus envoyée au client pendant la manche.
 * Un build antérieur ne peut donc PAS terminer un duel — il entrerait dans une
 * partie injouable. On le rejette dès `requestMatch`/`joinDuel` avec un code
 * reconnaissable, plutôt que de le laisser perdre une partie « fantôme ».
 *
 * `protocol_version` est un entier baked-in côté client, incrémenté à chaque
 * changement INCOMPATIBLE du contrat duel. Bumper MIN_DUEL_PROTOCOL ici (et la
 * constante client `kDuelProtocolVersion`) au prochain changement de contrat.
 */

import { HttpsError } from "firebase-functions/v2/https";

/** Version de protocole minimale acceptée pour entrer en duel. */
export const MIN_DUEL_PROTOCOL = 2;

/**
 * Marqueur d'erreur reconnu par le client neuf pour afficher « Mets à jour
 * l'app pour jouer en ligne ». Les anciens clients reçoivent juste une erreur
 * `failed-precondition` générique (ils n'ont pas ce code) — mais ils sont au
 * moins bloqués AVANT d'entrer dans un duel injouable.
 */
export const DUEL_OUTDATED_CODE = "DUEL_CLIENT_OUTDATED";

/**
 * Vérifie que le client est assez récent. Lève `failed-precondition` sinon.
 * Un client sans `protocol_version` est considéré comme antérieur (= 1).
 */
export function requireDuelProtocol(data: unknown): void {
  const raw =
    data && typeof data === "object" && "protocol_version" in data
      ? (data as { protocol_version?: unknown }).protocol_version
      : undefined;
  const version = typeof raw === "number" ? raw : 1;
  if (version < MIN_DUEL_PROTOCOL) {
    throw new HttpsError("failed-precondition", DUEL_OUTDATED_CODE);
  }
}
