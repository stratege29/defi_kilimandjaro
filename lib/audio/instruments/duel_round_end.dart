import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Sons procéduraux de fin de manche du duel 3-manches.
///
/// Design sonore (cf. identité projet, maquette p.12) :
/// - Round won  : arpège kora ascendant C major (C4-E4-G4-C5) + roulement
///                djembé crescendo final — joyeux, valorisant (~900 ms).
/// - Round lost : note balafon grave descendante (D3→A2) + "ride" — courte
///                texture aiguë bruitée évoquant une cymbale ride (~780 ms).
/// - Round draw : accord kora suspendu (C4-F4-G4, pas de tierce) — tension
///                non résolue, sensation neutre/en attente (~720 ms).
///
/// Aucun fichier audio bundle — tout est synthétisé via [WavBuffer].
class DuelRoundEnd {
  DuelRoundEnd._();

  // ─── Round won ───────────────────────────────────────────────────────────

  /// Accord majeur kora ascendant + roulement djembé crescendo.
  static Uint8List renderRoundWon() {
    const total = 0.95;
    final out = WavBuffer.silence(total);

    // Arpège kora C major : C4 - E4 - G4 - C5, espacés de 100 ms.
    const notes = <double>[
      261.63, // C4
      329.63, // E4
      391.99, // G4 (utilisé ici comme 5e juste, sonne brillant)
      523.25, // C5
    ];
    const spacing = 0.10;
    for (var i = 0; i < notes.length; i++) {
      final pluck = _koraPluck(notes[i], 0.80);
      final off = (i * spacing * WavBuffer.sampleRate).round();
      // Gain croissant léger pour souligner la montée.
      final gain = 0.55 + i * 0.06;
      WavBuffer.mixInto(out, pluck, offset: off, gain: gain);
    }

    // Roulement djembé final : 3 frappes rapides crescendo à partir de 520 ms.
    const rollFreqs = <double>[230, 250, 275];
    const rollSpacing = 0.06;
    const rollStart = 0.52;
    for (var i = 0; i < rollFreqs.length; i++) {
      final hit = _djembeHit(rollFreqs[i], 0.20);
      final off =
          ((rollStart + i * rollSpacing) * WavBuffer.sampleRate).round();
      final gain = 0.50 + i * 0.12;
      WavBuffer.mixInto(out, hit, offset: off, gain: gain);
    }

    WavBuffer.normalize(out, target: 0.90);
    return WavBuffer.encodeMono16(out);
  }

  // ─── Round lost ──────────────────────────────────────────────────────────

  /// Note grave balafon descendante + courte texture ride aiguë.
  static Uint8List renderRoundLost() {
    const total = 0.80;
    final out = WavBuffer.silence(total);

    // Balafon D3 (~146.83 Hz) — note grave, attaque immédiate.
    final low1 = _balafonGrave(146.83, 0.55);
    WavBuffer.mixInto(out, low1, gain: 0.78);

    // Descente sur A2 (~110 Hz) 220 ms après — accentue le côté "tombé".
    final low2 = _balafonGrave(110, 0.50);
    WavBuffer.mixInto(
      out,
      low2,
      offset: (0.22 * WavBuffer.sampleRate).round(),
      gain: 0.62,
    );

    // "Ride" : bande de bruit haute fréquence (3-5 kHz) avec decay court.
    // Pas de vrai sample cymbale — on évoque la texture brillante via du
    // bruit filtré + decay percussif, attaque légèrement décalée (60 ms).
    final ride = _rideBurst(0.32);
    WavBuffer.mixInto(
      out,
      ride,
      offset: (0.06 * WavBuffer.sampleRate).round(),
      gain: 0.38,
    );

    WavBuffer.normalize(out, target: 0.85);
    return WavBuffer.encodeMono16(out);
  }

  // ─── Round draw ──────────────────────────────────────────────────────────

