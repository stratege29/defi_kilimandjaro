import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';

/// Façade au-dessus du DAO Drift — expose une API simple en termes
/// d'entités domain. Permet au repository composite de rester ignorant
/// de Drift (et facilite les tests : le composite se mock avec un fake
/// `LocalDevinetteCacheDatasource`).
class LocalDevinetteCacheDatasource {
  LocalDevinetteCacheDatasource(this._db);

  final DevinetteDatabase _db;

  /// Charge toutes les devinettes en cache pour un monde (packs distants +
  /// communautaires). Le starter pack bundlé est lu ailleurs.
  Future<List<Devinette>> loadByWorld(String world) {
    return _db.devinetteDao.loadByWorld(world);
  }

  /// Remplace le contenu d'un pack atomiquement (delete + insert dans une
  /// transaction). À appeler après un download + hash verify réussi.
  Future<void> replacePackContents({
    required String world,
    required DevinetteSource source,
    required List<Devinette> devinettes,
    required int packVersion,
  }) {
    return _db.devinetteDao.replacePackContents(
      world: world,
      source: source,
      devinettes: devinettes,
      packVersion: packVersion,
    );
  }

  /// Compte les entrées en cache pour un monde.
  Future<int> countByWorld(String world) =>
      _db.devinetteDao.countByWorld(world);

  /// Supprime un pack spécifique (kill-switch via Remote Config par exemple).
  Future<void> deletePack({
    required String world,
    required DevinetteSource source,
  }) {
    return _db.devinetteDao.deletePack(world: world, source: source);
  }

  /// État local d'un pack (version installée, hash, comptage).
  Future<PackStateRow?> packState(String packId) =>
      _db.packStateDao.get(packId);

  Future<void> upsertPackState({
    required String packId,
    required String world,
    required int packVersion,
    required String hashSha256,
    required int sizeBytes,
    required int count,
  }) {
    return _db.packStateDao.upsert(
      packId: packId,
      world: world,
      packVersion: packVersion,
      hashSha256: hashSha256,
      sizeBytes: sizeBytes,
      count: count,
    );
  }

  Future<void> markManifestSync(String packId) =>
      _db.packStateDao.markManifestSync(packId);
}
