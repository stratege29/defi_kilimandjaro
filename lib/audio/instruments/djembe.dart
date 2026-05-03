import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Djembé — frappe = transient bruité court + résonance corps.
///
/// Spec maquette p.12 :
/// - 2 frappes désaccordées (220 Hz / 195 Hz), 120 ms d'écart
/// - Utilisé pour `playWrongAnswer`
class Djembe {
  Djembe._();

  /// 2 frappes désaccordées, 120 ms d'écart.
  static Uint8List renderWrongDouble() {
    const total = 0.55;
    final out = WavBuffer.silence(total);
    final hit1 = _hit(220);
    final hit2 = _hit(195);
    WavBuffer.mixInto(out, hit1, gain: 0.85);
    WavBuffer.mixInto(
      out,
      hit2,
      offset: (0.12 * WavBuffer.sampleRate).round(),
      gain: 0.8,
    );
    WavBuffer.normalize(out, target: 0.85);
    return WavBuffer.encodeMono16(out);
  }

  /// Frappe unique : transient bruité (peau) + corps tonal.
  static Float32List _hit(double bodyFreq) {
    const duration = 0.28;
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    final rng = math.Random(bodyFreq.toInt());
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      // Transient (clap court) — bruit en exp decay 8 ms.
      final transient = (rng.nextDouble() * 2 - 1) * math.exp(-t / 0.008);
      // Corps : oscillation amortie.
      final body = math.sin(twoPi * bodyFreq * t) * math.exp(-t / 0.12);
      // Sub-harmonique (slap grave).
      final sub = math.sin(twoPi * (bodyFreq * 0.5) * t) *
          math.exp(-t / 0.18) *
          0.4;
      out[i] = transient * 0.55 + body * 0.7 + sub;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.001,
      decay: 0.04,
      sustainLevel: 0.6,
      release: duration - 0.041 > 0 ? duration - 0.041 : 0.05,
    );
    return out;
  }
}
