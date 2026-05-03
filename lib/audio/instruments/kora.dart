import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Kora (harpe-luth mandingue) — Karplus-Strong plucked string.
///
/// Spec maquette p.12 :
/// - 2 notes douces descendantes (A4, F#4)
/// - Vibrato 4.2 Hz, profondeur ~0.5%
/// - Decay total ~1.8 s
class Kora {
  Kora._();

  /// 2 notes descendantes pour `playHintUsed` — 220ms d'écart.
  static Uint8List renderHint() {
    const total = 1.8;
    const spacing = 0.22;
    final out = WavBuffer.silence(total);
    final n1 = _pluck(440, 1.6);
    final n2 = _pluck(369.99, 1.6); // F#4
    WavBuffer.mixInto(out, n1, gain: 0.7);
    WavBuffer.mixInto(
      out,
      n2,
      offset: (spacing * WavBuffer.sampleRate).round(),
      gain: 0.6,
    );
    WavBuffer.normalize(out, target: 0.7);
    return WavBuffer.encodeMono16(out);
  }

  /// Contrepoint kora pour la fanfare de victoire — arpège A4/E5/A5.
  static Float32List renderVictoryCounterpoint() {
    const total = 1.6;
    final out = WavBuffer.silence(total);
    const notes = <double>[440, 659.25, 880];
    const spacing = 0.18;
    for (var i = 0; i < notes.length; i++) {
      final p = _pluck(notes[i], 1.2);
      final off = (i * spacing * WavBuffer.sampleRate).round();
      WavBuffer.mixInto(out, p, offset: off, gain: 0.45);
    }
    return out;
  }

  /// Karplus-Strong avec vibrato — restitue un timbre cordé doux.
  static Float32List _pluck(double freq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final delayLen = (sr / freq).round().clamp(2, sr);
    final rng = math.Random(freq.toInt());
    // Buffer de retard initialisé avec du bruit blanc.
    final delay = Float32List(delayLen);
    for (var i = 0; i < delayLen; i++) {
      delay[i] = rng.nextDouble() * 2 - 1;
    }
    final out = Float32List(n);
    var idx = 0;
    const damping = 0.996;
    const vibratoHz = 4.2;
    const vibratoDepth = 0.005;
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final vib = 1.0 + vibratoDepth * math.sin(twoPi * vibratoHz * t);
      // Filtre passe-bas (moyenne 2 échantillons) + damping.
      final next = (delay[idx] + delay[(idx + 1) % delayLen]) * 0.5 * damping;
      out[i] = delay[idx] * vib * 0.6;
      delay[idx] = next;
      idx = (idx + 1) % delayLen;
    }
    // Release lent (decay total ~1.8s).
    WavBuffer.applyAdsr(
      out,
      attack: 0.002,
      sustainLevel: 0.85,
      release: duration * 0.9,
    );
    return out;
  }
}
