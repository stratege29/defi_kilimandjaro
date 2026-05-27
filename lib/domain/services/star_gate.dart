/// Star-gate — système de portes par étoiles cumulées entre les tiers.
///
/// Donne un usage fonctionnel aux 2★/3★ : pour franchir certains paliers
/// de tier, le joueur doit cumuler un nombre minimal d'étoiles sur les
/// niveaux précédents. Combiné à l'unlock 100 % par montagne (qui reste
/// en place), force le replay des niveaux à 1★ pour les joueurs proches
/// du seuil.
///
/// **Pas de porte entre Tier 1 et Tier 2** — la zone tutoriel doit rester
/// fluide (cf. décision PO sur l'extension Tier 1 à 3 montagnes).
///
/// **Seuils calibrés** sur le potentiel théorique du jeu (avec le
/// découpage actuel : T1=10 niveaux, T2=56, T3=85, T4=48, T5=33) :
/// - T2 → T3 : 30 ★ (≈15 % du potentiel cumulé T1+T2 = 198 ★)
/// - T3 → T4 : 120 ★ (≈27 % du potentiel cumulé T1→T3 = 453 ★)
/// - T4 → T5 : 250 ★ (≈42 % du potentiel cumulé T1→T4 = 597 ★)
///
/// Ces ratios montent volontairement avec le tier : on accepte que le
/// joueur casual atteigne le Tier 3 sans replay (1.5 ★ moyen suffit),
/// mais on force un effort pour les zones haute altitude.
///
/// Source de vérité unique pour les seuils — référencer cette classe et
/// non des constantes dupliquées.
abstract final class StarGate {
  /// Seuil d'étoiles cumulées requis pour franchir vers `targetTier`.
  /// `targetTier` doit être dans `2..5`. Retourne `0` pour `targetTier == 2`
  /// (pas de porte) et lève [ArgumentError] hors de la plage.
  static int thresholdForTier(int targetTier) {
    switch (targetTier) {
      case 2:
        return 0;
      case 3:
        return 30;
      case 4:
        return 120;
      case 5:
        return 250;
      default:
        throw ArgumentError.value(
          targetTier,
          'targetTier',
          'must be in 2..5',
        );
    }
  }

  /// Calcule le tier maximal **déverrouillé** par le joueur en fonction
  /// de ses étoiles cumulées. Toujours ≥ 2 (le passage Tier 1 → Tier 2
  /// est sans porte). Retourne :
  /// - `2` si totalStars < 30 (Tier 1 et 2 accessibles)
  /// - `3` si 30 ≤ totalStars < 120
  /// - `4` si 120 ≤ totalStars < 250
  /// - `5` si totalStars ≥ 250
  ///
  /// Fonction pure et déterministe — testable trivialement.
  static int computeUnlockedTier(int totalStars) {
    if (totalStars >= thresholdForTier(5)) return 5;
    if (totalStars >= thresholdForTier(4)) return 4;
    if (totalStars >= thresholdForTier(3)) return 3;
    return 2;
  }

  /// Nombre d'étoiles **manquantes** pour atteindre le tier `targetTier`.
  /// Retourne `0` si déjà débloqué (ou si `targetTier` ≤ 2). Utilisé par
  /// la couche présentation pour afficher « il te manque N ★ ».
  static int starsNeededForTier({
    required int targetTier,
    required int currentTotal,
  }) {
    if (targetTier <= 2) return 0;
    final threshold = thresholdForTier(targetTier);
    final missing = threshold - currentTotal;
    return missing > 0 ? missing : 0;
  }
}
