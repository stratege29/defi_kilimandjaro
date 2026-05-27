/// Constantes de l'économie de défaite — mode **solo uniquement**.
///
/// Ces valeurs gouvernent la mécanique anti-rage / pro-monétisation :
/// le joueur perd des cauris à chaque défaite (incite à l'achat IAP),
/// et au seuil de tilt obtient un skip gratuit (protège la rétention).
///
/// **Ne s'applique PAS au mode duel 1v1** : pas de cauris, pas de pub,
/// pas de skip pendant un duel temps réel (cf. CLAUDE.md — "JAMAIS de
/// pub pendant un duel").
library;

/// Cauris perdus lors d'une défaite solo (timer écoulé sans avoir
/// trouvé le mot). Choix produit : 10 cauris — assez visible pour
/// matérialiser l'enjeu, assez modeste pour ne pas être hostile au
/// nouveau joueur (solde initial 120 ⇒ 12 défaites avant ruine).
const int kLossCaurisPenalty = 10;

/// Seuil de défaites consécutives sur **la même devinette** au-delà
/// duquel l'écran d'échec propose un skip gratuit (anti-tilt).
/// Choix produit : 3 — alignement avec le rythme classique "rule of
/// three" et le compteur existant de l'interstitielle (1 pub / 3
/// défaites globales).
const int kFreeSkipLossThreshold = 3;
