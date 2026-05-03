import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Balafon (xylophone ouest-africain) — additive synthesis pentatonique.
///
/// Spec maquette p.12 :
/// - Pentatonique majeure C : C4 D4 E4 G4 A4 (262, 294, 330, 392, 440 Hz)
/// - Caisse de résonance : 3 partiels (1.0, 2.76, 5.4) tempérés par caisse
/// - Light vibrato (~5 Hz, profondeur 0.4%)
class Balafon {
  Balafon._();

  /// Pentatonique majeure C (Hz) — utilisée par sélection lettre + chord.
  static const List<double> pentatonicC = <double>[
    261.63, // C4
    293.66, // D4
    329.63, // E4
    391.99, // G4
    440, // A4
  ];

  /// Une note isolée — utilisée pour `playLetterSelect`.
  static Uint8List renderNote(double frequencyHz, {double duration = 0.55}) {
    final buf = _renderNote(frequencyHz, duration);
    WavBuffer.normalize(buf, target: 0.85);
    return WavBuffer.encodeMono16(buf);
  }

  /// Note ascendante choisie selon l'index de la lettre (mod taille gamme).
  static Uint8List renderLetterNote(int letterIdx) {
    final freq = pentatonicC[letterIdx % pentatonicC.length] *
        // octave +1 toutes les 5 lettres
        math.pow(2, (letterIdx ~/ pentatonicC.length).clamp(0, 1)).toDouble();
    return renderNote(freq);
  }

  /// Accord ascendant — 5 notes pentatoniques séparées de 70 ms (maquette p.12).
  static Uint8List renderAscendingChord({double spacingMs = 70}) {
    const totalSeconds = 1.6;
    final out = WavBuffer.silence(totalSeconds);
    final spacingSamples = (spacingMs / 1000.0 * WavBuffer.sampleRate).round();
    for (var i = 0; i < pentatonicC.length; i++) {
      final note = _renderNote(pentatonicC[i], 1);
      WavBuffer.mixInto(out, note, offset: spacingSamples * i, gain: 0.55);
    }
    WavBuffer.normalize(out);
    return WavBuffer.encodeMono16(out);
  }

  /// 4 notes graves descendantes — utilisé pour `playFailure`.
  static Uint8List renderDescendingGrave() {
    final out = renderDescendingGraveBuffer();
    WavBuffer.normalize(out);
    return WavBuffer.encodeMono16(out);
  }

  /// Variante Float32 (sans normalize/encode) pour mixage externe.
  static Float32List renderDescendingGraveBuffer() {
    const freqs = <double>[220, 196, 174.61, 146.83]; // A3, G3, F3, D3
    const totalSeconds = 1.8;
    const spacing = 0.32;
    final out = WavBuffer.silence(totalSeconds);
    for (var i = 0; i < freqs.length; i++) {
      final note = _renderNote(freqs[i], 0.55);
      final off = (i * spacing * WavBuffer.sampleRate).round();
      WavBuffer.mixInto(out, note, offset: off, gain: 0.7);
    }
    return out;
  }

  /// 7 notes ascendantes — fanfare victoire (utilisé par GriotFanfare).
  static Float32List renderVictoryRun() {
    const scale = <double>[
      261.63, 293.66, 329.63, 391.99, 440, 523.25, 587.33,
    ];
    const total = 1.6;
    const spacing = 0.11;
    final out = WavBuffer.silence(total);
    for (var i = 0; i < scale.length; i++) {
      final note = _renderNote(scale[i], 0.5);
      final off = (i * spacing * WavBuffer.sampleRate).round();
      WavBuffer.mixInto(out, note, offset: off, gain: 0.65);
    }
    return out;
  }

  /// Génère le buffer brut Float32 d'une note (sans normalize ni encode).
  static Float32List _renderNote(double freq, double duration) {
    final n = (duration * WavBuffer.sampleRate).round();
    final out = Float32List(n);
    // Partiels balafon (rapports approximatifs d'une lame de bois résonante).
    const partials = <double>[1, 2.76, 5.4];
    const partialAmps = <double>[1, 0.45, 0.18];
    // Vibrato léger.
    const vibratoHz = 5.0;
    const vibratoDepth = 0.004;
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / WavBuffer.sampleRate;
      final vib = 1.0 + vibratoDepth * math.sin(twoPi * vibratoHz * t);
      var s = 0.0;
      for (var p = 0; p < partials.length; p++) {
        // Amortissement plus rapide pour les harmoniques aigus.
        final partialDecay = math.exp(-3.5 * partials[p] * t);
        s += partialAmps[p] *
            partialDecay *
            math.sin(twoPi * freq * partials[p] * vib * t);
      }
      out[i] = s * 0.55;
    }
    // Caisse de résonance : enveloppe percussive courte.
    WavBuffer.applyAdsr(
      out,
      attack: 0.003,
      decay: 0.08,
      sustainLevel: 0.35,
      release: duration - 0.083 > 0 ? duration - 0.083 : 0.05,
    );
    return out;
  }
}
