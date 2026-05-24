import 'package:equatable/equatable.dart';

/// Catégorie d'avatar — utilisée pour organiser le picker en sections.
enum AvatarCategory {
  griot,
  masque,
  vieQuotidienne,
  aliment,
  instrument,
  faune,
  wildcard,
}

/// Avatar choisi par le joueur pour s'identifier dans le leaderboard,
/// l'écran profil et l'overlay de duel.
///
/// Le catalogue est **fini et hardcodé** (`AvatarCatalog`) — pas d'upload
/// utilisateur, donc pas de modération à scaler ni de risque COPPA.
///
/// Un avatar peut être :
/// - libre (`unlockMinElo == null && !isPremium`) — dispo dès J0
/// - déverrouillable par palier ELO (`unlockMinElo: 2000`)
/// - premium (`isPremium: true`) — achat en cauris (Phase 4 monétisation)
class Avatar extends Equatable {
  const Avatar({
    required this.id,
    required this.assetPath,
    required this.nameKey,
    required this.category,
    this.unlockMinElo,
    this.isPremium = false,
  });

  /// Identifiant stable persisté dans Firestore (`profiles/{uid}.avatar_id`).
  /// Format `snake_case`. Ne JAMAIS le changer après release — c'est une
  /// clé de persistance.
  final String id;

  /// Chemin asset complet (ex: `assets/images/avatars/griot_classique.png`).
  final String assetPath;

  /// Clé `easy_localization` du nom affiché (ex: `'avatar.griot_classique'`).
  final String nameKey;

  /// Section d'affichage dans le picker.
  final AvatarCategory category;

  /// ELO minimum pour déverrouiller. Null = libre dès J0.
  final int? unlockMinElo;

  /// True = avatar premium acheté en cauris (Phase 4).
  final bool isPremium;

  /// Vrai si l'avatar est disponible pour un joueur d'ELO [playerElo].
  /// Les avatars premium retournent toujours false ici — l'achat est
  /// géré séparément via le wallet cauris.
  bool isUnlockedFor(int playerElo) {
    if (isPremium) return false;
    if (unlockMinElo == null) return true;
    return playerElo >= unlockMinElo!;
  }

  @override
  List<Object?> get props => [
        id,
        assetPath,
        nameKey,
        category,
        unlockMinElo,
        isPremium,
      ];
}
