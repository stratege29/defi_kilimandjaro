import 'dart:convert';
import 'dart:io';

import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
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

/// Variante avec assez de niveaux pour atteindre la zone post-ramp-up
/// (levelIndex ≥ 5) où les règles environnementales tier-based s'appliquent
/// sans être écrasées par les overrides « tutoriel » et « ramp-up doux ».
Mountain _makeLong({
  required String id,
  required int altitude,
  String countryCode = 'ci',
  int totalLevels = 10,
}) {
  return _make(
    id: id,
    altitude: altitude,
    countryCode: countryCode,
    totalLevels: totalLevels,
  );
}

/// Les 52 sommets réels du jeu, pour les invariants qui doivent tenir sur
/// tout le contenu livré (et pas seulement sur des montagnes synthétiques).
List<Mountain> _loadRealMountains() {
  final raw =
      jsonDecode(File('assets/data/mountains.json').readAsStringSync())
          as List<dynamic>;
  return raw
      .map((m) => Mountain.fromJson(m as Map<String, dynamic>))
      .toList(growable: false);
}

/// Modificateurs que le résolveur a le droit d'émettre : ceux qui ont un
/// runtime (`reverse`, `thinAir`, `wind`, `earthquake`, `fog`, `shuffle`)
/// plus les trois de la vague suivante (`mirage`, `rain`, `spirit`).
const Set<LevelModifier> _allowedModifiers = <LevelModifier>{
  LevelModifier.reverse,
  LevelModifier.thinAir,
  LevelModifier.wind,
  LevelModifier.earthquake,
  LevelModifier.fog,
  LevelModifier.shuffle,
  LevelModifier.mirage,
  LevelModifier.rain,
  LevelModifier.spirit,
};

/// Palette « douce » des niveaux 3-4 (tiers 1-2).
const Set<LevelModifier> _gentle = <LevelModifier>{
  LevelModifier.wind,
  LevelModifier.shuffle,
  LevelModifier.rain,
};

/// Palette douce élargie des niveaux 3-4 à partir du tier 3.
const Set<LevelModifier> _gentleExtended = <LevelModifier>{
  ..._gentle,
  LevelModifier.mirage,
  LevelModifier.spirit,
};

/// Palette douce applicable à une montagne selon son tier.
Set<LevelModifier> _gentleFor(Mountain m) =>
    LevelDifficultyResolver.tierForAltitude(m.altitude) >= 3
    ? _gentleExtended
    : _gentle;

/// Modificateurs « actifs » d'une config : tout sauf `thinAir` (passif).
Set<LevelModifier> _active(LevelDifficultyConfig config) =>
    config.modifiers.difference(<LevelModifier>{LevelModifier.thinAir});

List<LevelDifficultyConfig> _ladder(Mountain m) => <LevelDifficultyConfig>[
  for (var i = 1; i <= m.totalLevels; i++)
    LevelDifficultyResolver.resolve(mountain: m, levelIndex: i),
];

