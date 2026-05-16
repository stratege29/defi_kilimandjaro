import 'package:defi_kilimandjaro/domain/entities/devinette.dart';

/// Source des devinettes culturelles.
///
/// Implémentation actuelle : JSON bundlé dans `assets/data/devinettes/`.
/// Évolution v2 : override Remote Config + cache Isar.
abstract interface class DevinetteRepository {
  /// Charge toutes les devinettes d'un monde (cache mémoire en local).
  Future<List<Devinette>> loadWorld(String worldId);

  /// Renvoie une devinette aléatoire du monde.
  Future<Devinette> randomFromWorld(String worldId);

  /// Renvoie une devinette aléatoire du monde, en EXCLUANT les ids passés.
  /// Sert l'anti-répétition : on évite de retomber sur une des N dernières
  /// devinettes jouées par le joueur. Si après exclusion il ne reste rien
  /// (pool trop petit), tombe en fallback sur [randomFromWorld].
  Future<Devinette> randomFromWorldExcluding(
    String worldId,
    Iterable<String> excludeIds,
  );

  /// Renvoie la devinette à l'index donné (utile pour progression séquentielle).
  Future<Devinette> atIndex(String worldId, int index);
}
