import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/instruments/balafon.dart';
import 'package:defi_kilimandjaro/audio/instruments/kora.dart';
import 'package:defi_kilimandjaro/audio/instruments/tam_tam.dart';
import 'package:defi_kilimandjaro/audio/wav_buffer.dart';

/// Fanfare de victoire (séquenceur/compositeur) — cf. maquette p.12.
///
/// Combine :
/// - Balafon : montée 7 notes (~1.6 s)
/// - Kora : contrepoint arpégé (départ +120 ms)
/// - Tam-tam : cascade de 3 frappes graves (départ +400 ms)
class GriotFanfare {
  GriotFanfare._();

  /// Rendu mixé final, prêt à charger via `flutter_soloud.loadMem`.
  static Uint8List render() {
    const total = 2.0;
    final out = WavBuffer.silence(total);

    final balafon = Balafon.renderVictoryRun();
    final kora = Kora.renderVictoryCounterpoint();
    final tam = TamTam.renderVictoryCascade();

    WavBuffer.mixInto(out, balafon, gain: 0.85);
    WavBuffer.mixInto(
      out,
      kora,
      offset: (0.12 * WavBuffer.sampleRate).round(),
      gain: 0.55,
    );
    WavBuffer.mixInto(
      out,
      tam,
      offset: (0.40 * WavBuffer.sampleRate).round(),
      gain: 0.6,
    );

    WavBuffer.normalize(out);
    return WavBuffer.encodeMono16(out);
  }
}
