/// Calcul des étoiles obtenues à la fin d'une partie (mode solo).
///
/// Trois critères cumulatifs :
/// - **Étoile 1** : victoire (mot formé = réponse attendue).
/// - **Étoile 2** : victoire sans utiliser d'indice payant.
/// - **Étoile 3** : victoire dans la première moitié du temps imparti
///   (≥ 50 % du timer restant à la victoire).
///
/// Si la partie est perdue (timer écoulé), le score est 0 étoile —
/// aucun crédit même pour avoir tenté.
///
/// La fonction est pure : aucune dépendance Flutter/Riverpod. Testable
/// trivialement par table de vérité dans `level_star_rating_test.dart`.
abstract final class LevelStarRating {
  /// Calcule le nombre d'étoiles (0..3) selon les paramètres de la partie.
  ///
  /// - [won] : vrai si le mot formé == `expectedAnswer` (canonique ou
  ///   inversé selon le modifier `reverse`).
  /// - [hintUsed] : vrai si au moins un indice a été révélé pendant la
  ///   partie (coût cauris ≠ 0 ⇒ pénalité 2e étoile).
  /// - [timerSeconds] : durée totale calibrée par le resolver pour ce
  ///   niveau (cf. `LevelDifficultyConfig.timerSeconds`).
  /// - [timeLeftAtVictory] : secondes restantes au moment exact de la
  ///   validation. Doit être `0` quand la partie est perdue.
  static int computeStars({
    required bool won,
    required bool hintUsed,
    required int timerSeconds,
    required int timeLeftAtVictory,
  }) {
    if (!won) return 0;
    var stars = 1;
    if (!hintUsed) stars += 1;
    if (timerSeconds > 0 && timeLeftAtVictory * 2 >= timerSeconds) {
      stars += 1;
    }
    return stars;
  }

  /// Clé de stockage d'un niveau dans la map `starsByLevel` du
  /// `PlayerProgress`. Format stable utilisé en JSON — ne pas changer
  /// sans migration des sauvegardes existantes.
  static String levelKey({required String mountainId, required int levelIndex}) {
    return '$mountainId#$levelIndex';
  }
}
