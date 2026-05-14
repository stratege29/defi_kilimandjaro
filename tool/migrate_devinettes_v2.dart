// ignore_for_file: avoid_print
//
// One-shot migration script: format v1 (mono-langue) → v2 (multilingue).
//
// Usage:
//   dart run tool/migrate_devinettes_v2.dart
//
// Effets :
//   - Lit `assets/data/devinettes/<world>.json` v1 (riddle/explanation/proverb
//     en String plat).
//   - Réécrit chaque entrée en v2 (Map<String,String> sous clé 'fr'), ajoute
//     `format_version: 2` et `answer_normalized` si absent.
//   - Écrit le résultat dans `assets/data/devinettes/starter/<world>.json` (le
//     starter pack bundlé). Les fichiers v1 d'origine sont conservés pour
//     traçabilité (à supprimer manuellement après vérification).
//   - Met à jour `assets/data/devinettes/starter/_index.json`.
//
// Idempotent : relancer le script sur des fichiers déjà v2 ne casse rien.

import 'dart:convert';
import 'dart:io';

const String _devinettesDir = 'assets/data/devinettes';
const String _starterDir = 'assets/data/devinettes/starter';

const Map<String, String> _diacriticsMap = <String, String>{
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'î': 'i', 'ï': 'i', 'í': 'i',
  'ò': 'o', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ý': 'y',
  'ñ': 'n',
};

String _normalize(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_diacriticsMap[ch] ?? ch);
  }
  return buf.toString();
}

Map<String, dynamic> _migrateEntry(Map<String, dynamic> entry) {
  final formatVersion = entry['format_version'] as int? ?? 1;
  if (formatVersion >= 2) return entry; // already migrated

  Map<String, String> wrap(dynamic raw) {
    if (raw == null) return const <String, String>{};
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return <String, String>{'fr': raw.toString()};
  }

  final answer = (entry['answer'] as String).toUpperCase();
  final answerNormalized =
      entry['answer_normalized'] as String? ?? _normalize(answer);

  return <String, dynamic>{
    'id': entry['id'],
    'world': entry['world'],
    'country': entry['country'],
    'answer': answer,
    'answer_normalized': answerNormalized,
    'letters_pool': entry['letters_pool'],
    'riddle': wrap(entry['riddle']),
    'explanation': wrap(entry['explanation']),
    'proverb': wrap(entry['proverb']),
    if (entry['image_svg'] != null) 'image_svg': entry['image_svg'],
    if (entry['image_url'] != null) 'image_url': entry['image_url'],
    'difficulty': entry['difficulty'],
    'estimated_time_s': entry['estimated_time_s'],
    'tags': entry['tags'],
    'format_version': 2,
  };
}

Future<void> _migrateWorld(String worldId, File source) async {
  final raw = await source.readAsString();
  final list = (jsonDecode(raw) as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(_migrateEntry)
      .toList();

  final outFile = File('$_starterDir/$worldId.json');
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(list),
  );
  print('  • $worldId : ${list.length} entrées → ${outFile.path}');
}

Future<void> main() async {
  final dir = Directory(_devinettesDir);
  if (!dir.existsSync()) {
    stderr.writeln('Répertoire introuvable : $_devinettesDir');
    exitCode = 1;
    return;
  }

  print('Migration devinettes v1 → v2 :');

  final indexFile = File('$_devinettesDir/_index.json');
  Map<String, dynamic> indexJson;
  if (indexFile.existsSync()) {
    indexJson = jsonDecode(await indexFile.readAsString())
        as Map<String, dynamic>;
  } else {
    indexJson = <String, dynamic>{'worlds': <String, dynamic>{}, 'total': 0};
  }

  final worlds = (indexJson['worlds'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};

  var total = 0;
  final newWorlds = <String, dynamic>{};

  for (final entry in worlds.entries) {
    final worldId = entry.key;
    final source = File('$_devinettesDir/$worldId.json');
    if (!source.existsSync()) {
      print('  ✗ $worldId : fichier absent ($_devinettesDir/$worldId.json)');
      newWorlds[worldId] = <String, dynamic>{
        'count': 0,
        'file': '$worldId.json',
      };
      continue;
    }
    await _migrateWorld(worldId, source);
    final migratedFile = File('$_starterDir/$worldId.json');
    final migrated = (jsonDecode(await migratedFile.readAsString()) as List)
        .cast<Map<String, dynamic>>();
    total += migrated.length;
    newWorlds[worldId] = <String, dynamic>{
      'count': migrated.length,
      'file': '$worldId.json',
    };
  }

  final outIndex = File('$_starterDir/_index.json');
  await outIndex.parent.create(recursive: true);
  await outIndex.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format_version': 2,
      'worlds': newWorlds,
      'total': total,
    }),
  );

  print('Total migré : $total devinettes.');
  print('Index : ${outIndex.path}');
}
