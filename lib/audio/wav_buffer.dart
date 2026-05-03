import 'dart:typed_data';

/// Utilities to render Float32 PCM samples into a 16-bit mono WAV byte buffer.
///
/// Used by all instruments in `lib/audio/instruments/` to produce in-memory
/// WAV data which is then passed to `flutter_soloud.loadMem()`. No file IO,
/// no bundled assets — see maquette p.12.
class WavBuffer {
  WavBuffer._();

  /// Standard sample rate used across the whole audio engine (mono, 16-bit).
  static const int sampleRate = 44100;

  /// Encode a list of Float32 samples in [-1, 1] into a complete RIFF/WAV
  /// byte buffer (16-bit PCM, mono, [sampleRate] Hz).
  static Uint8List encodeMono16(Float32List samples) {
    final dataLength = samples.length * 2;
    final totalLength = 44 + dataLength;
    final bytes = ByteData(totalLength);

    // RIFF header
    _writeAscii(bytes, 0, 'RIFF');
    bytes.setUint32(4, totalLength - 8, Endian.little);
    _writeAscii(bytes, 8, 'WAVE');

    // fmt chunk
    _writeAscii(bytes, 12, 'fmt ');
    bytes
      ..setUint32(16, 16, Endian.little) // PCM chunk size
      ..setUint16(20, 1, Endian.little) // PCM format
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little) // byte rate
      ..setUint16(32, 2, Endian.little) // block align
      ..setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    _writeAscii(bytes, 36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);

    var offset = 44;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i].clamp(-1.0, 1.0);
      final v = (s * 32767).round();
      bytes.setInt16(offset, v, Endian.little);
      offset += 2;
    }
    return bytes.buffer.asUint8List();
  }

  /// Allocate a Float32 buffer of [seconds] duration at [sampleRate] Hz,
  /// initially silent.
  static Float32List silence(double seconds) {
    final n = (seconds * sampleRate).round();
    return Float32List(n);
  }

  /// Apply a linear ADSR envelope to [buffer] in-place.
  /// All times are seconds; [sustainLevel] is in [0,1].
  static void applyAdsr(
    Float32List buffer, {
    double attack = 0.005,
    double decay = 0.05,
    double sustainLevel = 0.7,
    double release = 0.2,
  }) {
    final total = buffer.length;
    final aN = (attack * sampleRate).round().clamp(1, total);
    final dN = (decay * sampleRate).round().clamp(0, total - aN);
    final rN = (release * sampleRate).round().clamp(0, total - aN - dN);
    final sN = total - aN - dN - rN;

    var i = 0;
    for (var k = 0; k < aN; k++, i++) {
      buffer[i] *= k / aN;
    }
    for (var k = 0; k < dN; k++, i++) {
      buffer[i] *= 1.0 - (1.0 - sustainLevel) * (k / dN);
    }
    for (var k = 0; k < sN; k++, i++) {
      buffer[i] *= sustainLevel;
    }
    for (var k = 0; k < rN; k++, i++) {
      buffer[i] *= sustainLevel * (1.0 - k / rN);
    }
  }

  /// Mix [src] into [dst] at sample [offset], scaled by [gain].
  /// Out-of-range samples are clipped (dropped).
  static void mixInto(
    Float32List dst,
    Float32List src, {
    int offset = 0,
    double gain = 1.0,
  }) {
    final end = (offset + src.length).clamp(0, dst.length);
    for (var i = offset < 0 ? -offset : 0; offset + i < end; i++) {
      dst[offset + i] += src[i] * gain;
    }
  }

  /// Normalize buffer peak to [target] amplitude (default 0.95).
  static void normalize(Float32List buffer, {double target = 0.95}) {
    var peak = 0.0;
    for (var i = 0; i < buffer.length; i++) {
      final a = buffer[i].abs();
      if (a > peak) peak = a;
    }
    if (peak < 1e-9) return;
    final g = target / peak;
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] *= g;
    }
  }

  static void _writeAscii(ByteData bytes, int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }
}
