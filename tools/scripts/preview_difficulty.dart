// ignore_for_file: avoid_print
// Script de visualisation : pour chaque montagne du jeu, calcule la
// LevelDifficultyConfig de chaque niveau et imprime un tableau. Sert
// au QA pour repérer rapidement où apparaissent `reverse` / `thinAir`,
// où sont les boss, et comment le timer/multiplier évoluent.
//
// Lancer : `dart run tools/scripts/preview_difficulty.dart`

import 'dart:convert';
import 'dart:io';

import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';

void main() {
  final raw = File('assets/data/mountains.json').readAsStringSync();
  final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
  final mountains = list.map(Mountain.fromJson).toList();

  print('rank | id                   | alt   | lvl | tier | bkt | timer | x    | boss | modifiers');
  print('-----+----------------------+-------+-----+------+-----+-------+------+------+-----------');

  for (var rank = 0; rank < mountains.length; rank++) {
    final m = mountains[rank];
    for (var lvl = 1; lvl <= m.totalLevels; lvl++) {
      final c = LevelDifficultyResolver.resolve(mountain: m, levelIndex: lvl);
      final mods = c.modifiers.map(_short).join(',');
      final id = m.id.padRight(20);
      final alt = m.altitude.toString().padLeft(5);
      final lvlStr = lvl.toString().padLeft(3);
      final tier = c.difficultyTier.toString().padLeft(4);
      final bkt = c.wordLengthBucket.toString().padLeft(3);
      final timer = c.timerSeconds.toString().padLeft(5);
      final mult = c.caurisMultiplier.toStringAsFixed(1).padLeft(4);
      final boss = c.isBoss ? 'BOSS' : '    ';
      final rankStr = rank.toString().padLeft(4);
      print('$rankStr | $id | $alt |$lvlStr | $tier | $bkt | $timer | $mult | $boss | $mods');
    }
  }

  // Synthèse : où apparaît le 1er reverse ? le 1er thinAir ?
  print('\nSynthèse :');
  for (final m in mountains) {
    for (var lvl = 1; lvl <= m.totalLevels; lvl++) {
      final c = LevelDifficultyResolver.resolve(mountain: m, levelIndex: lvl);
      if (c.modifiers.contains(LevelModifier.reverse)) {
        print('  Premier REVERSE non-boss : ${m.id} niveau $lvl '
            '(tier ${c.difficultyTier}, alt ${m.altitude} m)');
        if (!c.isBoss) {
          // On veut le premier reverse non-boss pour montrer l'algo
          // aléatoire ; on sort.
          break;
        }
      }
    }
  }
}

String _short(LevelModifier m) {
  switch (m) {
    case LevelModifier.reverse:
      return 'REV';
    case LevelModifier.thinAir:
      return 'AIR';
    // ignore: no_default_cases
    default:
      return m.name;
  }
}
