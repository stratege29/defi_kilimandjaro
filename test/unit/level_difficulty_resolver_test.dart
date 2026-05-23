import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:flutter_test/flutter_test.dart';

Mountain _make({
  required String id,
  required int altitude,
  int totalLevels = 4,
  String countryCode = 'ci',
}) {
  return Mountain(
    id: id,
    name: 'Mt $id',
    countryCode: countryCode,
    countryName: "Côte d'Ivoire",
    flagEmoji: '🇨🇮',
    altitude: altitude,
    totalLevels: totalLevels,
  );
}

void main() {
  group('LevelDifficultyResolver — palier de difficulté par altitude', () {
    test('palier 1 pour moins de 500 m (Red Rocks Gambie ~53 m)', () {
      final config = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'gm', altitude: 53),
        levelIndex: 1,
      );
      expect(config.difficultyTier, 1);
      expect(config.wordLengthBucket, 1);
      expect(config.caurisMultiplier, 1.0);
    });

    test('palier 3 pour 1500–2999 m (Mt Nimba 1752 m)', () {
      final config = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'ci', altitude: 1752),
        levelIndex: 1,
      );
      expect(config.difficultyTier, 3);
      expect(config.caurisMultiplier, 1.6);
    });

    test('palier 5 pour ≥ 4500 m (Kilimandjaro 5895 m)', () {
      final config = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'kili', altitude: 5895),
        levelIndex: 1,
      );
      expect(config.difficultyTier, 5);
      expect(config.caurisMultiplier, 2.5);
    });
  });

  group('LevelDifficultyResolver — timer adaptatif', () {
    test("timer plus long au palier 5 qu'au palier 1 (toutes choses égales)",
        () {
      final easy = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'easy', altitude: 100),
        levelIndex: 1,
      );
      // Pour comparer "toutes choses égales" on prend une montagne sous
      // 4000 m pour éviter le modifier `thinAir`.
      final hard = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'hard', altitude: 2800),
        levelIndex: 1,
      );
      expect(hard.timerSeconds, greaterThan(easy.timerSeconds));
    });

    test('thinAir réduit le timer au-dessus de 4000 m', () {
      final atFourThousand = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'a', altitude: 3999),
        levelIndex: 1,
      );
      final aboveFourThousand = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'b', altitude: 4000),
        levelIndex: 1,
      );
      // Même bucket de longueur, tier supérieur d'un cran, mais le
      // multiplicateur 0.8 doit faire baisser le timer absolu.
      expect(aboveFourThousand.modifiers, contains(LevelModifier.thinAir));
      expect(
        aboveFourThousand.timerSeconds,
        lessThan(atFourThousand.timerSeconds),
        reason: 'thinAir doit réduire le timer net malgré le tier supérieur',
      );
    });
  });

  group('LevelDifficultyResolver — modifier reverse', () {
    test('jamais attribué en tier 1–2 (zone tutoriel, même au boss)', () {
      // Aucun niveau (boss inclus) en tier 1-2 ne doit recevoir reverse.
      final easy = _make(id: 'plain', altitude: 200);
      var anyReverse = false;
      for (var i = 1; i <= easy.totalLevels; i++) {
        final config = LevelDifficultyResolver.resolve(
          mountain: easy,
          levelIndex: i,
        );
        if (config.modifiers.contains(LevelModifier.reverse)) {
          anyReverse = true;
        }
      }
      expect(anyReverse, isFalse);
    });

    test('peut être attribué à partir du tier 3', () {
      // Cherche au moins un niveau avec reverse parmi plusieurs montagnes
      // de tier 3 — l'attribution est déterministe via hash, donc on en
      // teste plusieurs pour ne pas dépendre d'un cas particulier.
      final candidates = <Mountain>[
        _make(id: 'a', altitude: 1800),
        _make(id: 'b', altitude: 2000),
        _make(id: 'c', altitude: 2500),
        _make(id: 'd', altitude: 2800),
      ];
      var foundReverse = false;
      for (final m in candidates) {
        for (var lvl = 1; lvl < m.totalLevels; lvl++) {
          final config = LevelDifficultyResolver.resolve(
            mountain: m,
            levelIndex: lvl,
          );
          if (config.modifiers.contains(LevelModifier.reverse)) {
            foundReverse = true;
            break;
          }
        }
        if (foundReverse) break;
      }
      expect(
        foundReverse,
        isTrue,
        reason: 'au moins une montagne tier 3+ doit avoir un niveau reverse',
      );
    });

    test('attribution déterministe : 2 résolutions du même niveau identiques',
        () {
      final m = _make(id: 'stable', altitude: 3500);
      final a = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 2);
      final b = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 2);
      expect(a, b);
    });
  });

  group('LevelDifficultyResolver — flag boss', () {
    test("dernier niveau d'une montagne ⇒ isBoss = true", () {
      final m = _make(id: 'boss', altitude: 500);
      final last = LevelDifficultyResolver.resolve(
        mountain: m,
        levelIndex: 4,
      );
      final earlier = LevelDifficultyResolver.resolve(
        mountain: m,
        levelIndex: 3,
      );
      expect(last.isBoss, isTrue);
      expect(earlier.isBoss, isFalse);
    });

    test('boss tier 1-2 reste "soft" : pas de reverse garanti (zone tutoriel)',
        () {
      // Red Rocks niveau 2 (tier 1, boss) ne doit PAS recevoir reverse —
      // le joueur sort à peine du splash et n'a pas appris le gameplay.
      final m = _make(id: 'boss-easy', altitude: 200);
      final boss = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 4);
      expect(boss.isBoss, isTrue);
      expect(boss.modifiers, isNot(contains(LevelModifier.reverse)));
      expect(
        boss.modifiers,
        isEmpty,
        reason: 'tier 1 + boss = aucun modifier (zone tutoriel)',
      );
    });

    test('boss tier ≥ 3 reçoit toujours au moins un modifier signature', () {
      // Couvert par les règles S3 : shuffle est attribué à tout boss
      // tier ≥ 3. Le filet reverse (garantie originale) reste en place
      // pour les cas pathologiques mais en pratique shuffle suffit.
      final m = _make(id: 'zw_nyangani', altitude: 2592);
      final boss = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 4);
      expect(boss.isBoss, isTrue);
      expect(
        boss.modifiers.any((m) => <LevelModifier>{
              LevelModifier.shuffle,
              LevelModifier.reverse,
              LevelModifier.earthquake,
              LevelModifier.wind,
              LevelModifier.fog,
            }.contains(m)),
        isTrue,
        reason: 'un boss tier ≥ 3 doit avoir au moins un modifier visible',
      );
    });
  });

  group('LevelDifficultyResolver — modifiers exclusifs mouvement/masque', () {
    test('tectonique tier ≥ 3 ⇒ earthquake (pas wind, pas fog)', () {
      // Mt Cameroun simulé : code CM, 4040 m, tier 4.
      final m = _make(id: 'cm', altitude: 4040, countryCode: 'CM');
      final c = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 1);
      expect(c.modifiers, contains(LevelModifier.earthquake));
      expect(c.modifiers, isNot(contains(LevelModifier.wind)));
      expect(c.modifiers, isNot(contains(LevelModifier.fog)));
    });

    test('non-tectonique altitude ≥ 3000 m ⇒ wind (pas earthquake)', () {
      // Toubkal Maroc simulé : code MA, 4167 m.
      final m = _make(id: 'ma', altitude: 4167, countryCode: 'MA');
      final c = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 1);
      expect(c.modifiers, contains(LevelModifier.wind));
      expect(c.modifiers, isNot(contains(LevelModifier.earthquake)));
      expect(c.modifiers, isNot(contains(LevelModifier.fog)));
    });

    test('non-tectonique altitude 2000–3000 m ⇒ fog', () {
      // Mt Sunzu Zambie simulé : code ZM, 2339 m.
      final m = _make(id: 'zm', altitude: 2339, countryCode: 'ZM');
      final c = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 1);
      expect(c.modifiers, contains(LevelModifier.fog));
      expect(c.modifiers, isNot(contains(LevelModifier.wind)));
      expect(c.modifiers, isNot(contains(LevelModifier.earthquake)));
    });

    test('shuffle attribué aux boss tier ≥ 3', () {
      final m = _make(id: 'ci_nimba', altitude: 1752, totalLevels: 6);
      final boss = LevelDifficultyResolver.resolve(
        mountain: m,
        levelIndex: 6,
      );
      expect(boss.isBoss, isTrue);
      expect(boss.modifiers, contains(LevelModifier.shuffle));
    });

    test('shuffle PAS attribué aux niveaux normaux ni aux boss tier 1-2', () {
      // Boss tier 2.
      final m = _make(id: 'sn', altitude: 648);
      final boss = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 4);
      expect(boss.modifiers, isNot(contains(LevelModifier.shuffle)));
      // Niveau normal tier 3.
      final mid = _make(id: 'ci_nimba', altitude: 1752, totalLevels: 6);
      final n3 = LevelDifficultyResolver.resolve(mountain: mid, levelIndex: 3);
      expect(n3.modifiers, isNot(contains(LevelModifier.shuffle)));
    });
  });

  group('LevelDifficultyResolver — distractorCount par tier', () {
    test('tier 1-2 → 0 distracteur (zone tutoriel)', () {
      final tier1 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't1', altitude: 200),
        levelIndex: 1,
      );
      final tier2 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't2', altitude: 800),
        levelIndex: 1,
      );
      expect(tier1.distractorCount, 0);
      expect(tier2.distractorCount, 0);
    });

    test('progression 1 → 2 → 3 distracteurs aux tiers 3/4/5', () {
      final tier3 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't3', altitude: 2000),
        levelIndex: 1,
      );
      final tier4 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't4', altitude: 3500),
        levelIndex: 1,
      );
      final tier5 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't5', altitude: 5000),
        levelIndex: 1,
      );
      expect(tier3.distractorCount, 1);
      expect(tier4.distractorCount, 2);
      expect(tier5.distractorCount, 3);
    });
  });

  group('LevelDifficultyResolver — clamping levelIndex', () {
    test('levelIndex < 1 clampé à 1 (UX > strictness)', () {
      final m = _make(id: 'clamp', altitude: 500);
      final at0 = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 0);
      final at1 = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 1);
      expect(at0, at1);
    });

    test('levelIndex > totalLevels clampé au boss', () {
      final m = _make(id: 'clamp2', altitude: 500);
      final beyond = LevelDifficultyResolver.resolve(
        mountain: m,
        levelIndex: 99,
      );
      expect(beyond.isBoss, isTrue);
    });
  });
}
