import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/solo_combo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du runtime des modificateurs `mirage`, `rain` et `spirit` dans
/// [GameController]. Même harnais que `game_controller_combo_test.dart`
/// (audio no-op, repo sur prefs mockées), mais en `testWidgets` : le binding
/// de test fait tourner le corps sous `FakeAsync`, donc `tester.pump(d)`
/// avance l'horloge et déclenche les ticks du timer des modifiers sans
/// attendre en temps réel.

class _FakeAudio extends AudioController {
  _FakeAudio() : super(AudioEngine.instance);
  @override
  void hapticDeselect() {}
  @override
  Future<void> playLetterSelect(int letterIdx) async {}
  @override
  Future<void> playWordComplete() async {}
  @override
  Future<void> playHintUsed() async {}
  @override
  Future<void> playVictory() async {}
  @override
  Future<void> playBossVictory() async {}
  @override
  Future<void> playFailure() async {}
  @override
  Future<void> playWrongAnswer() async {}
  @override
  Future<void> playTimerTick(int bpm) async {}
}

Devinette _devinette(String answer) => Devinette(
  id: 'test_$answer',
  pack: 'culture_ci',
  country: 'ci',
  answer: answer,
  lettersPool: answer.split(''),
  riddleByLang: const <String, String>{'fr': 'Énigme test'},
  explanationByLang: const <String, String>{'fr': 'Explication test'},
  difficulty: 1,
  estimatedTimeS: 15,
  tags: const <String>[],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlayerProgressNotifier progress;
  late _FakeAudio audio;
  late TempoScheduler tempo;
  late SoloComboNotifier combo;
  final controllers = <GameController>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    progress = PlayerProgressNotifier(PlayerProgressRepository(prefs));
    audio = _FakeAudio();
    tempo = TempoScheduler();
    combo = SoloComboNotifier();
  });

  /// Libère les controllers **dans le corps du test** : sous `FakeAsync`, un
  /// `Timer.periodic` encore actif à la fin du test est une erreur.
  void disposeControllers() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  }

  tearDown(() {
    disposeControllers();
    audio.dispose();
    combo.dispose();
  });

  GameController build({
    required Devinette devinette,
    Set<LevelModifier> modifiers = const <LevelModifier>{},
    int distractorCount = 0,
    int timerSeconds = 120,
  }) {
    final config = LevelDifficultyConfig(
      difficultyTier: 1,
      wordLengthBucket: 1,
      timerSeconds: timerSeconds,
      caurisMultiplier: 1,
      distractorCount: distractorCount,
      modifiers: modifiers,
    );
    final args = GameArgs(
      devinette: devinette,
      config: config,
      mountainId: 'mnt_test',
      levelIndex: 1,
    );
    final c = GameController(
      args,
      audio,
      progress,
      GameEconomyConfig.defaults,
      const NoopAnalyticsService(),
      tempo,
      combo,
    );
    controllers.add(c);
    return c;
  }

  /// Indices grille à taper, dans l'ordre, pour former [word].
  List<int> gridIndicesFor(GameController c, String word) {
    final letters = c.state.displayLetters;
    final used = <int>{};
    final result = <int>[];
    for (final ch in word.split('')) {
      final pick = [
        for (var i = 0; i < letters.length; i++)
          if (letters[i] == ch && !used.contains(i)) i,
      ].first;
      used.add(pick);
      result.add(pick);
    }
    return result;
  }

  group("mirage — une lettre fausse à l'initialisation", () {
    test(
      'pool effectif = original + distracteurs + 1, mirageIndices non vide',
      () {
        final c = build(
          devinette: _devinette('KORA'),
          modifiers: <LevelModifier>{LevelModifier.mirage},
          distractorCount: 2,
        );
        final s = c.state;
        expect(s.effectivePool.length, 4 + 2 + 1);
        expect(s.mirageIndices, hasLength(1));
        // La lettre mirage n'appartient pas au mot et se projette bien en
        // index grille (même lettre des deux côtés).
        final mirageIdx = s.mirageIndices.single;
        final mirageLetter = s.effectivePool[mirageIdx];
        expect('KORA'.contains(mirageLetter), isFalse);
        expect(s.mirageGridIndices, hasLength(1));
        expect(s.displayLetters[s.mirageGridIndices.single], mirageLetter);
        // Hors mirage : aucun distracteur ne double une lettre du mot.
        expect(s.shuffledIndices.length, s.effectivePool.length);
      },
    );

    test('sans le modifier : pas de tuile mirage', () {
      final c = build(devinette: _devinette('KORA'), distractorCount: 2);
      expect(c.state.effectivePool.length, 6);
      expect(c.state.mirageIndices, isEmpty);
      expect(c.state.mirageGridIndices, isEmpty);
    });

    test("pool déjà au plafond de tuiles (16) : le mirage ne s'ajoute pas", () {
      // 12 lettres + 4 distracteurs = 16 = plafond → pas de 17e tuile.
      final c = build(
        devinette: _devinette('BOULANGERIES'),
        modifiers: <LevelModifier>{LevelModifier.mirage},
        distractorCount: 4,
      );
      expect(c.state.effectivePool.length, 16);
      expect(c.state.mirageIndices, isEmpty);
    });

    test('la tuile mirage reste tappable et compte comme une lettre', () {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.mirage},
      );
      final mirageGrid = c.state.mirageGridIndices.single;
      c.selectTile(mirageGrid);
      expect(c.state.selectedIndices, <int>[mirageGrid]);
      expect(
        c.state.formedWord,
        c.state.effectivePool[c.state.mirageIndices.single],
      );
    });

    test('restart retire un nouveau mirage (toujours exactement un)', () {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.mirage},
      )..restart();
      expect(c.state.effectivePool.length, 5);
      expect(c.state.mirageIndices, hasLength(1));
    });
  });

  group('rain — flou 1 s toutes les 4 s', () {
    testWidgets(
      'rainBlurActive vrai au tick 4, faux au tick 5, vrai au tick 8',
      (tester) async {
        final c = build(
          devinette: _devinette('KORA'),
          modifiers: <LevelModifier>{LevelModifier.rain},
        );
        expect(c.state.rainBlurActive, isFalse);

        await tester.pump(const Duration(seconds: 3));
        expect(c.state.rainBlurActive, isFalse);
        await tester.pump(const Duration(seconds: 1)); // tick 4
        expect(c.state.rainBlurActive, isTrue);
        await tester.pump(const Duration(seconds: 1)); // tick 5
        expect(c.state.rainBlurActive, isFalse);
        await tester.pump(const Duration(seconds: 3)); // tick 8
        expect(c.state.rainBlurActive, isTrue);

        disposeControllers();
      },
    );

    testWidgets(
      "pause pendant l'averse lève le flou ; reprise repart du tick 0",
      (tester) async {
        final c = build(
          devinette: _devinette('KORA'),
          modifiers: <LevelModifier>{LevelModifier.rain},
        );
        await tester.pump(const Duration(seconds: 4)); // tick 4 : flou
        expect(c.state.rainBlurActive, isTrue);

        c.pause();
        expect(c.state.rainBlurActive, isFalse);
        await tester.pump(const Duration(seconds: 10)); // rien ne tourne
        expect(c.state.rainBlurActive, isFalse);

        c.resume();
        await tester.pump(const Duration(seconds: 3)); // ticks 1..3
        expect(c.state.rainBlurActive, isFalse);
        await tester.pump(const Duration(seconds: 1)); // tick 4
        expect(c.state.rainBlurActive, isTrue);

        disposeControllers();
      },
    );
  });

  group('spirit — emprunte 1 tuile 3 s toutes les 10 s', () {
    testWidgets('tuile masquée au tick 10, rendue au tick 13', (tester) async {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.spirit},
      );
      await tester.pump(const Duration(seconds: 9));
      expect(c.state.spiritHiddenIndex, isNull);
      expect(c.state.hiddenTileIndices, isEmpty);

      await tester.pump(const Duration(seconds: 1)); // tick 10
      final borrowed = c.state.spiritHiddenIndex;
      expect(borrowed, isNotNull);
      expect(c.state.hiddenTileIndices, <int>{borrowed!});

      await tester.pump(const Duration(seconds: 2)); // tick 12 : toujours
      expect(c.state.spiritHiddenIndex, borrowed);
      await tester.pump(const Duration(seconds: 1)); // tick 13 : rendue
      expect(c.state.spiritHiddenIndex, isNull);
      expect(c.state.hiddenTileIndices, isEmpty);

      await tester.pump(const Duration(seconds: 7)); // tick 20 : nouveau tour
      expect(c.state.spiritHiddenIndex, isNotNull);

      disposeControllers();
    });

    testWidgets("n'emprunte jamais une tuile sélectionnée", (tester) async {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.spirit},
      );
      // 3 lettres sur 4 sélectionnées → une seule candidate possible.
      final idxs = gridIndicesFor(c, 'KOR');
      for (final i in idxs) {
        c.selectTile(i);
      }
      final free = <int>{0, 1, 2, 3}.difference(idxs.toSet()).single;

      await tester.pump(const Duration(seconds: 10));
      expect(c.state.spiritHiddenIndex, free);

      disposeControllers();
    });

    testWidgets("toutes les tuiles prises : l'esprit passe son tour", (
      tester,
    ) async {
      final c = build(
        devinette: _devinette('KORAS'),
        modifiers: <LevelModifier>{LevelModifier.spirit, LevelModifier.fog},
      );
      // 4 lettres sur 5 sélectionnées, la 5e sous le fog (tick 10 = 2 × 5,
      // le fog se pose avant l'esprit dans le tick) : rien à emprunter.
      for (final i in gridIndicesFor(c, 'KORA')) {
        c.selectTile(i);
      }
      await tester.pump(const Duration(seconds: 10));
      // Le fog tombe forcément sur une tuile ; s'il a pris la seule libre,
      // l'esprit n'a aucune candidate et laisse `spiritHiddenIndex` à null.
      final fogged = c.state.fogHiddenIndices;
      final spirit = c.state.spiritHiddenIndex;
      if (spirit != null) {
        expect(c.state.selectedIndices, isNot(contains(spirit)));
        expect(fogged, isNot(contains(spirit)));
      }
      expect(c.state.hiddenTileIndices, containsAll(fogged));

      disposeControllers();
    });

    testWidgets("selectTile ignore une tuile empruntée par l'esprit", (
      tester,
    ) async {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.spirit},
      );
      await tester.pump(const Duration(seconds: 10));
      final borrowed = c.state.spiritHiddenIndex!;

      c.selectTile(borrowed);
      expect(c.state.selectedIndices, isEmpty);

      // Une fois rendue, la même tuile redevient sélectionnable.
      await tester.pump(const Duration(seconds: 3));
      c.selectTile(borrowed);
      expect(c.state.selectedIndices, <int>[borrowed]);

      disposeControllers();
    });

    testWidgets('pause rend la lettre empruntée ; reprise repart du tick 0', (
      tester,
    ) async {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.spirit},
      );
      await tester.pump(const Duration(seconds: 10));
      expect(c.state.spiritHiddenIndex, isNotNull);

      c.pause();
      expect(c.state.spiritHiddenIndex, isNull);

      c.resume();
      await tester.pump(const Duration(seconds: 9));
      expect(c.state.spiritHiddenIndex, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.spiritHiddenIndex, isNotNull);

      disposeControllers();
    });

    testWidgets('la lettre empruntée suit la permutation (Mélanger)', (
      tester,
    ) async {
      final c = build(
        devinette: _devinette('KORA'),
        modifiers: <LevelModifier>{LevelModifier.spirit},
      );
      await tester.pump(const Duration(seconds: 10));
      final before = c.state.spiritHiddenIndex!;
      final letter = c.state.displayLetters[before];

      c.shuffleByPlayer();
      final after = c.state.spiritHiddenIndex!;
      expect(c.state.displayLetters[after], letter);

      disposeControllers();
    });
  });

  group('GameState.hiddenTileIndices', () {
    test('union fog ∪ esprit', () {
      final base = build(devinette: _devinette('KORA')).state;
      expect(base.hiddenTileIndices, isEmpty);
      final s = base.copyWith(fogHiddenIndices: <int>{1}, spiritHiddenIndex: 2);
      expect(s.hiddenTileIndices, <int>{1, 2});
      expect(s.copyWith(clearSpiritHiddenIndex: true).hiddenTileIndices, <int>{
        1,
      });
    });
  });
}
