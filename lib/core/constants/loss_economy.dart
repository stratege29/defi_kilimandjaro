/// Constantes de l'économie de défaite — mode **solo uniquement**.
///
/// Gouverne la mécanique anti-tilt : au seuil de défaites consécutives
/// sur une même devinette, l'écran d'échec propose un skip gratuit qui
/// débloque la frustration sans pénalité.
///
/// Décision produit (cf. game_view : « punir l'échec dégrade
/// l'expérience ») : **aucune pénalité en cauris** n'est appliquée à la
/// défaite. La rétention prime sur la ponction monétaire.
///
/// **Ne s'applique PAS au mode duel 1v1** : pas de cauris, pas de pub,
/// pas de skip pendant un duel temps réel (cf. CLAUDE.md — « JAMAIS de
/// pub pendant un duel »).
library;

/// Seuil de défaites consécutives sur **la même devinette** au-delà
/// duquel l'écran d'échec propose un skip gratuit (anti-tilt).
/// Choix produit : 3 — alignement avec le rythme classique "rule of
/// three".
const int kFreeSkipLossThreshold = 3;
