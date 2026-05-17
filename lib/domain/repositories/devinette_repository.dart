import 'package:defi_kilimandjaro/domain/entities/devinette.dart';

/// Source des devinettes culturelles.
///
/// Implémentation actuelle (format_version 3) : JSON bundlé dans
/// `assets/data/devinettes/starter/<packId>.json` + cache Drift + packs
/// distants téléchargés.
abstract interface class DevinetteRepository {
  /// Charge toutes les devinettes d'un pack (cache mémoire en local).
  Future<List<Devinette>> loadPack(String packId);

  /// Renvoie une devinette aléatoire du pack.
  Future<Devinette> randomFromPack(String packId);

  /// Renvoie une devinette aléatoire du pack, en EXCLUANT les ids passés.
  /// Sert l'anti-répétition : on évite de retomber sur une des N dernières
  /// devinettes jouées par le joueur. Si après exclusion il ne reste rien
  /// (pool trop petit), tombe en fallback sur [randomFromPack].
  Future<Devinette> randomFromPackExcluding(
    String packId,
    Iterable<String> excludeIds,
  );

  /// Renvoie une devinette aléatoire du monde, en EXCLUANT les ids passés.
  /// Sert l'anti-répétition : on évite de retomber sur une des N dernières
  /// devinettes jouées par le joueur. Si après exclusion il ne reste rien
  /// (pool trop petit), tombe en fallback sur [randomFromWorld].
  Future<Devinette> randomFromWorldExcluding(
    String worldId,
    Iterable<String> excludeIds,
  );

  /// Renvoie la devinette à l'index donné (utile pour progression séquentielle).
  Future<Devinette> atIndex(String packId, int index);
}
