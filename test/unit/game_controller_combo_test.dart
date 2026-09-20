import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/solo_combo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du câblage série intra-session (`soloComboProvider`) + bonus
/// « Sans faute » + « Mélanger » dans [GameController]. Même harnais que
/// `game_controller_freehand_test.dart` (audio no-op, repo sur prefs mockées).

class _FakeAudio extends AudioController {
  _FakeAudio() : super(AudioEngine.instance);
  int hintCues = 0;
  @override
  void hapticDeselect() {}
  @override
  Future<void> playLetterSelect(int letterIdx) async {}
  @override
  Future<void> playWordComplete() async {}
  @override
  Future<void> playHintUsed() async {
    hintCues++;
  }

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

Devinette _devinette(String answer, {String? id}) => Devinette(
      id: id ?? 'test_$answer',
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

  const newPlayerCauris = 120;

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

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    audio.dispose();
    combo.dispose();
  });

  GameController build({
    required Devinette devinette,
    GameEconomyConfig economy = GameEconomyConfig.defaults,
    bool isDaily = false,
    bool hub = false,
    int timerSeconds = 30,
  }) {
    final config = LevelDifficultyConfig(
      difficultyTier: 1,
      wordLengthBucket: 1,
      timerSeconds: timerSeconds,
      caurisMultiplier: 1,
    );
    final args = GameArgs(
      devinette: devinette,
      config: config,
      mountainId: (isDaily || hub) ? null : 'mnt_test',
      levelIndex: (isDaily || hub) ? null : 1,
      isDailyChallenge: isDaily,
    );
    final c = GameController(
      args,
      audio,
      progress,
      economy,
      const NoopAnalyticsService(),
      tempo,
      combo,
    );
    controllers.add(c);
    return c;
  }

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

  /// Tape [word] lettre par lettre ; tracé déclaré « croisé » pour neutraliser
  /// le bonus à main levée et isoler série + sans faute.
  void playWord(GameController c, String word) {
    final idxs = gridIndicesFor(c, word);
    for (var i = 0; i < idxs.length - 1; i++) {
      c.selectTile(idxs[i]);
    }
    c
      ..updateTrailSelfIntersecting(true)
      ..selectTile(idxs.last);
  }

  /// Gagne [n] niveaux Sommets distincts d'affilée (devinettes différentes
  /// pour ne pas tomber dans l'anti-farm « déjà récompensée »).
  Future<GameController> winStreak(int n, {bool useHintOnLast = false}) async {
    late GameController last;
    for (var i = 0; i < n; i++) {
      final c = build(devinette: _devinette('KORA', id: 'kora_$i'));
      if (useHintOnLast && i == n - 1) c.useHint();
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);
      last = c;
    }
    return last;
  }

  int base(GameEconomyConfig eco, int timeLeft) =>
      eco.winRewardBase + timeLeft * eco.speedBonusPerSecond;

  group('série intra-session — compteur', () {
    test('chaque victoire Sommets incrémente la série (courante incluse)',
        () async {
      final c = await winStreak(2);
      expect(combo.state, 2);
      expect(c.state.comboStreak, 2);
    });

    test('défi du jour et Hub ne touchent pas la série', () async {
      combo.increment(); // série existante = 1
      final daily = build(devinette: _devinette('KORA'), isDaily: true);
      playWord(daily, 'KORA');
      final hub = build(devinette: _devinette('BOLI'), hub: true);
      playWord(hub, 'BOLI');
      await Future<void>.delayed(Duration.zero);

      expect(daily.state.phase, GamePhase.won);
      expect(hub.state.phase, GamePhase.won);
      expect(combo.state, 1);
      expect(daily.state.comboStreak, 0);
      expect(hub.state.comboStreak, 0);
    });

    test('temps écoulé (GamePhase.lost) remet la série à 0', () async {
      combo
        ..increment()
        ..increment();
      final c = build(devinette: _devinette('KORA'), timerSeconds: 1);
      // Timer.periodic 1 s : au 1er tick timeLeft <= 1 → lost.
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(c.state.phase, GamePhase.lost);
      expect(combo.state, 0);
    });
  });

  group('série intra-session — multiplicateur de récompense', () {
    test('sous le seuil (2 victoires) : pas de multiplicateur', () async {
      const eco = GameEconomyConfig.defaults; // seuil 3, ×1.5
      final c = await winStreak(2);
      expect(c.state.comboMultiplierApplied, 1.0);
      expect(c.state.caurisAwarded, base(eco, 30)); // 50
    });

    test("au seuil (3e victoire d'affilée) sans indice : ×1.5 sur la base",
        () async {
      const eco = GameEconomyConfig.defaults;
      final c = await winStreak(3);
      expect(c.state.comboStreak, 3);
      expect(c.state.comboMultiplierApplied, eco.comboMultiplier);
      expect(c.state.caurisAwarded, (base(eco, 30) * 1.5).round()); // 75
      // Le solde intègre la base bonifiée + sans faute.
      expect(
        c.state.cauris,
        newPlayerCauris + 50 + 50 + 75 + 3 * eco.perfectBonus,
      );
    });

    test('au seuil MAIS indice utilisé sur ce niveau : pas de multiplicateur '
        '(la série continue quand même)', () async {
      const eco = GameEconomyConfig.defaults;
      final c = await winStreak(3, useHintOnLast: true);
      expect(c.state.comboStreak, 3);
      expect(c.state.comboMultiplierApplied, 1.0);
      expect(c.state.caurisAwarded, base(eco, 30));
    });

    test('valeurs Remote Config respectées (seuil 2, ×2)', () async {
      final eco = GameEconomyConfig.defaults.copyWith(
        comboMinStreak: 2,
        comboMultiplier: 2,
      );
      final c1 = build(devinette: _devinette('KORA', id: 'a'), economy: eco);
      playWord(c1, 'KORA');
      final c2 = build(devinette: _devinette('KORA', id: 'b'), economy: eco);
      playWord(c2, 'KORA');
      await Future<void>.delayed(Duration.zero);

      expect(c1.state.comboMultiplierApplied, 1.0);
      expect(c2.state.comboMultiplierApplied, 2.0);
      expect(c2.state.caurisAwarded, base(eco, 30) * 2);
    });

    test('devinette déjà récompensée : 0 cauris, ni série ni sans faute '
        'crédités (anti-farm)', () async {
      const eco = GameEconomyConfig.defaults;
      await progress.markDevinetteRewarded('test_KORA');
      combo
        ..increment()
        ..increment();
      final c = build(devinette: _devinette('KORA'));
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);

      expect(c.state.comboStreak, 3); // la série, elle, avance.
      expect(c.state.comboMultiplierApplied, 1.0);
      expect(c.state.caurisAwarded, 0);
      expect(c.state.perfectBonusAwarded, 0);
      expect(c.state.cauris, newPlayerCauris);
      expect(eco.perfectBonus, greaterThan(0)); // garde-fou du test
    });
  });

  group('bonus « Sans faute »', () {
    test('aucun mot erroné → +perfectBonus crédité et persisté', () async {
      const eco = GameEconomyConfig.defaults;
      final c = build(devinette: _devinette('KORA'));
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);

      expect(c.state.wrongAttempts, 0);
      expect(c.state.perfectBonusAwarded, eco.perfectBonus);
      expect(
        progress.state.cauris,
        newPlayerCauris + base(eco, 30) + eco.perfectBonus,
      );
    });

    test('un mot erroné incrémente wrongAttempts et annule le bonus',
        () async {
      const eco = GameEconomyConfig.defaults;
      final c = build(devinette: _devinette('KORA'));
      playWord(c, 'KOAR'); // faux → validate() échoue, reste playing
      expect(c.state.phase, GamePhase.playing);
      expect(c.state.wrongAttempts, 1);

      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.phase, GamePhase.won);
      expect(c.state.perfectBonusAwarded, 0);
      expect(progress.state.cauris, newPlayerCauris + base(eco, 30));
    });

    test('restart remet wrongAttempts à 0', () {
      final c = build(devinette: _devinette('KORA'));
      playWord(c, 'KOAR');
      expect(c.state.wrongAttempts, 1);
      c.restart();
      expect(c.state.wrongAttempts, 0);
    });

    test('perfectBonus 0 (Remote Config) → aucun bonus', () async {
      final eco = GameEconomyConfig.defaults.copyWith(perfectBonus: 0);
      final c = build(devinette: _devinette('KORA'), economy: eco);
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.perfectBonusAwarded, 0);
    });

    test('défi du jour : pas de bonus sans faute', () async {
      final c = build(devinette: _devinette('KORA'), isDaily: true);
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.perfectBonusAwarded, 0);
    });
  });

  group('shuffleByPlayer — Mélanger gratuit, une fois par niveau', () {
    test('re-mélange la grille en préservant les lettres sélectionnées',
        () {
      final c = build(devinette: _devinette('KORA'));
      final idxs = gridIndicesFor(c, 'KO');
      c
        ..selectTile(idxs[0])
        ..selectTile(idxs[1]);
      expect(c.state.formedWord, 'KO');

      c.shuffleByPlayer();

      expect(c.state.shuffleUsed, isTrue);
      expect(c.state.formedWord, 'KO'); // sélection suivie après permutation
      expect(c.state.selectedIndices.length, 2);
      expect(c.state.phase, GamePhase.playing);
      expect(audio.hintCues, 1); // cue kora discret
    });

    test('second appel sur le même niveau : no-op', () {
      final c = build(devinette: _devinette('KORA'))..shuffleByPlayer();
      final after1 = List<int>.from(c.state.shuffledIndices);
      c.shuffleByPlayer();
      expect(c.state.shuffledIndices, after1);
      expect(audio.hintCues, 1);
    });

    test('restart rend le Mélanger disponible', () {
      final c = build(devinette: _devinette('KORA'))..shuffleByPlayer();
      expect(c.state.shuffleUsed, isTrue);
      c.restart();
      expect(c.state.shuffleUsed, isFalse);
    });

    test('hors phase playing : no-op', () async {
      final c = build(devinette: _devinette('KORA'));
      playWord(c, 'KORA');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.phase, GamePhase.won);
      c.shuffleByPlayer();
      expect(c.state.shuffleUsed, isFalse);
      expect(audio.hintCues, 0);
    });
  });
}
