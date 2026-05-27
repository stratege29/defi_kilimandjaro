// ignore_for_file: avoid_print
//
// Seed des packs distants OTA. Fusionne deux sources :
//
//   1. `assets/data/devinettes/starter/<packId>.json`
//      (bundled dans l'app, frozen à 90 questions, offline-first)
//
//   2. `content/ota_packs/<packId>.json`
//      (non bundled, ajouts continus distribués via Firebase OTA)
//
// Produit dans `build/seed_packs/<packId>/<packId>-v<N>.json.gz` + un
// manifest `manifests.json`. Les fichiers sont prêts à uploader sur
// Cloud Storage / Firestore.
//
// Merge rule : pour un même `id`, l'entrée de `ota_packs` supplante celle
// du starter (permet de corriger une faute du starter via OTA sans release).
// Si `content/ota_packs/<packId>.json` est absent ou vide, l'output est
// strictement identique à celui produit à partir du starter seul — utile
// pour valider la reproductibilité des hashes v1.
//
// Usage :
//   dart run tool/seed_content_packs.dart
//
// Étapes manuelles ensuite :
//   1. Uploader `build/seed_packs/**/*.json.gz` vers
//      `gs://<your-bucket>/packs/v2/<packId>/<packId>-v<N>.json.gz`.
//   2. Pour chaque pack, mettre à jour le doc Firestore `content_packs/<packId>`
//      à partir de `manifests.json`.
//   3. Mettre à jour `content_index/global` si nouveau pack.
//
// Note : ce script ne TOUCHE PAS Firebase. Il prépare les fichiers pour
// upload — c'est volontaire pour éviter qu'un dev local pousse en prod par
// erreur.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const String _starterDir = 'assets/data/devinettes/starter';
const String _otaDir = 'content/ota_packs';
const String _outDir = 'build/seed_packs';
const int _formatVersion = 3;
const int _defaultVersion = 1;

void main() async {
  final indexFile = File('$_starterDir/_index.json');
  if (!indexFile.existsSync()) {
    stderr.writeln('Index introuvable : $_starterDir/_index.json');
    exitCode = 1;
    return;
  }

  final indexJson =
      jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
  final packsIndex =
      (indexJson['packs'] as Map?)?.cast<String, dynamic>() ?? {};
  if (packsIndex.isEmpty) {
    stderr.writeln('Aucun pack déclaré dans $_starterDir/_index.json.');
    exitCode = 1;
    return;
  }

  final manifests = <String, Map<String, dynamic>>{};
  final activePackIds = <String>[];

  await Directory(_outDir).create(recursive: true);

  for (final entry in packsIndex.entries) {
    final packId = entry.key;
    final indexEntry = (entry.value as Map?)?.cast<String, dynamic>() ?? {};
    // Version du pack — lue depuis _index.json (champ `current_version`), 1 par défaut
    // pour rétrocompatibilité. Bumper ce champ quand on push une nouvelle version OTA.
    final packVersion =
        (indexEntry['current_version'] as num?)?.toInt() ?? _defaultVersion;

    final source = File('$_starterDir/$packId.json');
    if (!source.existsSync()) {
      print('  • $packId : fichier source absent — skip.');
      continue;
    }

    final raw = await source.readAsString();
    final starterList =
        (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final list = _merge(starterList, await _loadOtaAdditions(packId));
    if (list.isEmpty) {
      print('  • $packId : 0 entrée — skip (rien à seeder).');
      continue;
    }

    // Champs déterministes uniquement — pas de timestamp, pour que deux
    // exécutions sur le même contenu produisent le même hash (idempotence).
    final packPayload = <String, dynamic>{
      'format_version': _formatVersion,
      'pack_id': packId,
      'pack_version': packVersion,
      'langs': _detectLangs(list),
      'default_lang': 'fr',
      'min_app_version': '0.1.0',
      'count': list.length,
      'devinettes': list,
    };

    final encoded = utf8.encode(jsonEncode(packPayload));
    final hash = sha256.convert(encoded).toString();
    packPayload['hash_sha256'] = hash;

    // Hash externe (manifest) = hash du JSON final avec le champ hash_sha256
    // déjà présent, car c'est ce que le client gunzippe puis hashe pour
    // vérification (cf. RemoteDevinettePackDatasource.downloadAndParse).
    final encodedFinal = utf8.encode(jsonEncode(packPayload));
    final hashFinal = sha256.convert(encodedFinal).toString();

    final gz = const GZipEncoder().encode(encodedFinal);

    final outFile =
        File('$_outDir/$packId/$packId-v$packVersion.json.gz');
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(gz);

    final storagePath = 'packs/v2/$packId/$packId-v$packVersion.json.gz';
    manifests[packId] = <String, dynamic>{
      'pack': packId,
      'current_version': packVersion,
      'format_version': _formatVersion,
      'hash_sha256': hashFinal,
      'size_bytes': gz.length,
      'count': list.length,
      'storage_path': storagePath,
      'download_url':
          'https://firebasestorage.googleapis.com/v0/b/<BUCKET>/o/${Uri.encodeComponent(storagePath)}?alt=media',
      'min_app_version': '0.1.0',
      'langs': packPayload['langs'],
      'default_lang': 'fr',
      'enabled': true,
    };

    activePackIds.add(packId);
    print(
      '  ✓ $packId : v$packVersion (${list.length} entrées, '
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
      'min_format_version': _formatVersion,
    }),
  );

  print('');
  print('Fichiers produits dans $_outDir/ :');
  print('  - <packId>/<packId>-v<N>.json.gz → upload vers Cloud Storage');
  print('  - manifests.json                 → un doc par pack dans `content_packs/`');
  print('  - content_index_global.json     → doc `content_index/global`');
}

