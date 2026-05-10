import 'dart:math' as math;
import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Sons procéduraux spécifiques au lobby et à l'écran de duel.
///
/// Design sonore (cf. spec PR-2) :
/// - Lobby loop  : tam-tam doum grave 80 Hz + tac djembé 320 Hz — pattern 8/8
///   à 108 BPM. Rendu en deux samples séparés (doum / tac) pour que
///   `AudioController` puisse les ordonnancer en Timer.periodic.
/// - Match found : ding! balafon G5→C6 + roulement djembé crescendo (~600 ms).
/// - Duel start  : kora fortissimo C3 grave + frappe tam-tam très grave (~800ms).
class LobbyDuel {
  LobbyDuel._();

  // ─── Lobby loop : deux samples indépendants ──────────────────────────────

  /// Frappe "DOUM" grave — corps 80 Hz, sub 40 Hz, transient bruité.
  /// Volume fort (accent sur le 1).
  static Uint8List renderLoopDoum() {
    final buf = _doum(80, 0.28);
    WavBuffer.normalize(buf, target: 0.88);
    return WavBuffer.encodeMono16(buf);
  }

  /// Frappe "tac" aigu — corps 320 Hz, transient court.
  /// Volume modéré (temps faibles).
  static Uint8List renderLoopTac() {
    final buf = _tac(320, 0.18);
    WavBuffer.normalize(buf, target: 0.62);
    return WavBuffer.encodeMono16(buf);
  }

  // ─── Match found ─────────────────────────────────────────────────────────

  /// Ding! balafon G5 (784 Hz) → C6 (1047 Hz) + roulement djembé crescendo.
  /// Durée totale ~620 ms.
  static Uint8List renderMatchFound() {
    const total = 0.65;
    final out = WavBuffer.silence(total);

    // Balafon G5 — attaque immédiate
    final g5 = _balafonNote(783.99, 0.25);
    WavBuffer.mixInto(out, g5, gain: 0.70);

    // Balafon C6 — 80 ms après
    final c6 = _balafonNote(1046.50, 0.25);
    WavBuffer.mixInto(
      out,
      c6,
      offset: (0.08 * WavBuffer.sampleRate).round(),
      gain: 0.75,
    );

    // Roulement djembé : 4 frappes rapides 300→320→340→360 Hz crescendo.
    const roulFreqs = <double>[300, 315, 335, 360];
    const roulSpacing = 0.07; // 70 ms entre chaque frappe
    const roulStart = 0.22; // démarre 220 ms après le G5
    for (var i = 0; i < roulFreqs.length; i++) {
      final hit = _tac(roulFreqs[i], 0.14);
      final off =
          ((roulStart + i * roulSpacing) * WavBuffer.sampleRate).round();
      // Gain croissant (0.45 → 0.80) pour le crescendo.
      final gain = 0.45 + i * 0.117;
      WavBuffer.mixInto(out, hit, offset: off, gain: gain);
    }

    // Coup sec final djembé fort à ~600 ms.
    final finalHit = _doum(200, 0.12);
    WavBuffer.mixInto(
      out,
      finalHit,
      offset: (0.52 * WavBuffer.sampleRate).round(),
      gain: 0.85,
    );

    WavBuffer.normalize(out, target: 0.88);
    return WavBuffer.encodeMono16(out);
  }

  // ─── Duel start ──────────────────────────────────────────────────────────

  /// Gong cérémoniel : kora fortissimo C3 (130.81 Hz) long sustain
  /// + frappe tam-tam très grave (100→45 Hz) en début.
  /// Durée totale ~820 ms.
  static Uint8List renderDuelStart() {
    const total = 0.85;
    final out = WavBuffer.silence(total);

    // Frappe tam-tam très grave en ouverture.
    final tamStrike = _graveSweep(120, 42, 0.50);
    WavBuffer.mixInto(out, tamStrike, gain: 0.72);

    // Kora C3 fortissimo, long sustain avec vibrato.
    final koraC3 = _koraFortissimo(130.81, 0.78);
    WavBuffer.mixInto(
      out,
      koraC3,
      offset: (0.04 * WavBuffer.sampleRate).round(),
      gain: 0.90,
    );

    // Deuxième partiel kora G3 (quinte) plus doux — texture harmonique.
    final koraG3 = _koraFortissimo(196, 0.65);
    WavBuffer.mixInto(
      out,
      koraG3,
      offset: (0.08 * WavBuffer.sampleRate).round(),
      gain: 0.42,
    );

    WavBuffer.normalize(out, target: 0.92);
    return WavBuffer.encodeMono16(out);
  }

  // ─── Générateurs privés ──────────────────────────────────────────────────

