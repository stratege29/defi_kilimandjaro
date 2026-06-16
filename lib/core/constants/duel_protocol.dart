/// Version du protocole du Défi 1v1 embarquée par ce build.
///
/// Envoyée au serveur (`protocol_version`) dans `requestMatch`/`joinDuel`. Le
/// serveur refuse les clients dont la version est < `MIN_DUEL_PROTOCOL`
/// (cf. `functions/src/matchmaking/protocol.ts`) — c'est la barrière qui
/// empêche un build antérieur (incompatible avec les changements anti-cheat
/// C2/C3) d'entrer dans un duel injouable.
///
/// À INCRÉMENTER (ici ET côté serveur) à chaque changement INCOMPATIBLE du
/// contrat duel.
const int kDuelProtocolVersion = 2;

/// Marqueur renvoyé par le serveur (message d'HttpsError) quand le client est
/// trop ancien pour le contrat duel courant.
const String kDuelOutdatedCode = 'DUEL_CLIENT_OUTDATED';
