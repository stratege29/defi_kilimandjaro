import 'dart:convert';
import 'dart:io';

import 'package:defi_kilimandjaro/data/local/daos/devinette_dao.dart';
import 'package:defi_kilimandjaro/data/local/daos/pack_state_dao.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'devinette_database.g.dart';

/// Cache local des devinettes téléchargées (packs distants + communautaires).
///
/// Le starter pack bundlé n'est PAS persistant ici — il est lu directement
/// depuis `rootBundle` à chaque session par `BundledDevinetteDatasource`.
/// Cette table accueille uniquement le contenu téléchargé : packs officiels
/// et pack communautaire.
@DataClassName('CachedDevinetteRow')
class DevinettesCache extends Table {
  TextColumn get id => text()();
  TextColumn get world => text()();
  TextColumn get country => text()();
  TextColumn get answer => text()();
  TextColumn get answerNormalized => text().nullable()();
  TextColumn get lettersPoolJson => text()();
  TextColumn get riddleJson => text()();
  TextColumn get explanationJson => text()();
  TextColumn get proverbJson => text()();
  IntColumn get difficulty => integer()();
  IntColumn get estimatedTimeS => integer()();
  TextColumn get tagsJson => text()();
  IntColumn get formatVersion => integer().withDefault(const Constant(2))();
  TextColumn get source => text()();
  TextColumn get imageSvg => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  IntColumn get packVersion => integer().withDefault(const Constant(0))();
  DateTimeColumn get insertedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// État local par pack : version installée, hash, comptage. Sert à comparer
/// avec le manifest Firestore pour décider d'un re-download.
@DataClassName('PackStateRow')
class PackState extends Table {
  /// Identifiant du pack — `<world>` pour les packs officiels et
  /// `<world>_community` pour le pack communautaire.
  TextColumn get packId => text()();
  TextColumn get world => text()();
  IntColumn get packVersion => integer()();
  TextColumn get hashSha256 => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get count => integer().withDefault(const Constant(0))();
  DateTimeColumn get downloadedAt => dateTime()();
  DateTimeColumn get lastSyncedManifestAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {packId};
}

/// Brouillons UGC offline-first : tant qu'un draft n'est pas envoyé au backend,
/// il vit ici. Une fois la soumission acceptée par le serveur, l'entrée est
/// supprimée et le résultat consommé via Firestore (collection `submissions/`).
@DataClassName('SubmissionDraftRow')
class SubmissionDrafts extends Table {
  TextColumn get id => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: <Type>[DevinettesCache, PackState, SubmissionDrafts],
  daos: <Type>[DevinetteDao, PackStateDao],
)
class DevinetteDatabase extends _$DevinetteDatabase {
  DevinetteDatabase() : super(_openConnection());

  /// Ctor de test : permet d'injecter une `DatabaseConnection` in-memory.
  DevinetteDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'devinettes_cache.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Helpers de conversion entité ↔ ligne Drift.
extension DevinetteCacheMapping on Devinette {
  DevinettesCacheCompanion toCacheCompanion({required int packVersion}) {
    return DevinettesCacheCompanion.insert(
      id: id,
      world: world,
      country: country,
      answer: answer,
      answerNormalized: Value(answerNormalized),
      lettersPoolJson: jsonEncode(lettersPool),
      riddleJson: jsonEncode(riddleByLang),
      explanationJson: jsonEncode(explanationByLang),
      proverbJson: jsonEncode(proverbByLang),
      difficulty: difficulty,
      estimatedTimeS: estimatedTimeS,
      tagsJson: jsonEncode(tags),
      source: source.name,
      imageSvg: Value(imageSvg),
      imageUrl: Value(imageUrl),
      packVersion: Value(packVersion),
      insertedAt: DateTime.now(),
      formatVersion: Value(formatVersion),
    );
  }
}

extension CachedDevinetteRowMapping on CachedDevinetteRow {
  Devinette toEntity() {
    return Devinette(
      id: id,
      world: world,
      country: country,
      answer: answer,
      answerNormalized: answerNormalized,
      lettersPool: List<String>.from(jsonDecode(lettersPoolJson) as List),
      riddleByLang: (jsonDecode(riddleJson) as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      explanationByLang: (jsonDecode(explanationJson) as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      proverbByLang: (jsonDecode(proverbJson) as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      difficulty: difficulty,
      estimatedTimeS: estimatedTimeS,
      tags: List<String>.from(jsonDecode(tagsJson) as List),
      formatVersion: formatVersion,
      source: DevinetteSource.values.firstWhere(
        (s) => s.name == source,
        orElse: () => DevinetteSource.remotePack,
      ),
      imageSvg: imageSvg,
      imageUrl: imageUrl,
    );
  }
}
