/// Structure d'un niveau Sommets — ce que le joueur doit accomplir pour le
/// gagner, indépendamment des modificateurs (`LevelModifier`) qui ne font
/// que perturber la grille.
///
/// Attribué de façon déterministe par `LevelDifficultyResolver.resolve`
/// (cf. `LevelDifficultyConfig.kind`) et consommé par `GameController` /
/// `GameView`. Les niveaux 1-2 de chaque sommet restent toujours
/// [classic] (tutoriel), et deux niveaux consécutifs ne sont jamais tous
/// deux non-classiques.
enum LevelKind {
  /// Une énigme, un mot, une grille — la boucle historique.
  classic,

  /// Trois mots courts enchaînés dans la même partie avec un timer commun :
  /// chaque mot validé recharge la grille et offre quelques secondes.
  rafale,

  /// Deux énigmes, deux mots à trouver dans une seule grille dont le pool
  /// est l'union des lettres des deux réponses.
  duo,

  /// Boss des tiers ≥ 3 : l'énigme s'efface après quelques secondes et se
  /// relit à la demande, contre du temps.
  blindBoss;

  /// Nombre de devinettes à tirer pour ce type de niveau (principale
  /// comprise).
  int get devinetteCount {
    switch (this) {
      case LevelKind.rafale:
        return 3;
      case LevelKind.duo:
        return 2;
      case LevelKind.classic:
      case LevelKind.blindBoss:
        return 1;
    }
  }

  /// Vrai pour les structures qui cassent la boucle « un mot, un niveau »
  /// (rafale et duo). Le boss aveugle garde la structure classique.
  bool get isMultiWord => this == LevelKind.rafale || this == LevelKind.duo;
}
