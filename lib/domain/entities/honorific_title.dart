/// Titres honorifiques progressifs (cf. maquette p.10).
///
/// Quatre paliers de maîtrise basés sur le nombre total de niveaux gagnés.
/// Le titre courant est le plus haut palier débloqué.
enum HonorificTitle {
  oreilleDuVillage(
    name: 'Oreille du Village',
    icon: '👂',
    description: 'Tu commences à reconnaître les chants du griot.',
    threshold: 5,
  ),
  gardienDeLaParole(
    name: 'Gardien de la Parole',
    icon: '📖',
    description: 'Les proverbes commencent à habiter ta mémoire.',
    threshold: 25,
  ),
  griotDuFeu(
    name: 'Griot du Feu',
    icon: '🔥',
    description: 'Tu portes les histoires de tout un peuple.',
    threshold: 75,
  ),
  ancetreVivant(
    name: 'Ancêtre Vivant',
    icon: '🌿',
    description: 'Ta sagesse rejoint celle des aïeux.',
    threshold: 200,
  );

  const HonorificTitle({
    required this.name,
    required this.icon,
    required this.description,
    required this.threshold,
  });

  final String name;
  final String icon;
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
