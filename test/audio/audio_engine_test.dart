import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/instruments/balafon.dart';
import 'package:defi_kilimandjaro/audio/instruments/djembe.dart';
import 'package:defi_kilimandjaro/audio/instruments/griot_fanfare.dart';
import 'package:defi_kilimandjaro/audio/instruments/kora.dart';
import 'package:defi_kilimandjaro/audio/instruments/tam_tam.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/audio/wav_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('WavBuffer.normalize peaks at target', () {
      final buf = WavBuffer.silence(0.01)
        ..[0] = 0.2
        ..[1] = -0.1;
      WavBuffer.normalize(buf, target: 0.9);
      expect(buf[0].abs(), closeTo(0.9, 1e-6));
    });
  });

  group('AudioState', () {
    test('defaults: not muted, volume 0.8', () {
      final s = AudioState.defaults();
      expect(s.muted, isFalse);
      expect(s.volume, 0.8);
    });

    test('copyWith preserves untouched fields', () {
      final s = AudioState.defaults().copyWith(muted: true);
      expect(s.muted, isTrue);
      expect(s.volume, 0.8);
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
