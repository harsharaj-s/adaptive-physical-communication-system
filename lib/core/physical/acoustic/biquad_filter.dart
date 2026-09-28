import 'dart:math' as math;
import 'dart:typed_data';

/// One second-order IIR section (RBJ cookbook), transposed direct form II.
///
/// State persists across calls, so a stream can be filtered chunk by chunk
/// exactly as if it had arrived in one piece.
class Biquad {
  Biquad.highPass({
    required double cutoffHz,
    required double q,
    int sampleRate = 44100,
  }) {
    final w0 = 2 * math.pi * cutoffHz / sampleRate;
    final cosW = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    final a0 = 1 + alpha;
    _b0 = (1 + cosW) / 2 / a0;
    _b1 = -(1 + cosW) / a0;
    _b2 = (1 + cosW) / 2 / a0;
    _a1 = -2 * cosW / a0;
    _a2 = (1 - alpha) / a0;
  }

  late final double _b0, _b1, _b2, _a1, _a2;
  double _z1 = 0, _z2 = 0;

  /// Filter [samples] in place.
  void process(Float32List samples) {
    var z1 = _z1, z2 = _z2;
    for (var i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = _b0 * x + z1;
      z1 = _b1 * x - _a1 * y + z2;
      z2 = _b2 * x - _a2 * y;
      samples[i] = y;
    }
    _z1 = z1;
    _z2 = z2;
  }

  void reset() {
    _z1 = 0;
    _z2 = 0;
  }
}

/// Fourth-order Butterworth high-pass: two biquads with the Butterworth Qs.
///
/// Used ahead of the near-ultrasonic receiver. Its marker score is tone power
/// over window energy, so without this, voices at 0–5 kHz inflate the energy
/// and bury an 18 kHz marker they never actually overlap. At a 16 kHz corner
/// speech harmonics at 5 kHz lose ~40 dB while 18.3 kHz loses ~1.3 dB.
class HighPassFilter {
  HighPassFilter({required double cutoffHz, int sampleRate = 44100})
      : _stages = [
          Biquad.highPass(
              cutoffHz: cutoffHz, q: 0.54119610, sampleRate: sampleRate),
          Biquad.highPass(
              cutoffHz: cutoffHz, q: 1.30656296, sampleRate: sampleRate),
        ];

  final List<Biquad> _stages;

  /// Returns a filtered copy; the caller's buffer is left untouched because
  /// the same microphone chunk is shared by every profile's receiver.
  Float32List apply(Float32List samples) {
    final out = Float32List.fromList(samples);
    for (final stage in _stages) {
      stage.process(out);
    }
    return out;
  }

  void reset() {
    for (final stage in _stages) {
      stage.reset();
    }
  }
}
