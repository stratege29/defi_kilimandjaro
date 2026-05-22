/// Modificateurs gameplay attribuables à un niveau pour enrichir la
/// progression de difficulté au-delà du simple palier d'altitude.
///
/// Chaque modifier représente une mécanique thématique liée à
/// l'environnement (vent en altitude, brouillard, lave volcanique, …)
/// ou cognitive (mot à l'envers). Les modifiers sont attribués
/// algorithmiquement par `LevelDifficultyResolver` selon
/// `(mountain, levelIndex)`.
///
/// L'implémentation visuelle/runtime des effets est progressive :
/// - **S1 (cette PR)** : `reverse` (validation inversée) et `thinAir`
///   (timer accéléré) sont les seuls effectifs.
/// - **S3** : implémentation des effets visuels des autres modifiers
///   (lettres qui bougent, brouillard, etc.) via plugins
///   `LevelModifierEffect` dans `presentation/game/modifiers/`.
///
/// Les autres valeurs de l'enum sont déjà déclarées pour que la chaîne
/// de typage (resolver → config → controller) soit complète dès S1.
enum LevelModifier {
  /// Le joueur doit former le mot à l'envers (FOUTOU → UOTUOF).
  /// Indiqué par un badge explicite dans l'UI.
  reverse,

  /// Le timer tourne 1,3× plus vite (effet hypoxie haute altitude).
  thinAir,

  /// 1 lettre dérive vers une case voisine toutes les ~8 s.
  wind,

  /// 2 lettres s'échangent de position périodiquement.
  earthquake,

  /// La grille se re-mélange complètement toutes les X secondes.
  shuffle,

  /// 1–2 lettres masquées par un nuage qui se déplace.
  fog,

  /// 1 lettre « fausse » apparaît dans la grille (n'appartient pas au mot).
  mirage,

  /// 1 lettre devient rouge et disparaît si pas utilisée dans les 6 s.
  lava,

  /// Lettres givrées : tap maintenu 0,5 s requis pour activer.
  ice,

  /// Les lettres deviennent floues 1 s toutes les 4 s.
  rain,

  /// Toutes les 10 s, l'esprit emprunte 1 lettre 3 s puis la rend.
  spirit,

  /// 1–2 lettres cachées dans une calebasse à ouvrir (coût : 1 s pause).
  calabash,

  /// Les lettres tapées off-beat ne comptent pas (sync BPM balafon).
  drumbeat,

  /// Éboulis qui recouvre progressivement la grille à chaque erreur.
  rockslide,

  /// 1 lettre change de caractère toutes les 7 s (cycle entre 3 lettres).
  chameleon,

  /// Le timer ne se recharge pas avec les indices.
  drySeason,

  /// Un chemin « tracé » suggère un mauvais mot — piège visuel.
  pantherTrail,

  /// Lettre tapée se duplique fantomatiquement 1 s sur 2 cases voisines.
  caveEcho,
}
