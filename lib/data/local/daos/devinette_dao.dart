import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:drift/drift.dart';

part 'devinette_dao.g.dart';

@DriftAccessor(tables: <Type>[DevinettesCache])
class DevinetteDao extends DatabaseAccessor<DevinetteDatabase>
    with _$DevinetteDaoMixin {
  DevinetteDao(super.db);

  /// Charge toutes les devinettes en cache pour un monde donné.
  Future<List<Devinette>> loadByWorld(String world) async {
    final rows = await (select(devinettesCache)
          ..where((t) => t.world.equals(world)))
        .get();
    return rows.map((r) => r.toEntity()).toList(growable: false);
  }

  /// Remplace atomiquement le contenu d'un pack : delete-all-by-source-and-world
  /// puis insert. Garantit qu'une nouvelle version supplante l'ancienne sans
  /// états intermédiaires visibles.
  ///
  /// La [source] passée fait autorité sur la valeur de la colonne `source`
  /// pour toutes les entrées insérées — même si l'entité d'origine porte une
  /// `DevinetteSource` différente. Ça évite que le starter pack pollue
  /// accidentellement le cache distant.
  Future<void> replacePackContents({
    required String world,
    required DevinetteSource source,
    required List<Devinette> devinettes,
    required int packVersion,
  }) async {
    await transaction(() async {
      await (delete(devinettesCache)
            ..where((t) =>
                t.world.equals(world) & t.source.equals(source.name)))
          .go();
      for (final d in devinettes) {
        final companion = d
            .copyWith(source: source)
            .toCacheCompanion(packVersion: packVersion);
        await into(devinettesCache).insertOnConflictUpdate(companion);
      }
    });
  }

  /// Vide entièrement le cache (utile pour les tests + un éventuel "reset
  /// content" dans les paramètres).
  Future<void> clearAll() async {
    await delete(devinettesCache).go();
  }

  /// Supprime un pack spécifique (e.g. kill-switch via Remote Config).
  Future<void> deletePack({
    required String world,
    required DevinetteSource source,
  }) async {
    await (delete(devinettesCache)
          ..where(
              (t) => t.world.equals(world) & t.source.equals(source.name)))
        .go();
  }

  /// Compte les entrées en cache pour un monde — utile pour décider d'un
  /// fallback bundled-only à la volée.
  Future<int> countByWorld(String world) async {
    final query = selectOnly(devinettesCache)
      ..addColumns([devinettesCache.id.count()])
      ..where(devinettesCache.world.equals(world));
    final row = await query.getSingle();
    return row.read<int>(devinettesCache.id.count()) ?? 0;
  }
}
