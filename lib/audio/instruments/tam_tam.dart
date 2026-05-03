import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Tam-tam — sweep de membrane + enveloppe percussive.
///
/// Spec maquette p.12 :
/// - Sweep 160→60 Hz sur 0.35 s pour `playTimerTick`
/// - Cascade pour `playVictory`, frappes lentes pour `playFailure`
class TamTam {
  TamTam._();

  /// Tick timer (sweep 160→60 Hz, 0.35 s).
  static Uint8List renderTick() {
    final buf = _renderSweep(160, 60, 0.35);
    WavBuffer.normalize(buf, target: 0.75);
    return WavBuffer.encodeMono16(buf);
  }

  /// Cascade de victoire : 3 frappes graves descendantes.
  static Float32List renderVictoryCascade() {
    const total = 1.6;
    final out = WavBuffer.silence(total);
    final freqs = <(double, double)>[(180, 80), (140, 60), (110, 50)];
    const spacing = 0.18;
    for (var i = 0; i < freqs.length; i++) {
      final s = _renderSweep(freqs[i].$1, freqs[i].$2, 0.45);
      final off = (i * spacing * WavBuffer.sampleRate).round();
      WavBuffer.mixInto(out, s, offset: off, gain: 0.55);
    }
    return out;
  }

  /// Frappe lente x2 utilisée par `playFailure` (en plus du balafon descendant).
  static Float32List renderSlowDouble() {
    const total = 1.8;
    final out = WavBuffer.silence(total);
    final s1 = _renderSweep(120, 50, 0.55);
    final s2 = _renderSweep(100, 45, 0.55);
    WavBuffer.mixInto(out, s1, gain: 0.55);
    WavBuffer.mixInto(
      out,
      s2,
      offset: (0.7 * WavBuffer.sampleRate).round(),
      gain: 0.5,
    );
    return out;
  }

  /// Sweep de fréquence avec enveloppe percussive (membrane).
  static Float32List _renderSweep(double f0, double f1, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    const twoPi = 2 * math.pi;
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final r = i / n;
      final f = f0 + (f1 - f0) * r;
      phase += twoPi * f / sr;
      // Mélange sinus + bruit filtré pour l'aspect membrane.
      final noise = (math.sin(phase * 1.7) + math.sin(phase * 2.3)) * 0.15;
      out[i] = math.sin(phase) * 0.85 + noise;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.004,
      decay: 0.08,
      sustainLevel: 0.5,
      release: duration - 0.084 > 0 ? duration - 0.084 : 0.05,
    );
    return out;
  }
}
