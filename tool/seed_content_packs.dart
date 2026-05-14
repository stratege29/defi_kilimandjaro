// ignore_for_file: avoid_print
//
// Seed initial des packs distants : prend les fichiers v2 sous
// `assets/data/devinettes/starter/<world>.json`, les compresse en gzip et
// produit dans `build/seed_packs/<world>/<world>-v1.json.gz` + un manifest
// `manifests.json` à uploader manuellement (ou via un script `firebase`).
//
// Usage :
//   dart run tool/seed_content_packs.dart
//
// Étapes manuelles ensuite :
//   1. Uploader `build/seed_packs/**/*.json.gz` vers
//      `gs://<your-bucket>/packs/v2/<world>/<world>-v1.json.gz`.
//   2. Pour chaque pack, créer le doc Firestore `content_packs/<world>` à
//      partir de `manifests.json` (e.g. via le script Node ou la console).
//   3. Créer / mettre à jour `content_index/global` avec la liste des
//      `packIds` (cf. `index.json`).
//
// Note : ce script ne TOUCHE PAS Firebase. Il prépare les fichiers pour
// upload — c'est volontaire pour éviter qu'un dev local pousse en prod par
// erreur.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const String _starterDir = 'assets/data/devinettes/starter';
const String _outDir = 'build/seed_packs';
const int _initialVersion = 1;

void main() async {
  final indexFile = File('$_starterDir/_index.json');
  if (!indexFile.existsSync()) {
    stderr.writeln(
      'Index introuvable : $_starterDir/_index.json '
      '(lancer dabord `dart run tool/migrate_devinettes_v2.dart`).',
    );
    exitCode = 1;
    return;
  }

  final indexJson = jsonDecode(await indexFile.readAsString())
      as Map<String, dynamic>;
  final worlds =
      (indexJson['worlds'] as Map?)?.cast<String, dynamic>() ?? {};

  final manifests = <String, Map<String, dynamic>>{};
  final activePackIds = <String>[];

  await Directory(_outDir).create(recursive: true);

  for (final entry in worlds.entries) {
    final worldId = entry.key;
    final source = File('$_starterDir/$worldId.json');
    if (!source.existsSync()) continue;

    final raw = await source.readAsString();
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) {
      print('  • $worldId : 0 entrée — skip (rien à seeder).');
      continue;
    }

    final pack = <String, dynamic>{
      'format_version': 2,
      'pack_id': worldId,
      'pack_version': _initialVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'langs': _detectLangs(list),
      'default_lang': 'fr',
      'min_app_version': '0.1.0',
      'count': list.length,
      'devinettes': list,
    };

    final encoded = utf8.encode(jsonEncode(pack));
    final hash = sha256.convert(encoded).toString();
    pack['hash_sha256'] = hash;

    // Re-encode avec le hash inclus → recompute final hash sur l'objet final
    // est inutile : le hash documenté correspond au JSON décompressé tel que
    // téléchargé par le client. Le client le calcule sur le JSON post-decode
    // (cf. RemoteDevinettePackDatasource.downloadAndParse).
    final encodedFinal = utf8.encode(jsonEncode(pack));
    final hashFinal = sha256.convert(encodedFinal).toString();

    final gz = const GZipEncoder().encode(encodedFinal);

    final outFile = File('$_outDir/$worldId/$worldId-v$_initialVersion.json.gz');
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(gz);

    final storagePath = 'packs/v2/$worldId/$worldId-v$_initialVersion.json.gz';
    manifests[worldId] = <String, dynamic>{
      'world': worldId,
      'current_version': _initialVersion,
      'format_version': 2,
      'hash_sha256': hashFinal,
      'size_bytes': gz.length,
      'count': list.length,
      'storage_path': storagePath,
      'download_url':
          'https://firebasestorage.googleapis.com/v0/b/<BUCKET>/o/${Uri.encodeComponent(storagePath)}?alt=media',
      'min_app_version': '0.1.0',
      'langs': pack['langs'],
      'default_lang': 'fr',
      'enabled': true,
    };

    activePackIds.add(worldId);
    print(
      '  ✓ $worldId : v$_initialVersion (${list.length} entrées, '
      '${gz.length} bytes gzip, hash $hashFinal)',
    );
  }

  // Écriture des manifests prêts à uploader.
  final manifestsFile = File('$_outDir/manifests.json');
  await manifestsFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifests),
  );
  final indexOut = File('$_outDir/content_index_global.json');
  await indexOut.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'packs': activePackIds,
      'min_format_version': 2,
    }),
  );

  print('');
  print('Fichiers produits dans $_outDir/ :');
  print('  - <world>/<world>-v1.json.gz  → upload vers Cloud Storage');
  print('  - manifests.json               → un doc par pack dans `content_packs/`');
  print('  - content_index_global.json   → doc `content_index/global`');
}

List<String> _detectLangs(List<Map<String, dynamic>> list) {
  final langs = <String>{};
  for (final entry in list) {
    void add(dynamic raw) {
      if (raw is Map) {
        for (final k in raw.keys) {
          langs.add(k.toString());
        }
      }
    }

    add(entry['riddle']);
    add(entry['explanation']);
    add(entry['proverb']);
  }
  if (langs.isEmpty) return const ['fr'];
  return langs.toList()..sort();
}
