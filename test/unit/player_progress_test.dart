import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerProgress', () {
    test('initial state has 120 cauris, no titles', () {
      final p = PlayerProgress.initial();
      expect(p.cauris, 120);
      expect(p.totalLevelsCompleted, 0);
      expect(p.dailyStreak, 0);
      expect(p.completedLevelsByMountain, isEmpty);
      expect(p.consecutiveFailures, 0);
      expect(p.noAdsPurchased, isFalse);
    });

    test('toJson / fromJson round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        cauris: 200,
        totalLevelsCompleted: 12,
        completedLevelsByMountain: const {'tz_kilimanjaro': 3},
        dailyStreak: 5,
        consecutiveFailures: 2,
        noAdsPurchased: true,
        lastPlayDate: DateTime(2026, 5, 3),
      );
      final json = p.toJson();
      final back = PlayerProgress.fromJson(json);
      expect(back.cauris, 200);
      expect(back.totalLevelsCompleted, 12);
      expect(back.completedLevelsByMountain['tz_kilimanjaro'], 3);
      expect(back.dailyStreak, 5);
      expect(back.consecutiveFailures, 2);
      expect(back.noAdsPurchased, isTrue);
      expect(back.lastPlayDate, DateTime(2026, 5, 3));
    });

    test('levelsOn returns 0 by default', () {
      expect(PlayerProgress.initial().levelsOn('any_mountain'), 0);
    });

    test('fromJson tolerates missing fields', () {
      final p = PlayerProgress.fromJson(const <String, dynamic>{});
      expect(p.cauris, 120);
      expect(p.totalLevelsCompleted, 0);
      expect(p.consecutiveFailures, 0);
      expect(p.noAdsPurchased, isFalse);
    });

    test('fromJson reads legacy `coins` key (pre-rebrand saves)', () {
      final p = PlayerProgress.fromJson(const <String, dynamic>{'coins': 333});
      expect(p.cauris, 333);
    });

    test('starsByLevel persistance round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        starsByLevel: const <String, int>{
          'ci_nimba#1': 3,
          'ci_nimba#2': 2,
          'tz_kilimanjaro#8': 1,
        },
      );
      final back = PlayerProgress.fromJson(p.toJson());
      expect(back.starsByLevel['ci_nimba#1'], 3);
      expect(back.starsByLevel['ci_nimba#2'], 2);
      expect(back.starsByLevel['tz_kilimanjaro#8'], 1);
    });

    test('starsByLevel absent du JSON quand vide (économie de bytes)', () {
      final json = PlayerProgress.initial().toJson();
      expect(json.containsKey('stars_by_level'), isFalse);
    });

    test('starsOnLevel retourne 0 quand niveau jamais joué', () {
      final p = PlayerProgress.initial();
      expect(
        p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
        0,
      );
    });

    test('starsOnLevel lit la valeur persistée du pack actif', () {
      // Progression par pack : clés préfixées par le pack actif.
      final p = PlayerProgress.initial().copyWith(
        activePackId: 'culture_ci',
        starsByLevel: const <String, int>{'culture_ci::ci_nimba#3': 2},
      );
      expect(
        p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        2,
      );
    });

    test('starsOnLevel ignore les étoiles d\'un autre pack', () {
      final p = PlayerProgress.initial().copyWith(
        activePackId: 'culture_ci',
        starsByLevel: const <String, int>{'football_ci::ci_nimba#3': 3},
      );
      expect(p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 3), 0);
    });

    test('failsByLevel persistance round-trip', () {
      final p = PlayerProgress.initial().copyWith(
        failsByLevel: const <String, int>{
          'ci_nimba#3': 2,
          'tz_kilimanjaro#5': 1,
        },
      );
      final back = PlayerProgress.fromJson(p.toJson());
      expect(back.failsByLevel['ci_nimba#3'], 2);
      expect(back.failsByLevel['tz_kilimanjaro#5'], 1);
    });

    test('failsByLevel absent du JSON quand vide (économie de bytes)', () {
      final json = PlayerProgress.initial().toJson();
      expect(json.containsKey('fails_by_level'), isFalse);
    });

    test('failsOnLevel retourne 0 par défaut', () {
      final p = PlayerProgress.initial();
      expect(
        p.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 1),
        0,
      );
    });

    test('failsOnLevel lit la valeur persistée du pack actif', () {
      final p = PlayerProgress.initial().copyWith(
        activePackId: 'culture_ci',
        failsByLevel: const <String, int>{'culture_ci::ci_nimba#3': 2},
      );
      expect(
        p.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 3),
        2,
      );
    });

    test('totalStars somme les étoiles du pack actif uniquement', () {
      final p = PlayerProgress.initial().copyWith(
        activePackId: 'culture_ci',
        starsByLevel: const <String, int>{
          'culture_ci::gm_red_rocks#1': 3,
          'culture_ci::gm_red_rocks#2': 2,
          'culture_ci::sn_sambadougou#1': 1,
          'culture_ci::sn_sambadougou#2': 3,
          // Étoiles d'un AUTRE pack — ne doivent pas compter dans le total
          // du pack actif (star-gate par pack).
          'football_ci::gm_red_rocks#1': 3,
        },
      );
      expect(p.totalStars, 9);
    });

    test('totalStars = 0 sur état initial', () {
      expect(PlayerProgress.initial().totalStars, 0);
    });

    group('migration v1 → v2 (progression par pack)', () {
      test('un profil v1 (sans schema_version) rattache sa progression '
          'globale au pack actif/gratuit', () {
        // JSON v1 : clés de progression GLOBALES (non préfixées), pas de
        // schema_version, un pack gratuit choisi.
        final v1 = <String, dynamic>{
          'cauris': 200,
          'free_pack_chosen': 'culture_ci',
          'owned_packs': <String>['culture_ci'],
          'levels': <String, dynamic>{'ci_nimba': 2},
          'stars_by_level': <String, dynamic>{'ci_nimba#1': 3, 'ci_nimba#2': 2},
          'fails_by_level': <String, dynamic>{'ci_nimba#2': 1},
        };

        final p = PlayerProgress.fromJson(v1);

        // Le pack actif est dérivé du pack gratuit.
        expect(p.activePackId, 'culture_ci');
        // Les clés sont désormais préfixées → les accessors par-pack lisent.
        expect(p.levelsOn('ci_nimba'), 2);
        expect(p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1), 3);
        expect(p.failsOnLevel(mountainId: 'ci_nimba', levelIndex: 2), 1);
        expect(p.totalStars, 5);
        // Stockage interne préfixé.
        expect(p.completedLevelsByMountain['culture_ci::ci_nimba'], 2);
      });

      test('un profil v1 dérive le pack actif du pack_mix dominant', () {
        final v1 = <String, dynamic>{
          'owned_packs': <String>['culture_ci', 'football_ci'],
          'pack_mix': <String, dynamic>{'culture_ci': 0.7, 'football_ci': 0.3},
          'stars_by_level': <String, dynamic>{'ci_nimba#1': 3},
        };

        final p = PlayerProgress.fromJson(v1);
        expect(p.activePackId, 'culture_ci');
        expect(p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1), 3);
      });

      test('un profil v2 (schema_version: 2) ne re-migre pas les clés', () {
        final v2 = <String, dynamic>{
          'schema_version': 2,
          'free_pack_chosen': 'culture_ci',
          'owned_packs': <String>['culture_ci'],
          'active_pack_id': 'culture_ci',
          'stars_by_level': <String, dynamic>{'culture_ci::ci_nimba#1': 3},
        };

        final p = PlayerProgress.fromJson(v2);
        // Pas de double-préfixe.
        expect(p.starsByLevel['culture_ci::ci_nimba#1'], 3);
        expect(p.starsByLevel.containsKey('culture_ci::culture_ci::ci_nimba#1'),
            isFalse);
        expect(p.starsOnLevel(mountainId: 'ci_nimba', levelIndex: 1), 3);
      });

      test('toJson écrit schema_version: 2 et active_pack_id', () {
        final json = PlayerProgress.initial()
            .copyWith(
              ownedPacks: {'culture_ci'},
              freePackChosen: 'culture_ci',
              activePackId: 'culture_ci',
            )
            .toJson();
        expect(json['schema_version'], 2);
        expect(json['active_pack_id'], 'culture_ci');
      });
    });

    group('encounteredModifiers', () {
      test('état initial = set vide', () {
        expect(PlayerProgress.initial().encounteredModifiers, isEmpty);
      });

      test('round-trip toJson / fromJson conserve le set', () {
        final p = PlayerProgress.initial().copyWith(
          encounteredModifiers: const <LevelModifier>{
            LevelModifier.reverse,
            LevelModifier.wind,
            LevelModifier.thinAir,
          },
        );
        final back = PlayerProgress.fromJson(p.toJson());
        expect(back.encounteredModifiers, <LevelModifier>{
          LevelModifier.reverse,
          LevelModifier.wind,
          LevelModifier.thinAir,
        });
      });

      test('absent du JSON quand set vide (économie de bytes)', () {
        final json = PlayerProgress.initial().toJson();
        expect(json.containsKey('encountered_modifiers'), isFalse);
      });

      test('fromJson tolère un nom inconnu (forward-compat enum)', () {
        // Simule une persistance écrite par une version future qui aurait
        // ajouté un modifier non-encore-déclaré dans l'enum local — le
        // load doit drop la valeur inconnue sans crasher.
        final back = PlayerProgress.fromJson(const <String, dynamic>{
          'encountered_modifiers': <String>[
            'reverse',
            'newModifierFromFuture',
            'wind',
          ],
        });
        expect(back.encounteredModifiers, <LevelModifier>{
          LevelModifier.reverse,
          LevelModifier.wind,
        });
      });

      test('fromJson ignore une valeur de type incorrect', () {
        // raw n'est pas une liste → fallback set vide, pas de crash.
        final back = PlayerProgress.fromJson(const <String, dynamic>{
          'encountered_modifiers': 'not a list',
        });
        expect(back.encounteredModifiers, isEmpty);
      });

      test('copyWith préserve la valeur courante quand omis', () {
        final p = PlayerProgress.initial().copyWith(
          encounteredModifiers: const <LevelModifier>{LevelModifier.fog},
        );
        final updated = p.copyWith(cauris: 999);
        expect(updated.encounteredModifiers, <LevelModifier>{LevelModifier.fog});
      });

      test('copyWith remplace par la valeur fournie', () {
        final p = PlayerProgress.initial().copyWith(
          encounteredModifiers: const <LevelModifier>{LevelModifier.fog},
        );
        final updated = p.copyWith(
          encounteredModifiers: const <LevelModifier>{
            LevelModifier.fog,
            LevelModifier.earthquake,
          },
        );
        expect(updated.encounteredModifiers, <LevelModifier>{
          LevelModifier.fog,
          LevelModifier.earthquake,
        });
      });
    });
  });
}
