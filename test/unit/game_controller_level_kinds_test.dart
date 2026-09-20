import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/solo_combo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests des structures de niveau (`LevelKind`) dans [GameController] :
/// rafale (enchaînement, +8 s, victoire au 3e mot, échec timer global,
/// cauris), duo (validation d'un mot sur sa longueur, erreur sur la longueur
/// max, victoire aux deux) et boss aveugle (effacement, relecture, coût).
/// Même harnais que `game_controller_modifiers_test.dart` : les tests à
/// horloge sont en `testWidgets` (FakeAsync), les autres en `test`.

class _FakeAudio extends AudioController {
  _FakeAudio() : super(AudioEngine.instance);
  int wordCompleteCues = 0;
  int victoryCues = 0;
  int hintCues = 0;
  @override
  void hapticDeselect() {}
  @override
  Future<void> playLetterSelect(int letterIdx) async {}
  @override
  Future<void> playWordComplete() async {
    wordCompleteCues++;
  }

  @override
  Future<void> playHintUsed() async {
    hintCues++;
  }

  @override
  Future<void> playVictory() async {
    victoryCues++;
  }

  @override
  Future<void> playBossVictory() async {
    victoryCues++;
  }

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
  riddleByLang: <String, String>{'fr': 'Énigme $answer'},
  explanationByLang: const <String, String>{'fr': 'Explication test'},
  difficulty: 1,
  estimatedTimeS: 15,
  tags: const <String>[],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const newPlayerCauris = 120;
  const eco = GameEconomyConfig.defaults;

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

