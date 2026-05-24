import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/instruments/balafon.dart';
import 'package:defi_kilimandjaro/audio/instruments/kora.dart';
import 'package:defi_kilimandjaro/audio/instruments/tam_tam.dart';
import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Fanfare BOSS — variante dramatique de la fanfare victoire standard.
///
/// Joue à la victoire d'un boss (dernier niveau d'une montagne). Plus
/// solennelle que `GriotFanfare.render()` :
///
/// 1. **Intro djembé grave** (~0.45 s) : 2 frappes désaccordées 160/135 Hz
///    avec 180 ms d'écart pour annoncer l'événement.
/// 2. **Fanfare griot complète** déclenchée après 500 ms (balafon ascending
///    + kora arpégé + tam-tam cascade). Voicing plus chaud (gains +5–10%).
/// 3. **Queue tam-tam** en finale (~0.4 s) pour signer la résonance.
///
/// Durée totale ~2.8 s vs ~2 s pour la fanfare standard.
class BossFanfare {
  BossFanfare._();

  /// Rendu mixé final, prêt à charger via `flutter_soloud.loadMem`.
  static Uint8List render() {
    const total = 2.8;
    final out = WavBuffer.silence(total);
    const sr = WavBuffer.sampleRate;

    // 1. Intro djembé grave.
    final hit1 = _djembeBassHit(160);
    final hit2 = _djembeBassHit(135);
    WavBuffer.mixInto(out, hit1, gain: 0.95);
    WavBuffer.mixInto(
      out,
      hit2,
      offset: (0.18 * sr).round(),
      gain: 0.9,
    );

    // 2. Fanfare griot après 500 ms.
    final fanfareOffset = (0.50 * sr).round();
    final balafon = Balafon.renderVictoryRun();
    final kora = Kora.renderVictoryCounterpoint();
    final tam = TamTam.renderVictoryCascade();
    WavBuffer.mixInto(out, balafon, offset: fanfareOffset, gain: 0.95);
    WavBuffer.mixInto(
      out,
      kora,
      offset: fanfareOffset + (0.12 * sr).round(),
      gain: 0.6,
    );
    WavBuffer.mixInto(
      out,
      tam,
      offset: fanfareOffset + (0.40 * sr).round(),
      gain: 0.7,
    );

    // 3. Queue tam-tam grave en signature finale.
    final tamTail = TamTam.renderSlowDouble();
    WavBuffer.mixInto(
      out,
      tamTail,
      offset: (2.30 * sr).round(),
      gain: 0.7,
    );

    WavBuffer.normalize(out, target: 0.92);
    return WavBuffer.encodeMono16(out);
  }

  /// Frappe djembé grave isolée. Réimplémente la logique de
  /// `Djembe._hit` (privée, non exportée) avec une fréquence plus basse
  /// et une queue résonance plus longue — bien plus présente que la
  /// frappe "wrong answer" qui est volontairement sèche.
  static Float32List _djembeBassHit(double bodyFreq) {
    const duration = 0.45;
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    final rng = math.Random(bodyFreq.toInt());
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      // Transient bruité court (~12 ms decay) pour la peau.
      final transient =
          (rng.nextDouble() * 2 - 1) * math.exp(-t / 0.012);
      // Corps oscillant amorti — résonance plus longue pour grosse caisse.
      final body = math.sin(twoPi * bodyFreq * t) * math.exp(-t / 0.20);
      // Sub-harmonique (basse profonde).
      final sub = math.sin(twoPi * (bodyFreq * 0.5) * t) *
          math.exp(-t / 0.28) *
          0.5;
      out[i] = transient * 0.6 + body * 0.8 + sub;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.002,
      sustainLevel: 0.6,
      release: duration - 0.052,
    );
    return out;
  }
}
