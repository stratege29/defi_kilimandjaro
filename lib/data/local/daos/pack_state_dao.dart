import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:drift/drift.dart';

part 'pack_state_dao.g.dart';

@DriftAccessor(tables: <Type>[PackState])
class PackStateDao extends DatabaseAccessor<DevinetteDatabase>
    with _$PackStateDaoMixin {
  PackStateDao(super.db);

  /// Récupère l'état local d'un pack, ou null si jamais téléchargé.
  Future<PackStateRow?> get(String packId) {
    return (select(packState)..where((t) => t.packId.equals(packId)))
        .getSingleOrNull();
  }

  /// Liste tous les packs connus localement (pour debug + écran "Vérifier
  /// les nouveaux contenus").
  Future<List<PackStateRow>> getAll() => select(packState).get();

  /// Upsert d'un état de pack après un download réussi.
  Future<void> upsert({
    required String packId,
    required String pack,
    required int packVersion,
    required String hashSha256,
    required int sizeBytes,
    required int count,
  }) async {
    await into(packState).insertOnConflictUpdate(
      PackStateCompanion.insert(
        packId: packId,
        pack: pack,
        packVersion: packVersion,
        hashSha256: hashSha256,
        sizeBytes: Value(sizeBytes),
        count: Value(count),
        downloadedAt: DateTime.now(),
      ),
    );
  }

  /// Met à jour le timestamp de dernière vérification du manifest, sans
  /// changer la version installée. Sert à throttler les fetches Firestore.
  Future<void> markManifestSync(String packId) async {
    await (update(packState)..where((t) => t.packId.equals(packId))).write(
      PackStateCompanion(lastSyncedManifestAt: Value(DateTime.now())),
    );
  }

  Future<void> remove(String packId) async {
    await (delete(packState)..where((t) => t.packId.equals(packId))).go();
  }
}
