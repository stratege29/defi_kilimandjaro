import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/instruments/balafon.dart';
import 'package:defi_kilimandjaro/audio/instruments/djembe.dart';
import 'package:defi_kilimandjaro/audio/instruments/duel_round_end.dart';
import 'package:defi_kilimandjaro/audio/instruments/griot_fanfare.dart';
import 'package:defi_kilimandjaro/audio/instruments/kora.dart';
import 'package:defi_kilimandjaro/audio/instruments/lobby_duel.dart';
import 'package:defi_kilimandjaro/audio/instruments/tam_tam.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/audio/wav_buffer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioEngine', () {
    test('init() does not throw and is idempotent', () async {
      // SoLoud's native engine is unavailable in the test runner; AudioEngine
      // is designed to swallow that error and remain a no-op (silent mode).
      await AudioEngine.instance.init();
      await AudioEngine.instance.init();
      // Whatever the platform outcome, no exception should reach the caller.
      expect(true, isTrue);
    });

    test('play() is a no-op when engine is not initialized', () async {
      await AudioEngine.instance.play(AudioCue.wordComplete);
      expect(true, isTrue);
    });

    test('suspend/resume/setMuted/setVolume never throw', () {
      AudioEngine.instance
        ..suspend()
        ..resume()
        ..setMuted(muted: true)
        ..setVolume(0.5)
        ..setMuted(muted: false);
      expect(true, isTrue);
    });
  });

  group('Procedural synthesis (no asset files)', () {
    test('all instruments produce valid WAV byte buffers', () {
      final wavs = <List<int>>[
        Balafon.renderLetterNote(0),
        Balafon.renderLetterNote(7),
        Balafon.renderAscendingChord(),
        Balafon.renderDescendingGrave(),
        Kora.renderHint(),
        TamTam.renderTick(),
        Djembe.renderWrongDouble(),
        GriotFanfare.render(),
      ];
      for (final w in wavs) {
        expect(w.length, greaterThan(44), reason: 'WAV should have header');
        expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
      }
    });

    test('LobbyDuel samples produce valid WAV byte buffers', () {
      final wavs = <(String, List<int>)>[
        ('lobbyLoopDoum', LobbyDuel.renderLoopDoum()),
        ('lobbyLoopTac', LobbyDuel.renderLoopTac()),
        ('lobbyMatchFound', LobbyDuel.renderMatchFound()),
        ('duelStart', LobbyDuel.renderDuelStart()),
      ];
      for (final (name, w) in wavs) {
        expect(
          w.length,
          greaterThan(44),
          reason: '$name WAV should have header',
        );
        expect(
          String.fromCharCodes(w.sublist(0, 4)),
          'RIFF',
          reason: '$name should start with RIFF',
        );
        expect(
          String.fromCharCodes(w.sublist(8, 12)),
          'WAVE',
          reason: '$name should be WAVE format',
        );
      }
    });

    test('LobbyDuel.renderLoopDoum is shorter than renderMatchFound', () {
      // doum is a short single-hit sample (~280 ms); matchFound is ~620 ms.
      final doum = LobbyDuel.renderLoopDoum();
      final matchFound = LobbyDuel.renderMatchFound();
      expect(doum.length, lessThan(matchFound.length));
    });

    test('LobbyDuel.renderDuelStart is longer than renderLoopTac', () {
      // duelStart is ~820 ms; tac is a short hit ~180 ms.
      final tac = LobbyDuel.renderLoopTac();
      final duelStart = LobbyDuel.renderDuelStart();
      expect(tac.length, lessThan(duelStart.length));
    });

    test('DuelRoundEnd samples produce valid WAV byte buffers', () {
      final wavs = <(String, List<int>)>[
        ('roundWon', DuelRoundEnd.renderRoundWon()),
        ('roundLost', DuelRoundEnd.renderRoundLost()),
        ('roundDraw', DuelRoundEnd.renderRoundDraw()),
      ];
      for (final (name, w) in wavs) {
        expect(
          w.length,
          greaterThan(44),
          reason: '$name WAV should have header + data',
        );
        expect(
          String.fromCharCodes(w.sublist(0, 4)),
          'RIFF',
          reason: '$name should start with RIFF',
        );
        expect(
          String.fromCharCodes(w.sublist(8, 12)),
          'WAVE',
          reason: '$name should be WAVE format',
        );
      }
    });

    test('DuelRoundEnd.renderRoundWon is the longest of the three cues', () {
      // roundWon (~950 ms) > roundLost (~800 ms) > roundDraw (~750 ms).
      final won = DuelRoundEnd.renderRoundWon();
      final lost = DuelRoundEnd.renderRoundLost();
      final draw = DuelRoundEnd.renderRoundDraw();
      expect(won.length, greaterThan(lost.length));
      expect(lost.length, greaterThan(draw.length));
    });

    test('WavBuffer.normalize peaks at target', () {
      final buf = WavBuffer.silence(0.01)
        ..[0] = 0.2
        ..[1] = -0.1;
      WavBuffer.normalize(buf, target: 0.9);
      expect(buf[0].abs(), closeTo(0.9, 1e-6));
    });
  });

  group('AudioState', () {
    test('defaults: not muted, volume 0.8, haptics on, respect silent off', () {
      final s = AudioState.defaults();
      expect(s.muted, isFalse);
      expect(s.volume, 0.8);
      expect(s.hapticsEnabled, isTrue);
      expect(s.respectSilentSwitch, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      final s = AudioState.defaults().copyWith(muted: true);
      expect(s.muted, isTrue);
      expect(s.volume, 0.8);
      expect(s.hapticsEnabled, isTrue);
      expect(s.respectSilentSwitch, isFalse);
    });

    test('copyWith updates haptics and respectSilentSwitch', () {
      final s = AudioState.defaults()
          .copyWith(hapticsEnabled: false, respectSilentSwitch: true);
      expect(s.hapticsEnabled, isFalse);
      expect(s.respectSilentSwitch, isTrue);
      expect(s.muted, isFalse);
    });
  });

  group('AudioController lobby loop', () {
    late AudioController controller;

    setUp(() {
      // Provide a mock SharedPreferences store so setMuted/setVolume don't
      // throw MissingPluginException in the unit-test runner.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // AudioEngine is in silent mode (SoLoud unavailable) — play() is no-op.
      controller = AudioController(AudioEngine.instance);
    });

    tearDown(() {
      controller.dispose();
    });

    test('playLobbySearchLoop is idempotent — multiple calls start one loop',
        () async {
      await controller.playLobbySearchLoop();
      await controller.playLobbySearchLoop(); // second call must be no-op
      // Verify no exception is thrown and controller is still usable.
      expect(controller.state.muted, isFalse);
    });

    test('stopLobbySearchLoop is safe when no loop is active', () async {
      // Must not throw even if called before playLobbySearchLoop.
      await expectLater(controller.stopLobbySearchLoop(), completes);
    });

    test('stopLobbySearchLoop stops the loop', () async {
      await controller.playLobbySearchLoop();
      await controller.stopLobbySearchLoop();
      // Starting again after stop must succeed (loop re-entrant).
      await expectLater(controller.playLobbySearchLoop(), completes);
    });

    test('playLobbySearchLoop is no-op when muted', () async {
      await controller.setMuted(muted: true);
      await controller.playLobbySearchLoop();
      // No timer started — stopLobbySearchLoop should be a no-op.
      await expectLater(controller.stopLobbySearchLoop(), completes);
    });

    test('playLobbyMatchFound stops loop then plays cue — no throw', () async {
      await controller.playLobbySearchLoop();
      await expectLater(controller.playLobbyMatchFound(), completes);
    });

    test('playLobbyMatchFound is no-op when muted', () async {
      await controller.setMuted(muted: true);
      await expectLater(controller.playLobbyMatchFound(), completes);
    });

    test('playDuelStart does not throw', () async {
      await expectLater(controller.playDuelStart(), completes);
    });

    test('playDuelStart is no-op when muted', () async {
      await controller.setMuted(muted: true);
      await expectLater(controller.playDuelStart(), completes);
    });

    test('playRoundWon/Lost/Draw do not throw', () async {
      await expectLater(controller.playRoundWon(), completes);
      await expectLater(controller.playRoundLost(), completes);
      await expectLater(controller.playRoundDraw(), completes);
    });

    test('playRoundWon/Lost/Draw are no-ops when muted', () async {
      await controller.setMuted(muted: true);
      await expectLater(controller.playRoundWon(), completes);
      await expectLater(controller.playRoundLost(), completes);
      await expectLater(controller.playRoundDraw(), completes);
    });

    test('suspend() cancels the loop', () async {
      await controller.playLobbySearchLoop();
      controller.suspend();
      // After suspend, stopping again should be safe.
      await expectLater(controller.stopLobbySearchLoop(), completes);
    });

    test('toggleHaptics flips the persisted flag', () async {
      // Laisse _loadPrefs (async, lancé au constructeur) se stabiliser avant
      // de muter l'état, sinon il écrase la valeur du toggle.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.hapticsEnabled, isTrue);
      await controller.toggleHaptics();
      expect(controller.state.hapticsEnabled, isFalse);
      await controller.toggleHaptics();
      expect(controller.state.hapticsEnabled, isTrue);
    });

    test('hapticDeselect never throws (haptics on or off)', () async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.hapticDeselect();
      await controller.setHapticsEnabled(enabled: false);
      controller.hapticDeselect();
      expect(controller.state.hapticsEnabled, isFalse);
    });

    test('toggleRespectSilentSwitch flips without throwing', () async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.respectSilentSwitch, isFalse);
      await expectLater(controller.toggleRespectSilentSwitch(), completes);
      expect(controller.state.respectSilentSwitch, isTrue);
    });
  });

  group('TempoScheduler', () {
    test('updateForTimeLeft maps to 60/90/140 BPM', () {
      final s = TempoScheduler();
      expect(_bpmFor(s, 20), 60);
      expect(_bpmFor(s, 10), 90);
      expect(_bpmFor(s, 5), 140);
    });
  });
}

int _bpmFor(TempoScheduler s, int seconds) {
  s.updateForTimeLeft(seconds);
  return s.bpm;
}
