import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests d'intégration de la logique d'octroi du bonus « À main levée » dans
/// [GameController.validate]. Couvre la composition octroi/refus/daily +
/// le crédit total via [PlayerProgressNotifier.recordWin] et le reset du flag.
///
/// Les pièces pures (géométrie, [GameEconomyConfig.freehandBonus]) sont
/// testées ailleurs ; ici on verrouille le câblage controller↔état↔repo.

/// AudioController no-op : on sous-classe pour neutraliser tout I/O audio /
/// haptique. Le ctor parent est tolérant en test (prefs mockées + `AudioSession`
/// fail-soft), et `AudioEngine.play` est un no-op tant que l'engine n'est pas
/// `init()`.
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

  const newPlayerCauris = 120; // PlayerProgressNotifier.initialCaurisIfNew

  late PlayerProgressNotifier progress;
  late _FakeAudio audio;
  late TempoScheduler tempo;
  final controllers = <GameController>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    progress = PlayerProgressNotifier(PlayerProgressRepository(prefs));
    audio = _FakeAudio();
    tempo = TempoScheduler();
  });

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    audio.dispose();
  });

  GameController build({
    required Devinette devinette,
    GameEconomyConfig economy = GameEconomyConfig.defaults,
    bool isDaily = false,
    double caurisMultiplier = 1.0,
    int timerSeconds = 30,
    bool isBoss = false,
  }) {
    final config = LevelDifficultyConfig(
      difficultyTier: 1,
      wordLengthBucket: 1,
      timerSeconds: timerSeconds,
      caurisMultiplier: caurisMultiplier,
      isBoss: isBoss,
    );
    final args = GameArgs(
      devinette: devinette,
      config: config,
      mountainId: isDaily ? null : 'mnt_test',
      levelIndex: isDaily ? null : 1,
      isDailyChallenge: isDaily,
    );
    final c = GameController(
      args,
      audio,
      progress,
      economy,
      const NoopAnalyticsService(),
      tempo,
    );
    controllers.add(c);
    return c;
  }

  /// Indices grille à taper, dans l'ordre, pour former [word]. Robuste aux
  /// doublons via le set `used` (première occurrence libre).
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

  /// Tape le mot lettre par lettre ; [selfIntersecting] est poussé juste avant
  /// la DERNIÈRE lettre (mime le report widget→controller avant le validate
  /// synchrone). La complétion déclenche `validate()` automatiquement.
  void playWord(
    GameController c,
    String word, {
    required bool selfIntersecting,
  }) {
    final idxs = gridIndicesFor(c, word);
    for (var i = 0; i < idxs.length - 1; i++) {
      c.selectTile(idxs[i]);
    }
    c
      ..updateTrailSelfIntersecting(selfIntersecting)
      ..selectTile(idxs.last);
  }

  int expectedBase(GameEconomyConfig eco, int timerSeconds, double mult) =>
      ((eco.winRewardBase + timerSeconds * eco.speedBonusPerSecond) * mult)
          .round();

  group('GameController.validate — octroi du bonus à main levée', () {
    test('tracé propre, ≥4 lettres, non-daily → bonus = freehandBonus(len) '
        'et solde crédité du total', () async {
      const eco = GameEconomyConfig.defaults;
      final c = build(devinette: _devinette('KORA'));

      playWord(c, 'KORA', selfIntersecting: false);
      await Future<void>.delayed(Duration.zero); // flush recordWin async

      final base = expectedBase(eco, 30, 1); // (20 + 30) * 1 = 50
      const freehand = 15; // freehandBonus(4) défauts
      expect(c.state.phase, GamePhase.won);
      expect(c.state.caurisAwarded, base);
      expect(c.state.freehandBonusAwarded, freehand);
      expect(c.state.cauris, newPlayerCauris + base + freehand);
      // recordWin a crédité base + freehand (pas seulement la base).
      expect(progress.state.cauris, newPlayerCauris + base + freehand);
    });

    test('tracé auto-croisé → bonus 0, base seule créditée', () async {
      const eco = GameEconomyConfig.defaults;
      final c = build(devinette: _devinette('KORA'));

      playWord(c, 'KORA', selfIntersecting: true);
      await Future<void>.delayed(Duration.zero);

      final base = expectedBase(eco, 30, 1);
      expect(c.state.phase, GamePhase.won);
      expect(c.state.freehandBonusAwarded, 0);
      expect(c.state.cauris, newPlayerCauris + base);
      expect(progress.state.cauris, newPlayerCauris + base);
    });

    test('mot < seuil (3 lettres) même propre → bonus 0', () async {
      final c = build(devinette: _devinette('FAN'));

      playWord(c, 'FAN', selfIntersecting: false);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.phase, GamePhase.won);
      expect(c.state.freehandBonusAwarded, 0);
    });

    test('valeurs Remote Config respectées (base/perLetter custom)', () async {
      final eco = GameEconomyConfig.defaults.copyWith(
        freehandBonusBase: 10,
        freehandBonusPerLetter: 5,
        freehandMinLength: 4,
      );
      final c = build(devinette: _devinette('KORA'), economy: eco);

      playWord(c, 'KORA', selfIntersecting: false);
      await Future<void>.delayed(Duration.zero);

      // 4 lettres = seuil → forfait de base custom (10), pas de per-letter.
      expect(c.state.freehandBonusAwarded, 10);
    });

    test('mode défi du jour → bonus 0 et recordWin NON appelé', () async {
      final c = build(devinette: _devinette('KORA'), isDaily: true);

      playWord(c, 'KORA', selfIntersecting: false);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.phase, GamePhase.won);
      expect(c.state.caurisAwarded, DailyChallengeService.rewardCauris); // 100
      expect(c.state.freehandBonusAwarded, 0);
      // recordWin sauté en daily → le solde persistant ne bouge pas.
      expect(progress.state.cauris, newPlayerCauris);
    });
  });

  group('GameController — reset du flag currentTrailSelfIntersecting', () {
    test('mauvaise réponse réinitialise le flag à false', () {
      final c = build(devinette: _devinette('KORA'));
      // Forme un mauvais mot (KOAR) avec flag « croisé » actif.
      final idxs = gridIndicesFor(c, 'KOAR');
      for (var i = 0; i < idxs.length - 1; i++) {
        c.selectTile(idxs[i]);
      }
      c
        ..updateTrailSelfIntersecting(true)
        ..selectTile(idxs.last); // complète → validate → mauvaise réponse

      expect(c.state.phase, GamePhase.playing); // reste jouable
      expect(c.state.currentTrailSelfIntersecting, isFalse);
    });

    test('clearSelection réinitialise le flag à false', () {
      final c = build(devinette: _devinette('KORA'))
        ..updateTrailSelfIntersecting(true);
      expect(c.state.currentTrailSelfIntersecting, isTrue);

      c.clearSelection();
      expect(c.state.currentTrailSelfIntersecting, isFalse);
    });
  });
}