void main() {
  group('LevelDifficultyResolver — palier de difficulté par altitude', () {
    test('palier 1 pour moins de 700 m (Red Rocks Gambie ~53 m)', () {
      final config = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'gm', altitude: 53),
        levelIndex: 1,
      );
      expect(config.difficultyTier, 1);
      expect(config.wordLengthBucket, 1);
      expect(config.caurisMultiplier, 1.0);
    });

    test('palier 1 inclut la zone 500–699 m (Sambadougou 648 m, '
        'Sokbaro 658 m) — onboarding étendu', () {
      // Avant l'extension du seuil tier 1, ces montagnes étaient tier 2
      // (5 lettres, multiplier 1.3). Elles servent désormais de zone
      // d'apprentissage prolongée pour atteindre 10 niveaux d'onboarding
      // au total (Red Rocks 2 + Sambadougou 4 + Sokbaro 4).
      for (final alt in <int>[500, 648, 658, 699]) {
        final config = LevelDifficultyResolver.resolve(
          mountain: _make(id: 'low-$alt', altitude: alt),
          levelIndex: 1,
        );
        expect(
          config.difficultyTier,
          1,
          reason: 'altitude $alt m doit être tier 1 (seuil exclusif 700 m)',
        );
      }
    });

    test('palier 2 commence exactement à 700 m (borne exclusive) — '
        'Tena Kourou 749 m amorce la rampe', () {
      final boundary = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'boundary', altitude: 700),
        levelIndex: 1,
      );
      expect(boundary.difficultyTier, 2);
      expect(boundary.caurisMultiplier, 1.3);

      final tenaKourou = LevelDifficultyResolver.resolve(
        mountain: _make(id: 'bf_tena_kourou', altitude: 749),
        levelIndex: 1,
      );
      expect(tenaKourou.difficultyTier, 2);
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
    test(
      "timer plus long au palier 5 qu'au palier 1 (toutes choses égales)",
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
      },
    );

    test('bases par tier au niveau 1 : 29 / 34 / 42 / 47 / 52 s', () {
      // 15 + 3·wordLen(bucket = tier) + 2·tier, sans rampe au niveau 1.
      const altitudes = <int, int>{1: 100, 2: 800, 3: 2000, 4: 3500, 5: 5000};
      const expected = <int, int>{1: 29, 2: 34, 3: 42, 4: 47, 5: 52};
      for (final entry in altitudes.entries) {
        final config = LevelDifficultyResolver.resolve(
          mountain: _make(id: 'base-${entry.key}', altitude: entry.value),
          levelIndex: 1,
        );
        expect(
          config.timerSeconds,
          expected[entry.key],
          reason: 'tier ${entry.key}',
        );
      }
    });

    test('thinAir réduit le timer au-dessus de 4000 m', () {
      // levelIndex ≥ 3 pour sortir de la zone « tutoriel » (niv 1-2 = aucun
      // modifier, thinAir compris). On compare deux montagnes du même tier
      // (3999 m et 4000 m sont toutes deux tier 4) au même niveau.
      final atFourThousand = LevelDifficultyResolver.resolve(
        mountain: _makeLong(id: 'a', altitude: 3999),
        levelIndex: 5,
      );
      final aboveFourThousand = LevelDifficultyResolver.resolve(
        mountain: _makeLong(id: 'b', altitude: 4000),
        levelIndex: 5,
      );
      expect(atFourThousand.modifiers, isNot(contains(LevelModifier.thinAir)));
      expect(aboveFourThousand.modifiers, contains(LevelModifier.thinAir));
      expect(
        aboveFourThousand.timerSeconds,
        (atFourThousand.timerSeconds * 0.8).round(),
        reason: 'thinAir = ×0,8 appliqué après la rampe',
      );
    });
  });

  group('LevelDifficultyResolver — rampe intra-sommet', () {
    test('distracteurs : base(tier) + (niveau − 1) ÷ 2, croissants', () {
      // Tier 1-2 : 0 aux niveaux 1-2, 1 aux niveaux 3-4, 2 au niveau 5+.
      final t2 = _makeLong(id: 't2', altitude: 800, totalLevels: 6);
      expect(_ladder(t2).map((c) => c.distractorCount).toList(), <int>[
        0,
        0,
        1,
        1,
        2,
        2,
      ]);
      // Tier 5 sur 8 niveaux : 3, 3, 4, 4, puis plafond à 4.
      final t5 = _makeLong(id: 't5', altitude: 5895, totalLevels: 8);
      expect(_ladder(t5).map((c) => c.distractorCount).toList(), <int>[
        3,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
      ]);
    });

    test('distracteurs monotones croissants et plafonnés à 4 sur toutes les '
        'montagnes réelles', () {
      for (final m in _loadRealMountains()) {
        final ladder = _ladder(m);
        for (var i = 1; i < ladder.length; i++) {
          expect(
            ladder[i].distractorCount,
            greaterThanOrEqualTo(ladder[i - 1].distractorCount),
            reason: '${m.id} niveau ${i + 1}',
          );
        }
        for (final c in ladder) {
          expect(c.distractorCount, lessThanOrEqualTo(4), reason: m.id);
        }
      }
    });

    test('timer : base(tier) − 2 s par niveau, strictement décroissant '
        "tant que le plancher n'est pas atteint", () {
      // Tier 3 (base 42 s) sur 6 niveaux, sans thinAir : 42, 40, …, 32.
      final t3 = _makeLong(id: 'ramp-t3', altitude: 2000, totalLevels: 6);
      expect(_ladder(t3).map((c) => c.timerSeconds).toList(), <int>[
        42,
        40,
        38,
        36,
        34,
        32,
      ]);
    });

    test('timer : plancher à 60 % de la base (arrondi)', () {
      // Tier 1, base 29 s → plancher round(17,4) = 17. Sur 12 niveaux la
      // rampe brute descendrait à 7 s : elle doit s'arrêter à 17.
      final long = _makeLong(id: 'floor', altitude: 100, totalLevels: 12);
      final timers = _ladder(long).map((c) => c.timerSeconds).toList();
      expect(timers.first, 29);
      expect(timers.last, 17);
      for (var i = 1; i < timers.length; i++) {
        expect(timers[i], lessThanOrEqualTo(timers[i - 1]));
        expect(timers[i], greaterThanOrEqualTo(17));
      }
    });

    test(
      'timer décroissant (au sens large) sur toutes les montagnes réelles',
      () {
        // Au sens large : le passage niveau 2 → 3 sur un sommet > 4000 m
        // ajoute thinAir (×0,8), ce qui ne fait que renforcer la décroissance.
        for (final m in _loadRealMountains()) {
          final ladder = _ladder(m);
          for (var i = 1; i < ladder.length; i++) {
            expect(
              ladder[i].timerSeconds,
              lessThanOrEqualTo(ladder[i - 1].timerSeconds),
              reason: '${m.id} niveau ${i + 1}',
            );
          }
        }
      },
    );

    test('multiplicateur cauris : mult(tier) × (1 + 0,1·(niveau − 1)), '
        'arrondi à 2 décimales', () {
      // Tier 2 (1,3) sur 6 niveaux ; le boss (niveau 6) ajoute +0,25.
      final t2 = _makeLong(id: 'mult-t2', altitude: 800, totalLevels: 6);
      expect(_ladder(t2).map((c) => c.caurisMultiplier).toList(), <double>[
        1.3,
        1.43,
        1.56,
        1.69,
        1.82,
        2.2,
      ]);
    });

    test('boss : bucket = tier + 1 (plafond 5) et multiplicateur majoré de '
        '+0,25', () {
      // Tier 3, 4 niveaux : boss bucket 4, mult 1,6 × 1,3 + 0,25 = 2,33.
      final t3 = _make(id: 'boss-t3', altitude: 2000);
      final boss = LevelDifficultyResolver.resolve(mountain: t3, levelIndex: 4);
      final before = LevelDifficultyResolver.resolve(
        mountain: t3,
        levelIndex: 3,
      );
      expect(boss.isBoss, isTrue);
      expect(boss.wordLengthBucket, 4);
      expect(before.wordLengthBucket, 3);
      expect(boss.caurisMultiplier, 2.33);
      expect(before.caurisMultiplier, 1.92);

      // Tier 1 exempté : Red Rocks niveau 2 (2ᵉ niveau du jeu) reste sur
      // des mots de 4 lettres, mais garde le bonus cauris boss.
      final t1 = _make(id: 'gm_red_rocks', altitude: 53, totalLevels: 2);
      final bossT1 = LevelDifficultyResolver.resolve(
        mountain: t1,
        levelIndex: 2,
      );
      expect(bossT1.isBoss, isTrue);
      expect(bossT1.wordLengthBucket, 1);
      expect(bossT1.caurisMultiplier, 1.35);

      // Tier 2 : +1 s'applique dès le tier 2.
      final t2 = _make(id: 'boss-t2', altitude: 800);
      expect(
        LevelDifficultyResolver.resolve(
          mountain: t2,
          levelIndex: 4,
        ).wordLengthBucket,
        3,
      );

      // Tier 5 : le bucket boss reste plafonné à 5.
      final t5 = _make(id: 'boss-t5', altitude: 5895);
      final bossT5 = LevelDifficultyResolver.resolve(
        mountain: t5,
        levelIndex: 4,
      );
      expect(bossT5.wordLengthBucket, 5);
      expect(bossT5.caurisMultiplier, 2.5 * 1.3 + 0.25);
    });

    test('la rampe ne change pas le tier (source de vérité = altitude)', () {
      for (final m in _loadRealMountains()) {
        final tier = LevelDifficultyResolver.tierForAltitude(m.altitude);
        for (final c in _ladder(m)) {
          expect(c.difficultyTier, tier, reason: m.id);
        }
      }
    });
  });

  group('LevelDifficultyResolver — modifier reverse', () {
    test('jamais attribué en tier 1–2 (zone tutoriel, même au boss)', () {
      // Aucun niveau (boss inclus) en tier 1-2 ne doit recevoir reverse,
      // y compris sur un sommet synthétique long (niveaux 5+).
      for (final easy in <Mountain>[
        _make(id: 'plain', altitude: 200),
        _makeLong(id: 'plain-long', altitude: 200),
        _makeLong(id: 'plain-t2', altitude: 900),
      ]) {
        for (final c in _ladder(easy)) {
          expect(
            c.modifiers,
            isNot(contains(LevelModifier.reverse)),
            reason: easy.id,
          );
        }
      }
    });

    test('peut être attribué à partir du tier 3 (hors zone ramp-up)', () {
      // Cherche au moins un niveau avec reverse parmi plusieurs montagnes
      // de tier 3 — l'attribution est déterministe via hash, donc on en
      // teste plusieurs pour ne pas dépendre d'un cas particulier.
      // On scrute uniquement levelIndex ≥ 5 : sur 1-2 (tutoriel) et 3-4
      // (ramp-up doux), reverse n'est pas candidat.
      final candidates = <Mountain>[
        _makeLong(id: 'a', altitude: 1800),
        _makeLong(id: 'b', altitude: 2000),
        _makeLong(id: 'c', altitude: 2500),
        _makeLong(id: 'd', altitude: 2800),
      ];
      var foundReverse = false;
      for (final m in candidates) {
        for (var lvl = 5; lvl < m.totalLevels; lvl++) {
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
        reason:
            'au moins une montagne tier 3+ doit avoir un niveau reverse '
            'hors zone ramp-up (levelIndex ≥ 5)',
      );
    });

    test(
      'attribution déterministe : 2 résolutions du même niveau identiques',
      () {
        final m = _makeLong(id: 'stable', altitude: 3500);
        final a = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 6);
        final b = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 6);
        expect(a, b);
      },
    );
  });

  group('LevelDifficultyResolver — flag boss', () {
    test("dernier niveau d'une montagne ⇒ isBoss = true", () {
      final m = _make(id: 'boss', altitude: 500);
      final last = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 4);
      final earlier = LevelDifficultyResolver.resolve(
        mountain: m,
        levelIndex: 3,
      );
      expect(last.isBoss, isTrue);
      expect(earlier.isBoss, isFalse);
    });

    test(
      'boss tier 1-2 reste "soft" : un seul modifier doux (zone ramp-up)',
      () {
        // Red Rocks-like niveau 4 (tier 1, boss) : exactement un modifier
        // tiré dans la palette douce {wind, shuffle, rain}. Pas de modifier
        // "dur" (reverse cognitif, fog occultant, earthquake brutal) car le
        // joueur découvre encore la mécanique, et pas de double boss.
        final m = _make(id: 'boss-easy', altitude: 200);
        final boss = LevelDifficultyResolver.resolve(
          mountain: m,
          levelIndex: 4,
        );
        expect(boss.isBoss, isTrue);
        expect(boss.modifiers, hasLength(1));
        expect(_gentle, containsAll(boss.modifiers));
      },
    );

    test('boss tier ≥ 3 au niveau 4 : shuffle + un tirage doux hors shuffle '
        '(signature prioritaire sur la zone douce)', () {
      // Nyangani (2592 m, 4 niveaux, ZW non tectonique) : un sommet à 4
      // niveaux a droit à un vrai boss — shuffle garanti + un doux (palette
      // élargie du tier 3, hors shuffle).
      final m = _make(id: 'zw_nyangani', altitude: 2592);
      final boss = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 4);
      expect(boss.isBoss, isTrue);
      expect(boss.modifiers, contains(LevelModifier.shuffle));
      final drawn = _active(boss)..remove(LevelModifier.shuffle);
      expect(drawn, hasLength(1));
      expect(
        _gentleExtended.difference(<LevelModifier>{LevelModifier.shuffle}),
        containsAll(drawn),
      );
    });

    test('boss tier ≥ 3 hors zone douce : shuffle + un modifier tiré '
        '(double pic)', () {
      final m = _make(id: 'ci_nimba', altitude: 1752, totalLevels: 6);
      final boss = LevelDifficultyResolver.resolve(mountain: m, levelIndex: 6);
      expect(boss.isBoss, isTrue);
      expect(boss.modifiers, contains(LevelModifier.shuffle));
      expect(
        _active(boss),
        hasLength(2),
        reason: 'shuffle garanti + le modificateur tiré (≠ shuffle)',
      );
    });

    test('tout boss tier ≥ 3 des montagnes réelles : exactement 2 modifiers '
        'actifs dont shuffle', () {
      var checked = 0;
      for (final m in _loadRealMountains()) {
        final tier = LevelDifficultyResolver.tierForAltitude(m.altitude);
        if (tier < 3) continue;
        checked++;
        final boss = LevelDifficultyResolver.resolve(
          mountain: m,
          levelIndex: m.totalLevels,
        );
        expect(boss.modifiers, contains(LevelModifier.shuffle), reason: m.id);
        expect(_active(boss), hasLength(2), reason: m.id);
      }
      expect(checked, greaterThan(30));
    });

    test('boss tier 1-2 : jamais la signature shuffle, un seul modifier', () {
      for (final m in _loadRealMountains()) {
        if (LevelDifficultyResolver.tierForAltitude(m.altitude) >= 3) continue;
        final boss = LevelDifficultyResolver.resolve(
          mountain: m,
          levelIndex: m.totalLevels,
        );
        if (m.totalLevels <= 2) {
          expect(boss.modifiers, isEmpty, reason: m.id);
          continue;
        }
        expect(_active(boss), hasLength(1), reason: m.id);
        expect(_gentle, containsAll(_active(boss)), reason: m.id);
      }
    });
  });

  group('LevelDifficultyResolver — palette douce par tier (niveaux 3-4)', () {
    test('tiers 1-2 : {wind, shuffle, rain} ; tier ≥ 3 : + mirage, spirit', () {
      final t2 = _make(id: 't2', altitude: 900);
      final t3 = _make(id: 't3', altitude: 2000);
      for (final lvl in <int>[3, 4]) {
        expect(
          LevelDifficultyResolver.candidateModifiers(
            mountain: t2,
            levelIndex: lvl,
          ).toSet(),
          _gentle,
        );
        expect(
          LevelDifficultyResolver.candidateModifiers(
            mountain: t3,
            levelIndex: lvl,
          ).toSet(),
          _gentleExtended,
        );
      }
    });

    test(
      'reverse et fog jamais aux niveaux 3-4 sur les 52 montagnes réelles',
      () {
        for (final m in _loadRealMountains()) {
          for (final lvl in <int>[3, 4]) {
            if (lvl > m.totalLevels) continue;
            final c = LevelDifficultyResolver.resolve(
              mountain: m,
              levelIndex: lvl,
            );
            expect(
              c.modifiers,
              isNot(contains(LevelModifier.reverse)),
              reason: '${m.id} niv $lvl',
            );
            expect(
              c.modifiers,
              isNot(contains(LevelModifier.fog)),
              reason: '${m.id} niv $lvl',
            );
          }
        }
      },
    );

    test('sur les 52 montagnes réelles, les niveaux 3-4 tier ≥ 3 émettent '
        'mirage et spirit', () {
      final seen = <LevelModifier>{};
      for (final m in _loadRealMountains()) {
        if (LevelDifficultyResolver.tierForAltitude(m.altitude) < 3) continue;
        for (final lvl in <int>[3, 4]) {
          if (lvl > m.totalLevels) continue;
          seen.addAll(
            _active(
              LevelDifficultyResolver.resolve(mountain: m, levelIndex: lvl),
            ),
          );
        }
      }
      expect(
        seen,
        containsAll(<LevelModifier>[
          LevelModifier.mirage,
          LevelModifier.spirit,
        ]),
      );
    });
  });

  group('LevelDifficultyResolver — signatures de palier (niveaux 5+)', () {
    test('tier ≥ 4 non tectonique à 5 niveaux : reverse garanti (boss = '
        'shuffle + reverse si non tiré avant)', () {
      for (final m in <Mountain>[
        _makeLong(
          id: 'dz_tahat',
          altitude: 3003,
          countryCode: 'DZ',
          totalLevels: 5,
        ),
        _makeLong(
          id: 'za_mafadi',
          altitude: 3450,
          countryCode: 'ZA',
          totalLevels: 5,
        ),
        _makeLong(
          id: 'ma_toubkal',
          altitude: 4167,
          countryCode: 'MA',
          totalLevels: 5,
        ),
      ]) {
        expect(
          _ladder(m).skip(4).expand(_active),
          contains(LevelModifier.reverse),
          reason: m.id,
        );
      }
    });

    test('tier 3 ≥ 2000 m non tectonique à 5 niveaux : fog garanti', () {
      for (final m in <Mountain>[
        _makeLong(
          id: 'ng_chappal_waddi',
          altitude: 2419,
          countryCode: 'NG',
          totalLevels: 5,
        ),
        _makeLong(
          id: 'eg_catherine',
          altitude: 2629,
          countryCode: 'EG',
          totalLevels: 5,
        ),
        _makeLong(
          id: 'mg_maromokotro',
          altitude: 2876,
          countryCode: 'MG',
          totalLevels: 5,
        ),
      ]) {
        expect(
          _ladder(m).skip(4).expand(_active),
          contains(LevelModifier.fog),
          reason: m.id,
        );
      }
    });

    test('tier 3 < 2000 m à 5+ niveaux : reverse garanti (pas de fog '
        'éligible)', () {
      final nimba = _makeLong(id: 'ci_nimba', altitude: 1752, totalLevels: 6);
      final deep = _ladder(nimba).skip(4).expand(_active).toSet();
      expect(deep, contains(LevelModifier.reverse));
      expect(deep, isNot(contains(LevelModifier.fog)));
    });

    test('la signature tectonique garde la priorité sur un seul niveau 5', () {
      // Cinq niveaux tectoniques tier ≥ 4 : un seul emplacement profond, il
      // revient à earthquake même si le tirage y avait mis fog ou reverse.
      for (final m in <Mountain>[
        _makeLong(
          id: 'cm_cameroon',
          altitude: 4040,
          countryCode: 'CM',
          totalLevels: 5,
        ),
        _makeLong(
          id: 'et_ras_dashen',
          altitude: 4550,
          countryCode: 'ET',
          totalLevels: 5,
        ),
        _makeLong(
          id: 'cd_marguerite',
          altitude: 5109,
          countryCode: 'CD',
          totalLevels: 5,
        ),
      ]) {
        final boss = LevelDifficultyResolver.resolve(
          mountain: m,
          levelIndex: 5,
        );
        expect(_active(boss), <LevelModifier>{
          LevelModifier.shuffle,
          LevelModifier.earthquake,
        }, reason: m.id);
      }
    });

    test('à 8 niveaux (Kilimandjaro), earthquake, reverse et fog sont tous '
        'présents sur les niveaux 5+', () {
      final kili = _makeLong(
        id: 'tz_kilimanjaro',
        altitude: 5895,
        countryCode: 'TZ',
        totalLevels: 8,
      );
      final deep = _ladder(kili).skip(4).expand(_active).toSet();
      expect(
        deep,
        containsAll(<LevelModifier>[
          LevelModifier.earthquake,
          LevelModifier.reverse,
          LevelModifier.fog,
        ]),
      );
    });

    test('répartition sur les 224 niveaux réels : reverse ≥ 6, fog ≥ 4, '
        'earthquake ≥ 8, mirage et spirit ≥ 10', () {
      // Garde-fou contre une régression de variété. Les niveaux ≥ 5 ne sont
      // que 17 sur 224 et ≥ 6 sont réservés à earthquake : fog ≥ 6 n'est
      // pas atteignable sans rendre la zone profonde entièrement fixe.
      final counts = <LevelModifier, int>{};
      var levels = 0;
      for (final m in _loadRealMountains()) {
        for (final c in _ladder(m)) {
          levels++;
          for (final mod in c.modifiers) {
            counts[mod] = (counts[mod] ?? 0) + 1;
          }
        }
      }
      expect(levels, 224);
      expect(counts[LevelModifier.reverse] ?? 0, greaterThanOrEqualTo(6));
      expect(counts[LevelModifier.fog] ?? 0, greaterThanOrEqualTo(4));
      expect(counts[LevelModifier.earthquake] ?? 0, greaterThanOrEqualTo(8));
      expect(counts[LevelModifier.mirage] ?? 0, greaterThanOrEqualTo(10));
      expect(counts[LevelModifier.spirit] ?? 0, greaterThanOrEqualTo(10));
    });
  });

  group('LevelDifficultyResolver — signature tectonique', () {
    test(
      'sommet tectonique tier ≥ 3 à 4 niveaux : boss = shuffle + earthquake',
      () {
        // Karthala (KM, 2361 m, 4 niveaux).
        final m = _make(id: 'km_karthala', altitude: 2361, countryCode: 'KM');
        final boss = LevelDifficultyResolver.resolve(
          mountain: m,
          levelIndex: 4,
        );
        expect(_active(boss), <LevelModifier>{
          LevelModifier.shuffle,
          LevelModifier.earthquake,
        });
      },
    );

    test('sommet tectonique tier ≥ 3 à 5+ niveaux : earthquake au moins une '
        'fois sur les niveaux 5+', () {
      for (final m in <Mountain>[
        _makeLong(id: 'cm', altitude: 4040, countryCode: 'CM', totalLevels: 5),
        _makeLong(id: 'tz', altitude: 5895, countryCode: 'TZ', totalLevels: 8),
        _makeLong(id: 'ke', altitude: 5199, countryCode: 'KE', totalLevels: 6),
      ]) {
        final deep = _ladder(m).skip(4).expand(_active);
        expect(deep, contains(LevelModifier.earthquake), reason: m.id);
      }
    });

    test('toute montagne tectonique tier ≥ 3 des données réelles émet '
        'earthquake au moins une fois ; jamais les non-tectoniques', () {
      const tectonic = <String>{
        'CM',
        'KM',
        'CD',
        'RW',
        'UG',
        'KE',
        'TZ',
        'ET',
        'ER',
        'DJ',
      };
      var checked = 0;
      for (final m in _loadRealMountains()) {
        final tier = LevelDifficultyResolver.tierForAltitude(m.altitude);
        final emitted = _ladder(m).expand(_active).toSet();
        if (tectonic.contains(m.countryCode) && tier >= 3) {
          checked++;
          expect(emitted, contains(LevelModifier.earthquake), reason: m.id);
        } else {
          expect(
            emitted,
            isNot(contains(LevelModifier.earthquake)),
            reason: m.id,
          );
        }
      }
      expect(checked, greaterThan(0));
    });
  });

  group(
    'LevelDifficultyResolver — candidats par environnement (niveau 5+)',
    () {
      test('tectonique tier ≥ 3 ⇒ earthquake candidat ; jamais ailleurs', () {
        // Mt Cameroun simulé : code CM, 4040 m, tier 4.
        final cm = _makeLong(id: 'cm', altitude: 4040, countryCode: 'CM');
        expect(
          LevelDifficultyResolver.candidateModifiers(
            mountain: cm,
            levelIndex: 5,
          ),
          contains(LevelModifier.earthquake),
        );
        // Non tectonique, même altitude : pas d'earthquake.
        final ma = _makeLong(id: 'ma', altitude: 4167, countryCode: 'MA');
        expect(
          LevelDifficultyResolver.candidateModifiers(
            mountain: ma,
            levelIndex: 5,
          ),
          isNot(contains(LevelModifier.earthquake)),
        );
        // Tectonique mais tier 2 : pas d'earthquake non plus.
        final lowTectonic = _makeLong(
          id: 'ke-low',
          altitude: 900,
          countryCode: 'KE',
        );
        expect(
          LevelDifficultyResolver.candidateModifiers(
            mountain: lowTectonic,
            levelIndex: 5,
          ),
          isNot(contains(LevelModifier.earthquake)),
        );
      });

      test("wind candidat dès 3000 m, fog dès 2000 m, ni l'un ni l'autre "
          'en dessous', () {
        final high = _makeLong(id: 'ma', altitude: 4167, countryCode: 'MA');
        final highCandidates = LevelDifficultyResolver.candidateModifiers(
          mountain: high,
          levelIndex: 5,
        );
        expect(highCandidates, contains(LevelModifier.wind));
        expect(highCandidates, contains(LevelModifier.fog));

        // Mt Sunzu Zambie simulé : code ZM, 2339 m → fog mais pas wind.
        final mid = _makeLong(id: 'zm', altitude: 2339, countryCode: 'ZM');
        final midCandidates = LevelDifficultyResolver.candidateModifiers(
          mountain: mid,
          levelIndex: 5,
        );
        expect(midCandidates, contains(LevelModifier.fog));
        expect(midCandidates, isNot(contains(LevelModifier.wind)));

        // Nimba 1752 m : ni fog ni wind, mais la palette cognitive tier 3.
        final low = _makeLong(id: 'ci_nimba', altitude: 1752);
        final lowCandidates = LevelDifficultyResolver.candidateModifiers(
          mountain: low,
          levelIndex: 5,
        );
        expect(lowCandidates, isNot(contains(LevelModifier.wind)));
        expect(lowCandidates, isNot(contains(LevelModifier.fog)));
        expect(
          lowCandidates,
          containsAll(<LevelModifier>[
            LevelModifier.reverse,
            LevelModifier.mirage,
            LevelModifier.spirit,
            LevelModifier.rain,
            LevelModifier.shuffle,
          ]),
        );
      });

      test('tier 2 au niveau 5+ : rain candidat, pas la palette cognitive', () {
        final t2 = _makeLong(id: 't2-long', altitude: 900);
        final candidates = LevelDifficultyResolver.candidateModifiers(
          mountain: t2,
          levelIndex: 5,
        );
        expect(candidates, contains(LevelModifier.rain));
        expect(candidates, isNot(contains(LevelModifier.reverse)));
        expect(candidates, isNot(contains(LevelModifier.mirage)));
        expect(candidates, isNot(contains(LevelModifier.spirit)));
        // Garde-fou d'alternance : au moins 2 candidats.
        expect(candidates.length, greaterThanOrEqualTo(2));
      });

      test('le modifier actif émis appartient toujours aux candidats', () {
        for (final m in _loadRealMountains()) {
          for (var lvl = 5; lvl <= m.totalLevels; lvl++) {
            final config = LevelDifficultyResolver.resolve(
              mountain: m,
              levelIndex: lvl,
            );
            final candidates = LevelDifficultyResolver.candidateModifiers(
              mountain: m,
              levelIndex: lvl,
            );
            final active = _active(config)
              ..remove(LevelModifier.shuffle); // signature boss, hors tirage
            expect(candidates, containsAll(active), reason: '${m.id} niv $lvl');
          }
        }
      });
    },
  );

  group('LevelDifficultyResolver — rotation des modifiers', () {
    test('niveaux 1-2 : aucun modifier (tutoriel strict), même à 5895 m', () {
      for (final m in <Mountain>[
        _make(id: 'low', altitude: 100),
        _makeLong(id: 'kili', altitude: 5895, countryCode: 'TZ'),
      ]) {
        for (final lvl in <int>[1, 2]) {
          final c = LevelDifficultyResolver.resolve(
            mountain: m,
            levelIndex: lvl,
          );
          expect(c.modifiers, isEmpty, reason: '${m.id} niv $lvl');
        }
      }
    });

    test('niveaux 3-4 : exactement un modifier doux (hors thinAir)', () {
      for (final m in <Mountain>[
        _make(id: 'low', altitude: 100),
        _makeLong(id: 'cm', altitude: 4040, countryCode: 'CM'),
        _makeLong(id: 'kili', altitude: 5895, countryCode: 'TZ'),
      ]) {
        for (final lvl in <int>[3, 4]) {
          final c = LevelDifficultyResolver.resolve(
            mountain: m,
            levelIndex: lvl,
          );
          final active = _active(c);
          expect(active, hasLength(1), reason: '${m.id} niv $lvl');
          expect(
            _gentleFor(m),
            containsAll(active),
            reason: '${m.id} niv $lvl',
          );
        }
      }
    });

    test('thinAir passif dès le niveau 3 au-dessus de 4000 m, jamais en '
        'dessous', () {
      final kili = _makeLong(id: 'kili', altitude: 5895, countryCode: 'TZ');
      for (var lvl = 3; lvl <= kili.totalLevels; lvl++) {
        final c = LevelDifficultyResolver.resolve(
          mountain: kili,
          levelIndex: lvl,
        );
        expect(
          c.modifiers,
          contains(LevelModifier.thinAir),
          reason: 'niv $lvl',
        );
      }
      final toubkalLike = _makeLong(id: 'dz', altitude: 3999);
      for (final c in _ladder(toubkalLike)) {
        expect(c.modifiers, isNot(contains(LevelModifier.thinAir)));
      }
    });

    test('un seul modifier actif par niveau hors boss signature', () {
      for (final m in _loadRealMountains()) {
        final ladder = _ladder(m);
        for (var i = 0; i < ladder.length; i++) {
          final c = ladder[i];
          final active = _active(c);
          if (c.isBoss && c.difficultyTier >= 3) {
            expect(active, hasLength(2), reason: '${m.id} boss');
          } else if (i + 1 >= 3) {
            expect(active, hasLength(1), reason: '${m.id} niv ${i + 1}');
          }
        }
      }
    });

    test('jamais deux niveaux consécutifs avec le même modifier actif '
        '(52 montagnes réelles)', () {
      final mountains = _loadRealMountains();
      expect(mountains, hasLength(52));
      for (final m in mountains) {
        final ladder = _ladder(m);
        for (var i = 1; i < ladder.length; i++) {
          final previous = _active(ladder[i - 1]);
          final current = _active(ladder[i]);
          if (previous.isEmpty || current.isEmpty) continue;
          // Strict : la signature boss `shuffle` compte aussi — le niveau
          // qui précède un boss signature ne tire jamais shuffle.
          expect(
            previous.intersection(current),
            isEmpty,
            reason: '${m.id} niveaux $i → ${i + 1} : $previous vs $current',
          );
        }
      }
    });

    test('variété : la zone douce ne donne pas toujours wind', () {
      // Sur les 52 sommets réels, les niveaux 3-4 doivent tirer au moins
      // deux modificateurs doux différents au total.
      final seen = <LevelModifier>{};
      for (final m in _loadRealMountains()) {
        for (final lvl in <int>[3, 4]) {
          if (lvl > m.totalLevels) continue;
          seen.addAll(
            _active(
              LevelDifficultyResolver.resolve(mountain: m, levelIndex: lvl),
            ),
          );
        }
      }
      expect(seen.length, greaterThanOrEqualTo(2));
    });

    test('déterminisme : deux appels = même résultat sur toutes les '
        'montagnes réelles', () {
      for (final m in _loadRealMountains()) {
        expect(_ladder(m), _ladder(m), reason: m.id);
      }
    });

    test('ensemble émis ⊆ liste autorisée (runtime existant ou vague '
        'suivante)', () {
      final emitted = <LevelModifier>{};
      for (final m in _loadRealMountains()) {
        for (final c in _ladder(m)) {
          emitted.addAll(c.modifiers);
        }
      }
      // Sommets synthétiques pour couvrir les branches absentes des données
      // réelles (tier 1-2 à 5+ niveaux).
      for (final m in <Mountain>[
        _makeLong(id: 'syn-t1', altitude: 100),
        _makeLong(id: 'syn-t2', altitude: 900),
      ]) {
        for (final c in _ladder(m)) {
          emitted.addAll(c.modifiers);
        }
      }
      expect(_allowedModifiers, containsAll(emitted));
    });
  });

  group('LevelDifficultyResolver — distractorCount par tier', () {
    test('tier 1-2 → 0 distracteur au niveau 1 (zone tutoriel)', () {
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

    test('bases 1 → 2 → 3 distracteurs aux tiers 3/4/5 (niveau 1)', () {
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

  group('LevelDifficultyResolver — tierForAltitude (API publique)', () {
    test('mappage cohérent avec resolve() pour chaque tier', () {
      expect(LevelDifficultyResolver.tierForAltitude(0), 1);
      expect(LevelDifficultyResolver.tierForAltitude(699), 1);
      expect(LevelDifficultyResolver.tierForAltitude(700), 2);
      expect(LevelDifficultyResolver.tierForAltitude(1499), 2);
      expect(LevelDifficultyResolver.tierForAltitude(1500), 3);
      expect(LevelDifficultyResolver.tierForAltitude(2999), 3);
      expect(LevelDifficultyResolver.tierForAltitude(3000), 4);
      expect(LevelDifficultyResolver.tierForAltitude(4499), 4);
      expect(LevelDifficultyResolver.tierForAltitude(4500), 5);
      expect(LevelDifficultyResolver.tierForAltitude(8848), 5);
    });
  });

  group('LevelDifficultyResolver — revealsAnswerOnFailure', () {
    test('tier 1 (amorçage) révèle la réponse gratuitement', () {
      final t1 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't1', altitude: 100),
        levelIndex: 1,
      );
      expect(t1.revealsAnswerOnFailure, isTrue);
    });

    test('tier 2+ masque la réponse par défaut (sink économique)', () {
      final t2 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't2', altitude: 1000),
        levelIndex: 1,
      );
      final t3 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't3', altitude: 2000),
        levelIndex: 1,
      );
      final t4 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't4', altitude: 3500),
        levelIndex: 1,
      );
      final t5 = LevelDifficultyResolver.resolve(
        mountain: _make(id: 't5', altitude: 5000),
        levelIndex: 1,
      );
      expect(t2.revealsAnswerOnFailure, isFalse);
      expect(t3.revealsAnswerOnFailure, isFalse);
      expect(t4.revealsAnswerOnFailure, isFalse);
      expect(t5.revealsAnswerOnFailure, isFalse);
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

  group('LevelDifficultyResolver — structure du tour (LevelKind)', () {
    List<LevelKind> kindsOf(Mountain m) => <LevelKind>[
      for (var l = 1; l <= m.totalLevels; l++)
        LevelDifficultyResolver.resolve(mountain: m, levelIndex: l).kind,
    ];

    test('déterminisme : deux appels = même kind sur toutes les montagnes '
        'réelles', () {
      for (final m in _loadRealMountains()) {
        expect(kindsOf(m), kindsOf(m), reason: m.id);
      }
    });

    test('niveaux 1-2 : toujours classic (tutoriel), même à 5895 m', () {
      for (final m in _loadRealMountains()) {
        final kinds = kindsOf(m);
        for (var l = 1; l <= 2 && l <= m.totalLevels; l++) {
          expect(kinds[l - 1], LevelKind.classic, reason: '${m.id} L$l');
        }
      }
      final high = _makeLong(id: 'high', altitude: 5895);
      expect(kindsOf(high).take(2), everyElement(LevelKind.classic));
    });

    test('boss tier ≥ 3 → blindBoss ; boss tier 1-2 → jamais blindBoss', () {
      for (final m in _loadRealMountains()) {
        final tier = LevelDifficultyResolver.tierForAltitude(m.altitude);
        final boss = LevelDifficultyResolver.resolve(
          mountain: m,
          levelIndex: m.totalLevels,
        );
        expect(boss.isBoss, isTrue);
        expect(
          boss.kind,
          tier >= 3 ? LevelKind.blindBoss : isNot(LevelKind.blindBoss),
          reason: m.id,
        );
      }
    });

    test('blindBoss uniquement sur le boss', () {
      for (final m in _loadRealMountains()) {
        final kinds = kindsOf(m);
        for (var l = 1; l < m.totalLevels; l++) {
          expect(kinds[l - 1], isNot(LevelKind.blindBoss), reason: m.id);
        }
      }
    });

    test('jamais deux rafale/duo consécutifs (52 montagnes réelles + sommets '
        'synthétiques longs) ; un boss aveugle peut suivre une rafale/duo', () {
      final mountains = <Mountain>[
        ..._loadRealMountains(),
        _makeLong(id: 'long_t2', altitude: 1000, totalLevels: 12),
        _makeLong(id: 'long_t4', altitude: 4000, totalLevels: 12),
      ];
      for (final m in mountains) {
        final kinds = kindsOf(m);
        for (var i = 1; i < kinds.length; i++) {
          expect(
            kinds[i - 1].isMultiWord && kinds[i].isMultiWord,
            isFalse,
            reason: '${m.id} L$i-L${i + 1} : $kinds',
          );
        }
      }
    });

    test('le niveau précédant un boss aveugle reste tiré normalement (au '
        'moins un sommet réel enchaîne rafale/duo → blindBoss)', () {
      final before = _loadRealMountains().where((m) {
        final kinds = kindsOf(m);
        return kinds.last == LevelKind.blindBoss &&
            kinds[kinds.length - 2].isMultiWord;
      });
      expect(before, isNotEmpty);
    });

    test('duo réservé au tier ≥ 2 ; rafale possible dès le tier 1', () {
      final tier1 = _makeLong(id: 'tier1_long', altitude: 100, totalLevels: 30);
      expect(kindsOf(tier1), isNot(contains(LevelKind.duo)));
      expect(kindsOf(tier1), contains(LevelKind.rafale));
      final tier2 = _makeLong(
        id: 'tier2_long',
        altitude: 1000,
        totalLevels: 30,
      );
      expect(kindsOf(tier2), contains(LevelKind.duo));
    });

    test('répartition des 224 niveaux réels : chaque type est présent et la '
        'majorité reste classique', () {
      final counts = <LevelKind, int>{};
      var total = 0;
      for (final m in _loadRealMountains()) {
        for (final k in kindsOf(m)) {
          counts[k] = (counts[k] ?? 0) + 1;
          total++;
        }
      }
      final withMultiWord = _loadRealMountains()
          .where((m) => kindsOf(m).any((k) => k.isMultiWord))
          .length;
      // Répartition rapportée au PO (cf. rapport de la tâche).
      // ignore: avoid_print
      print(
        'Répartition des $total niveaux par kind : $counts — '
        '$withMultiWord sommets avec au moins une rafale ou un duo',
      );
      expect(total, 224);
      for (final k in LevelKind.values) {
        expect(counts[k], greaterThan(0), reason: k.name);
      }
      expect(counts[LevelKind.classic], greaterThan(total ~/ 2));
    });
  });

  group('LevelDifficultyResolver — embranchement « voie exposée »', () {
    test('niveau 3 exactement des sommets à ≥ 5 niveaux, jamais ailleurs', () {
      for (final m in _loadRealMountains()) {
        for (var l = 1; l <= m.totalLevels; l++) {
          expect(
            LevelDifficultyResolver.isBranchingLevel(
              mountain: m,
              levelIndex: l,
            ),
            m.totalLevels >= 5 && l == 3,
            reason: '${m.id} L$l',
          );
        }
      }
    });

    test('13 sommets réels concernés', () {
      final concerned = _loadRealMountains()
          .where(
            (m) => LevelDifficultyResolver.isBranchingLevel(
              mountain: m,
              levelIndex: 3,
            ),
          )
          .length;
      expect(concerned, 13);
    });

    test('exposedVariant : +1 distracteur plafonné à 4, timer ×0,8, '
        'cauris ×2, reste inchangé', () {
      const base = LevelDifficultyConfig(
        difficultyTier: 3,
        wordLengthBucket: 3,
        timerSeconds: 40,
        caurisMultiplier: 1.6,
        distractorCount: 1,
        modifiers: <LevelModifier>{LevelModifier.wind},
        kind: LevelKind.rafale,
      );
      final exposed = LevelDifficultyResolver.exposedVariant(base);
      expect(exposed.distractorCount, 2);
      expect(exposed.timerSeconds, 32);
      expect(exposed.caurisMultiplier, 3.2);
      expect(exposed.modifiers, base.modifiers);
      expect(exposed.kind, LevelKind.rafale);
      expect(exposed.difficultyTier, 3);

      final capped = LevelDifficultyResolver.exposedVariant(
        base.copyWith(distractorCount: 4),
      );
      expect(capped.distractorCount, 4);
    });
  });
}
