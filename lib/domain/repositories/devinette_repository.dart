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

  /// Renvoie la devinette à l'index donné (utile pour progression séquentielle).
  Future<Devinette> atIndex(String worldId, int index);
}