  /// Sous `FakeAsync`, un `Timer.periodic` encore actif à la fin du test est
  /// une erreur : les tests à horloge appellent ceci avant de rendre la main.
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
    required List<String> answers,
    required LevelKind kind,
    int timerSeconds = 30,
    int distractorCount = 0,
    double caurisMultiplier = 1,
  }) {
    final config = LevelDifficultyConfig(
      difficultyTier: 1,
      wordLengthBucket: 1,
      timerSeconds: timerSeconds,
      caurisMultiplier: caurisMultiplier,
      distractorCount: distractorCount,
      kind: kind,
      isBoss: kind == LevelKind.blindBoss,
    );
    final devinettes = answers.map(_devinette).toList(growable: false);
    final args = GameArgs(
      devinette: devinettes.first,
      extraDevinettes: devinettes.sublist(1),
      config: config,
      mountainId: 'mnt_test',
      levelIndex: 3,
    );
    final c = GameController(
      args,
      audio,
      progress,
      eco,
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

  /// Tape [word] lettre par lettre ; tracé déclaré « croisé » pour
  /// neutraliser le bonus à main levée et isoler la base.
  void playWord(GameController c, String word) {
    final idxs = gridIndicesFor(c, word);
    for (var i = 0; i < idxs.length - 1; i++) {
      c.selectTile(idxs[i]);
    }
    c
      ..updateTrailSelfIntersecting(true)
      ..selectTile(idxs.last);
  }

  int base(int timeLeft) =>
      eco.winRewardBase + timeLeft * eco.speedBonusPerSecond;

  group('rafale — trois mots enchaînés, timer commun', () {
    test('état initial : mot 1/3, pool du premier mot', () {
      final c = build(
        answers: ['KORA', 'BOLI', 'DAMA'],
        kind: LevelKind.rafale,
      );
      expect(c.state.roundIndex, 0);
      expect(c.state.roundCount, 3);
      expect(c.state.devinette.answer, 'KORA');
      expect(c.state.effectivePool.toSet(), {'K', 'O', 'R', 'A'});
      expect(c.state.isDuo, isFalse);
    });

    test('mot validé (k < n) : mot suivant, nouveau pool, sélection vide, '
        '+8 s, cue accord, pas de victoire', () {
      final c = build(answers: ['KORA', 'BOLI', 'DAMA'], kind: LevelKind.rafale)
        ..useHint(); // une case révélée sur KORA, doit être effacée après
      expect(c.state.revealedPositions, hasLength(1));

      playWord(c, 'KORA');

      expect(c.state.phase, GamePhase.playing);
      expect(c.state.roundIndex, 1);
      expect(c.state.devinette.answer, 'BOLI');
      expect(c.state.effectivePool.toSet(), {'B', 'O', 'L', 'I'});
      expect(c.state.selectedIndices, isEmpty);
      expect(c.state.revealedPositions, isEmpty);
      expect(c.state.timeLeft, 30 + GameController.rafaleRoundBonusSeconds);
      expect(GameController.rafaleRoundBonusSeconds, 8);
      expect(audio.wordCompleteCues, 1);
      expect(audio.victoryCues, 0);
      expect(c.state.caurisAwarded, 0);
    });

    test('victoire au 3e mot : cauris = base × 3 × 0,6, série/sans faute '
        'une fois, les 3 devinettes marquées récompensées', () async {
      final c = build(
        answers: ['KORA', 'BOLI', 'DAMA'],
        kind: LevelKind.rafale,
      );
      playWord(c, 'KORA');
      playWord(c, 'BOLI');
      expect(c.state.roundIndex, 2);
      expect(c.state.devinette.answer, 'DAMA');
      playWord(c, 'DAMA');
      await Future<void>.delayed(Duration.zero);

      expect(c.state.phase, GamePhase.won);
      const timeLeft = 30 + 2 * GameController.rafaleRoundBonusSeconds;
      expect(c.state.timeLeft, timeLeft);
      expect(c.state.caurisAwarded, (base(timeLeft) * 3 * 0.6).round());
      expect(c.state.perfectBonusAwarded, eco.perfectBonus);
      expect(c.state.comboStreak, 1);
      expect(combo.state, 1);
      for (final id in ['test_KORA', 'test_BOLI', 'test_DAMA']) {
        expect(progress.state.isDevinetteRewarded(id), isTrue, reason: id);
      }
      expect(
        progress.state.cauris,
        newPlayerCauris + c.state.caurisAwarded + eco.perfectBonus,
      );
    });

    test(
      'mot erroné sur le 2e mot : compte une faute, la rafale continue',
      () async {
        final c = build(
          answers: ['KORA', 'BOLI', 'DAMA'],
          kind: LevelKind.rafale,
        );
        playWord(c, 'KORA');
        playWord(c, 'BLOI');
        expect(c.state.phase, GamePhase.playing);
        expect(c.state.roundIndex, 1);
        expect(c.state.wrongAttempts, 1);
        playWord(c, 'BOLI');
        playWord(c, 'DAMA');
        await Future<void>.delayed(Duration.zero);
        expect(c.state.phase, GamePhase.won);
        expect(c.state.perfectBonusAwarded, 0);
      },
    );

    test('anti-farm par devinette : une devinette déjà récompensée retire '
        'sa part (base × 2 × 0,6)', () async {
      await progress.markDevinetteRewarded('test_BOLI');
      final c = build(
        answers: ['KORA', 'BOLI', 'DAMA'],
        kind: LevelKind.rafale,
      );
      playWord(c, 'KORA');
      playWord(c, 'BOLI');
      playWord(c, 'DAMA');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.caurisAwarded, (base(c.state.timeLeft) * 2 * 0.6).round());
    });

    test('restart repart au 1er mot avec le timer initial', () {
      final c = build(
        answers: ['KORA', 'BOLI', 'DAMA'],
        kind: LevelKind.rafale,
      );
      playWord(c, 'KORA');
      c.restart();
      expect(c.state.roundIndex, 0);
      expect(c.state.devinette.answer, 'KORA');
      expect(c.state.timeLeft, 30);
    });

    test(
      'rafale sans devinettes supplémentaires : se comporte en classique',
      () async {
        final c = build(answers: ['KORA'], kind: LevelKind.rafale);
        expect(c.state.roundCount, 1);
        playWord(c, 'KORA');
        await Future<void>.delayed(Duration.zero);
        expect(c.state.phase, GamePhase.won);
        expect(c.state.caurisAwarded, (base(30) * 0.6).round());
      },
    );

    testWidgets("échec au timer global : le temps s'épuise pendant le 2e mot", (
      tester,
    ) async {
      final c = build(
        answers: ['KORA', 'BOLI', 'DAMA'],
        kind: LevelKind.rafale,
        timerSeconds: 5,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(c.state.timeLeft, 3);
      playWord(c, 'KORA');
      expect(c.state.timeLeft, 3 + GameController.rafaleRoundBonusSeconds);

      await tester.pump(const Duration(seconds: 10));
      expect(c.state.phase, GamePhase.playing);
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.phase, GamePhase.lost);
      expect(c.state.timeLeft, 0);
      expect(c.state.roundIndex, 1);
      disposeControllers();
    });
  });

  group('duo — deux mots dans une seule grille', () {
    test('pool = union multiset des lettres des deux réponses', () {
      final c = build(answers: ['KORA', 'DJEMBE'], kind: LevelKind.duo);
      expect(c.state.isDuo, isTrue);
      expect(c.state.wordCount, 2);
      expect(c.state.roundCount, 1);
      final pool = List<String>.from(c.state.effectivePool)..sort();
      expect(pool, ['A', 'B', 'D', 'E', 'E', 'J', 'K', 'M', 'O', 'R']);
      expect(c.state.remainingAnswers, ['KORA', 'DJEMBE']);
    });

    test("un mot est validé dès que la sélection l'égale (avant la longueur "
        'max) ; ses lettres restent dans la grille', () {
      final c = build(answers: ['KORA', 'DJEMBE'], kind: LevelKind.duo);
      playWord(c, 'KORA');

      expect(c.state.phase, GamePhase.playing);
      expect(c.state.isSolved(0), isTrue);
      expect(c.state.isSolved(1), isFalse);
      expect(c.state.selectedIndices, isEmpty);
      expect(c.state.formedFor(0), 'KORA');
      expect(c.state.remainingAnswers, ['DJEMBE']);
      expect(c.state.effectivePool, contains('K'));
      expect(c.state.focusDevinette.answer, 'DJEMBE');
      expect(audio.wordCompleteCues, 1);
    });

    test('sélection à la longueur max restante sans correspondre = erreur ; '
        "plus courte qu'un mot restant = pas encore", () {
      final c = build(answers: ['KORA', 'DJEMBE'], kind: LevelKind.duo);
      // 4 lettres ≠ KORA : rien ne se passe encore (DJEMBE fait 6).
      final kord = gridIndicesFor(c, 'KORD');
      for (final i in kord) {
        c.selectTile(i);
      }
      expect(c.state.wrongAttempts, 0);
      expect(c.state.formedWord, 'KORD');
      expect(c.state.formedFor(0), 'KORD');
      expect(c.state.formedFor(1), 'KORD');
      // 5 lettres : la rangée du mot de 4 ne peut plus l'afficher.
      c.selectTile(gridIndicesFor(c, 'KORDJ').last);
      expect(c.state.formedFor(0), '');
      expect(c.state.formedFor(1), 'KORDJ');
      // 6 lettres sans correspondre : erreur, sélection effacée.
      c.selectTile(gridIndicesFor(c, 'KORDJE').last);
      expect(c.state.wrongAttempts, 1);
      expect(c.state.selectedIndices, isEmpty);
      expect(c.state.phase, GamePhase.playing);
    });

    test('après le premier mot, une sélection à la longueur du mot trouvé '
        "n'est plus une erreur tant qu'elle peut devenir le second", () {
      final c = build(answers: ['KORA', 'DJEMBE'], kind: LevelKind.duo);
      playWord(c, 'KORA');
      for (final i in gridIndicesFor(c, 'DJEM')) {
        c.selectTile(i);
      }
      expect(c.state.wrongAttempts, 0);
      expect(c.state.formedWord, 'DJEM');
    });

    test('victoire aux deux mots : cauris = base × 2 × 0,75, les deux '
        'devinettes récompensées', () async {
      final c = build(answers: ['KORA', 'DJEMBE'], kind: LevelKind.duo);
      playWord(c, 'DJEMBE');
      expect(c.state.phase, GamePhase.playing);
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);

      expect(c.state.phase, GamePhase.won);
      expect(c.state.isSolved(0), isTrue);
      expect(c.state.isSolved(1), isTrue);
      expect(c.state.caurisAwarded, (base(30) * 2 * 0.75).round());
      expect(c.state.perfectBonusAwarded, eco.perfectBonus);
      expect(progress.state.isDevinetteRewarded('test_KORA'), isTrue);
      expect(progress.state.isDevinetteRewarded('test_DJEMBE'), isTrue);
      expect(audio.victoryCues, 0); // fanfare décalée de 350 ms
    });

    test("l'indice révèle une lettre du premier mot restant", () {
      final c = build(answers: ['KORA', 'DJEMBE'], kind: LevelKind.duo)
        ..useHint();
      expect(c.state.revealedPositions, hasLength(1));
      expect(c.state.secondRevealedPositions, isEmpty);
      playWord(c, 'KORA');
      c.useHint();
      expect(c.state.secondRevealedPositions, hasLength(1));
      expect(c.state.hintRevealedCount, 2);
      expect(c.state.canRevealMore, isTrue);
    });

    test('reverse : les deux séquences attendues sont inversées', () {
      final devinettes = ['KORA', 'DJEMBE'].map(_devinette).toList();
      final c = GameController(
        GameArgs(
          devinette: devinettes.first,
          extraDevinettes: devinettes.sublist(1),
          config: const LevelDifficultyConfig(
            difficultyTier: 3,
            wordLengthBucket: 2,
            timerSeconds: 30,
            caurisMultiplier: 1,
            kind: LevelKind.duo,
            modifiers: <LevelModifier>{LevelModifier.reverse},
          ),
          mountainId: 'mnt_test',
          levelIndex: 3,
        ),
        audio,
        progress,
        eco,
        const NoopAnalyticsService(),
        tempo,
        combo,
      );
      controllers.add(c);
      expect(c.state.answerFor(0), 'AROK');
      expect(c.state.answerFor(1), 'EBMEJD');
      playWord(c, 'EBMEJD');
      expect(c.state.isSolved(1), isTrue);
      expect(c.state.phase, GamePhase.playing);
    });
  });

  group('boss aveugle — énigme effacée, relecture contre du temps', () {
    testWidgets('énigme visible 8 s puis effacée ; relecture gratuite 2 s ; '
        'la seconde coûte 2 s de timer', (tester) async {
      final c = build(
        answers: ['KORA'],
        kind: LevelKind.blindBoss,
        timerSeconds: 60,
      );
      expect(c.state.riddleVisible, isTrue);
      await tester.pump(const Duration(seconds: 7));
      expect(c.state.riddleVisible, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.riddleVisible, isFalse);
      expect(c.state.timeLeft, 52);

      c.rereadRiddle();
      expect(c.state.riddleVisible, isTrue);
      expect(c.state.rereadCount, 1);
      expect(c.state.timeLeft, 52); // première relecture gratuite
      expect(audio.hintCues, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.riddleVisible, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.riddleVisible, isFalse);
      expect(c.state.timeLeft, 50);

      c.rereadRiddle();
      expect(c.state.rereadCount, 2);
      expect(c.state.timeLeft, 50 - GameController.blindRereadCostSeconds);
      expect(GameController.blindRereadCostSeconds, 2);
      // Relire pendant que l'énigme est lisible : no-op.
      c.rereadRiddle();
      expect(c.state.rereadCount, 2);
      disposeControllers();
    });

    testWidgets('restart : énigme à nouveau visible, compteur remis à zéro', (
      tester,
    ) async {
      final c = build(
        answers: ['KORA'],
        kind: LevelKind.blindBoss,
        timerSeconds: 60,
      );
      await tester.pump(const Duration(seconds: 8));
      c.rereadRiddle();
      expect(c.state.rereadCount, 1);
      c.restart();
      expect(c.state.riddleVisible, isTrue);
      expect(c.state.rereadCount, 0);
      await tester.pump(const Duration(seconds: 7));
      expect(c.state.riddleVisible, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.riddleVisible, isFalse);
      disposeControllers();
    });

    testWidgets('niveau classique : jamais effacée, rereadRiddle no-op', (
      tester,
    ) async {
      final c = build(
        answers: ['KORA'],
        kind: LevelKind.classic,
        timerSeconds: 60,
      );
      await tester.pump(const Duration(seconds: 20));
      expect(c.state.riddleVisible, isTrue);
      c.rereadRiddle();
      expect(c.state.rereadCount, 0);
      expect(audio.hintCues, 0);
      disposeControllers();
    });

    test(
      'la victoire du boss aveugle joue la fanfare boss et vaut 1 base',
      () async {
        final c = build(answers: ['KORA'], kind: LevelKind.blindBoss);
        playWord(c, 'KORA');
        await Future<void>.delayed(Duration.zero);
        expect(c.state.phase, GamePhase.won);
        expect(c.state.caurisAwarded, base(30));
      },
    );
  });
}