  /// Accord kora suspendu (sans tierce) — sensation neutre en attente.
  static Uint8List renderRoundDraw() {
    const total = 0.75;
    final out = WavBuffer.silence(total);

    // C4 - F4 - G4 : suspended chord (quarte + quinte), pas de tierce →
    // ni majeur ni mineur → suspension harmonique, parfait pour "match nul".
    const notes = <double>[
      261.63, // C4
      349.23, // F4
      391.99, // G4
    ];
    // Attaque simultanée (à 10 ms près pour éviter une phase parfaite).
    const microSpacing = 0.01;
    for (var i = 0; i < notes.length; i++) {
      final pluck = _koraPluck(notes[i], 0.70);
      final off = (i * microSpacing * WavBuffer.sampleRate).round();
      WavBuffer.mixInto(out, pluck, offset: off, gain: 0.55);
    }

    WavBuffer.normalize(out, target: 0.78);
    return WavBuffer.encodeMono16(out);
  }

  // ─── Générateurs privés ──────────────────────────────────────────────────

  /// Karplus-Strong kora doux — variante locale (timbre cordé pincé).
  static Float32List _koraPluck(double freq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final delayLen = (sr / freq).round().clamp(2, sr);
    final rng = math.Random(freq.toInt() + 23);
    final delay = Float32List(delayLen);
    for (var i = 0; i < delayLen; i++) {
      delay[i] = rng.nextDouble() * 2 - 1;
    }
    final out = Float32List(n);
    var idx = 0;
    const damping = 0.9965;
    const vibratoHz = 4.5;
    const vibratoDepth = 0.005;
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final vib = 1.0 + vibratoDepth * math.sin(twoPi * vibratoHz * t);
      final next = (delay[idx] + delay[(idx + 1) % delayLen]) * 0.5 * damping;
      out[i] = delay[idx] * vib * 0.6;
      delay[idx] = next;
      idx = (idx + 1) % delayLen;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.002,
      sustainLevel: 0.85,
      release: duration * 0.85,
    );
    return out;
  }

  /// Frappe djembé locale — transient bruité + corps tonal court.
  static Float32List _djembeHit(double bodyFreq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    final rng = math.Random(bodyFreq.toInt() + 53);
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final transient = (rng.nextDouble() * 2 - 1) * math.exp(-t / 0.008);
      final body = math.sin(twoPi * bodyFreq * t) * math.exp(-t / 0.10);
      final sub =
          math.sin(twoPi * (bodyFreq * 0.5) * t) * math.exp(-t / 0.15) * 0.35;
      out[i] = transient * 0.55 + body * 0.70 + sub;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.001,
      decay: 0.04,
      sustainLevel: 0.55,
      release: duration - 0.041 > 0 ? duration - 0.041 : 0.04,
    );
    return out;
  }

  /// Note balafon grave avec partiels bois — sustain modéré.
  static Float32List _balafonGrave(double freq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    const partials = <double>[1, 2.76, 5.4];
    const partialAmps = <double>[1, 0.40, 0.16];
    const vibratoHz = 4.8;
    const vibratoDepth = 0.0035;
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final vib = 1.0 + vibratoDepth * math.sin(twoPi * vibratoHz * t);
      var s = 0.0;
      for (var p = 0; p < partials.length; p++) {
        // Decay plus lent que le balafon standard (registre grave → caisse
        // résonante plus longue).
        final d = math.exp(-2.8 * partials[p] * t);
        s += partialAmps[p] * d * math.sin(twoPi * freq * partials[p] * vib * t);
      }
      out[i] = s * 0.55;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.004,
      decay: 0.08,
      sustainLevel: 0.32,
      release: duration - 0.085 > 0 ? duration - 0.085 : 0.04,
    );
    return out;
  }

  /// Burst de bruit haute fréquence évoquant une cymbale ride.
  ///
  /// Pas d'instrument cymbale dans le projet — on s'appuie sur du bruit
  /// blanc filtré (passe-haut grossier via dérivée première) avec decay
  /// exponentiel court. Suffisant pour la texture "tssh" courte voulue.
  static Float32List _rideBurst(double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    final rng = math.Random(91);
    var prev = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final noise = rng.nextDouble() * 2 - 1;
      // Différence finie ≈ passe-haut 1er ordre → accentue les aigus.
      final hp = noise - prev;
      prev = noise;
      // Decay exponentiel rapide (τ = 80 ms) pour le côté percussif.
      out[i] = hp * math.exp(-t / 0.08);
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.001,
      decay: 0.03,
      sustainLevel: 0.40,
      release: duration - 0.031 > 0 ? duration - 0.031 : 0.03,
    );
    return out;
  }
}