/// Charge les ajouts OTA pour un pack. Retourne une liste vide si le
/// fichier n'existe pas ou est mal formé. Toute erreur est tolérée
/// silencieusement — l'absence d'ajouts est l'état initial légitime.
Future<List<Map<String, dynamic>>> _loadOtaAdditions(String packId) async {
  final file = File('$_otaDir/$packId.json');
  if (!file.existsSync()) return const <Map<String, dynamic>>[];
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const <Map<String, dynamic>>[];
    return decoded.cast<Map<String, dynamic>>();
  } on FormatException {
    stderr.writeln(
      'OTA additions illisibles ($_otaDir/$packId.json) — ignoré.',
    );
    return const <Map<String, dynamic>>[];
  }
}

/// Fusionne starter + ota_packs en préservant l'ordre original du starter
/// pour les ids communs (ota override en place), et en appendant à la fin
/// les ids exclusivement OTA.
///
/// Important pour la reproductibilité des hashes v1 :
/// si `additions` est vide, retourne `starter` à l'identique (même ordre,
/// mêmes objets).
List<Map<String, dynamic>> _merge(
  List<Map<String, dynamic>> starter,
  List<Map<String, dynamic>> additions,
) {
  if (additions.isEmpty) return starter;
  final byId = <String, Map<String, dynamic>>{};
  final order = <String>[];
  for (final entry in starter) {
    final id = entry['id'] as String?;
    if (id == null) continue;
    byId[id] = entry;
    order.add(id);
  }
  for (final entry in additions) {
    final id = entry['id'] as String?;
    if (id == null) continue;
    if (!byId.containsKey(id)) {
      order.add(id);
    }
    byId[id] = entry;
  }
  return [for (final id in order) byId[id]!];
}

/// Détecte la liste des langues couvertes par le pack (clés des sous-objets
/// `riddle` / `explanation`). Le champ `proverb` n'existe plus en v3.
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
  }
  if (langs.isEmpty) return const ['fr'];
  return langs.toList()..sort();
}
