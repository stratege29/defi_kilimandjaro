import 'dart:convert';
import 'dart:io';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cohérence entre le dossier `assets/images/mountains/`, `mountains.json` et
/// le set constant [AppAssets.mountainHeroIds] (qui évite tout `Image.asset`
/// sur un visuel absent — cf. faux crash Crashlytics « Unable to load asset »).
void main() {
  final heroDir = Directory('assets/images/mountains');
  final heroIdsOnDisk = heroDir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.startsWith('hero_') && n.endsWith('.png'))
      .map((n) => n.substring('hero_'.length, n.length - '.png'.length))
      .toSet();

  final mountainsJson = jsonDecode(
    File('assets/data/mountains.json').readAsStringSync(),
  ) as List<dynamic>;
  final mountainIds = mountainsJson
      .map((m) => (m as Map<String, dynamic>)['id'] as String)
      .toSet();

  test('le dossier contient au moins un visuel hero', () {
    expect(heroIdsOnDisk, isNotEmpty);
  });

  test('chaque hero_<id>.png présent correspond à un id de mountains.json', () {
    final orphans = heroIdsOnDisk.difference(mountainIds);
    expect(
      orphans,
      isEmpty,
      reason: 'visuels hero sans montagne dans mountains.json : $orphans',
    );
  });

  test('AppAssets.mountainHeroIds reflète exactement le dossier assets', () {
    expect(
      AppAssets.mountainHeroIds,
      equals(heroIdsOnDisk),
      reason: 'mettre à jour AppAssets.mountainHeroIds après ajout/suppression '
          "d'un hero_<id>.png — manquants: "
          '${heroIdsOnDisk.difference(AppAssets.mountainHeroIds)}, '
          'en trop: ${AppAssets.mountainHeroIds.difference(heroIdsOnDisk)}',
    );
  });

  test('mountainHero(id) pointe vers un fichier existant pour chaque id du set',
      () {
    for (final id in AppAssets.mountainHeroIds) {
      expect(
        File(AppAssets.mountainHero(id)).existsSync(),
        isTrue,
        reason: '${AppAssets.mountainHero(id)} introuvable',
      );
    }
  });
}
