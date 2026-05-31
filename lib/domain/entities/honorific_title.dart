/// Titres honorifiques progressifs (cf. maquette p.10).
///
/// Quatre paliers de maîtrise basés sur le nombre total de niveaux gagnés.
/// Le titre courant est le plus haut palier débloqué.
enum HonorificTitle {
  oreilleDuVillage(
    name: 'Oreille du Village',
    badgeAsset: 'assets/images/badges/oreille_du_village.png',
    description: 'Tu commences à reconnaître les chants du griot.',
    threshold: 5,
  ),
  gardienDeLaParole(
    name: 'Gardien de la Parole',
    badgeAsset: 'assets/images/badges/gardien_de_la_parole.png',
    description: 'Les proverbes commencent à habiter ta mémoire.',
    threshold: 25,
  ),
  griotDuFeu(
    name: 'Griot du Feu',
    badgeAsset: 'assets/images/badges/griot_du_feu.png',
    description: 'Tu portes les histoires de tout un peuple.',
    threshold: 75,
  ),
  ancetreVivant(
    name: 'Ancêtre Vivant',
    badgeAsset: 'assets/images/badges/ancetre_vivant.png',
    description: 'Ta sagesse rejoint celle des aïeux.',
    threshold: 200,
  );

  const HonorificTitle({
    required this.name,
    required this.badgeAsset,
    required this.description,
    required this.threshold,
  });

  final String name;

  /// Illustration du masque sculpté (cf. badges K1-K4).
  final String badgeAsset;

  final String description;

  /// Nombre de niveaux totaux requis pour débloquer ce titre.
  final int threshold;

  /// Renvoie le palier le plus haut atteint, `null` si aucun.
  static HonorificTitle? currentFor(int totalLevels) {
    HonorificTitle? current;
    for (final t in HonorificTitle.values) {
      if (totalLevels >= t.threshold) current = t;
    }
    return current;
  }
}