  /// Frappe grave djembé type "doum" — corps large, sub profond.
  static Float32List _doum(double bodyFreq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    final rng = math.Random(bodyFreq.toInt() + 1);
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      // Transient : bruit blanc exp decay court.
      final transient = (rng.nextDouble() * 2 - 1) * math.exp(-t / 0.010);
      // Corps tonal : oscillation amortie (τ long pour le grave).
      final body = math.sin(twoPi * bodyFreq * t) * math.exp(-t / 0.18);
      // Sub-harmonique (frappe de peau).
      final sub =
          math.sin(twoPi * (bodyFreq * 0.45) * t) * math.exp(-t / 0.22) * 0.5;
      // Légère non-linéarité membrane.
      final mem =
          math.sin(twoPi * (bodyFreq * 1.62) * t) * math.exp(-t / 0.06) * 0.2;
      out[i] = transient * 0.45 + body * 0.75 + sub + mem;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.001,
      decay: 0.06,
      sustainLevel: 0.55,
      release: duration - 0.061 > 0 ? duration - 0.061 : 0.04,
    );
    return out;
  }

  /// Frappe sèche djembé type "tac" — corps plus aigu, transient court.
  static Float32List _tac(double bodyFreq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    final rng = math.Random(bodyFreq.toInt() + 7);
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final transient = (rng.nextDouble() * 2 - 1) * math.exp(-t / 0.005);
      final body = math.sin(twoPi * bodyFreq * t) * math.exp(-t / 0.07);
      final over =
          math.sin(twoPi * (bodyFreq * 1.8) * t) * math.exp(-t / 0.03) * 0.25;
      out[i] = transient * 0.60 + body * 0.65 + over;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.001,
      decay: 0.03,
      sustainLevel: 0.50,
      release: duration - 0.031 > 0 ? duration - 0.031 : 0.03,
    );
    return out;
  }

  /// Note balafon (partiels bois) — version taille et timbre ajustables.
  static Float32List _balafonNote(double freq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    const partials = <double>[1, 2.76, 5.4];
    const partialAmps = <double>[1, 0.45, 0.18];
    const vibratoHz = 5.0;
    const vibratoDepth = 0.004;
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final vib = 1.0 + vibratoDepth * math.sin(twoPi * vibratoHz * t);
      var s = 0.0;
      for (var p = 0; p < partials.length; p++) {
        final d = math.exp(-3.5 * partials[p] * t);
        s += partialAmps[p] * d * math.sin(twoPi * freq * partials[p] * vib * t);
      }
      out[i] = s * 0.55;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.003,
      decay: 0.06,
      sustainLevel: 0.30,
      release: duration - 0.063 > 0 ? duration - 0.063 : 0.03,
    );
    return out;
  }

  /// Kora fortissimo — Karplus-Strong grave, sustain long, vibrato intense.
  static Float32List _koraFortissimo(double freq, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final delayLen = (sr / freq).round().clamp(2, sr);
    final rng = math.Random(freq.toInt() + 13);
    final delay = Float32List(delayLen);
    // Excitation plus forte (amplitude 1.0) pour le fortissimo.
    for (var i = 0; i < delayLen; i++) {
      delay[i] = rng.nextDouble() * 2 - 1;
    }
    final out = Float32List(n);
    var idx = 0;
    // Damping plus faible → sustain plus long.
    const damping = 0.9985;
    // Vibrato légèrement plus profond que la kora standard.
    const vibratoHz = 4.8;
    const vibratoDepth = 0.007;
    const twoPi = 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final vib = 1.0 + vibratoDepth * math.sin(twoPi * vibratoHz * t);
      final next =
          (delay[idx] + delay[(idx + 1) % delayLen]) * 0.5 * damping;
      out[i] = delay[idx] * vib * 0.75;
      delay[idx] = next;
      idx = (idx + 1) % delayLen;
    }
    WavBuffer.applyAdsr(
      out,
      attack: 0.003,
      sustainLevel: 0.90,
      release: duration * 0.85,
    );
    return out;
  }

  /// Sweep très grave pour frappe d'ouverture du duel (effet gong).
  static Float32List _graveSweep(double f0, double f1, double duration) {
    const sr = WavBuffer.sampleRate;
    final n = (duration * sr).round();
    final out = Float32List(n);
    const twoPi = 2 * math.pi;
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final r = i / n;
      // Sweep exponentiel pour un glide plus naturel qu'un sweep linéaire.
      final f = f0 * math.pow(f1 / f0, r);
      phase += twoPi * f / sr;
      // Mélange fondamentale + 2 partiels légèrement désaccordés (effet gong).
      final s = math.sin(phase) * 0.70 +
          math.sin(phase * 1.41) * 0.18 +
          math.sin(phase * 2.23) * 0.12;
      out[i] = s;
    }
    WavBuffer.applyAdsr(
      out,
      decay: 0.12,
      sustainLevel: 0.45,
      release: duration - 0.125 > 0 ? duration - 0.125 : 0.05,
    );
    return out;
  }
}
