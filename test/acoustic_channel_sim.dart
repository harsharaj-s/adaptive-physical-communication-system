import 'dart:math';
import 'dart:typed_data';

/// A deliberately unkind room-and-hardware model for the acoustic channel.
///
/// Narrowband tone detection enjoys a large processing gain, so plain white
/// noise barely troubles it and tells you nothing. What actually breaks
/// multi-tone FSK is frequency-selective multipath (nulls that can wipe out
/// the winning tone of a group), speaker and microphone roll-off (which
/// starves the high tones) and sample-clock drift between the two devices.
class AcousticScenario {
  const AcousticScenario({
    required this.name,
    required this.snrDb,
    required this.reverbTail,
    required this.rolloffStages,
    required this.clockDriftPpm,
    required this.multipathTaps,
  });

  final String name;
  final double snrDb;
  final double reverbTail;
  final int rolloffStages;
  final double clockDriftPpm;
  final int multipathTaps;

  /// Two phones on a desk, quiet room.
  static const easy = AcousticScenario(
    name: 'easy',
    snrDb: 20,
    reverbTail: 0.15,
    rolloffStages: 0,
    clockDriftPpm: 0,
    multipathTaps: 0,
  );

  /// Across a table in a normal room.
  static const room = AcousticScenario(
    name: 'room',
    snrDb: 12,
    reverbTail: 0.35,
    rolloffStages: 2,
    clockDriftPpm: 50,
    multipathTaps: 3,
  );

  /// Background chatter, further apart, reverberant.
  static const noisyRoom = AcousticScenario(
    name: 'noisy room',
    snrDb: 6,
    reverbTail: 0.45,
    rolloffStages: 4,
    clockDriftPpm: 200,
    multipathTaps: 5,
  );

  /// Worst case we still want to carry a short message: loud room, phones a
  /// few metres apart, cheap speaker, badly mismatched sample clocks.
  static const hostile = AcousticScenario(
    name: 'hostile',
    snrDb: 2,
    reverbTail: 0.55,
    rolloffStages: 6,
    clockDriftPpm: 400,
    multipathTaps: 7,
  );

  static const all = [easy, room, noisyRoom];

  static const allIncludingHostile = [easy, room, noisyRoom, hostile];
}

/// Push [clean] through the simulated room and return what a microphone hears.
Float32List simulateAcoustic(
  Float32List clean, {
  required AcousticScenario scenario,
  int leadSilence = 1777,
  int seed = 1,
  int sampleRate = 44100,
}) {
  final rng = Random(seed);

  var src = clean;
  if (scenario.clockDriftPpm != 0) {
    final ratio = 1 + scenario.clockDriftPpm / 1e6;
    final n = (clean.length * ratio).floor();
    final resampled = Float32List(n);
    for (var i = 0; i < n; i++) {
      final pos = i / ratio;
      final i0 = pos.floor();
      final frac = pos - i0;
      final a = i0 < clean.length ? clean[i0] : 0.0;
      final b = i0 + 1 < clean.length ? clean[i0 + 1] : 0.0;
      resampled[i] = a + (b - a) * frac;
    }
    src = resampled;
  }

  final out = Float32List(leadSilence + src.length + sampleRate ~/ 2);
  for (var i = 0; i < src.length; i++) {
    out[leadSilence + i] += src[i];
  }

  for (var t = 0; t < scenario.multipathTaps; t++) {
    final delay = 40 + rng.nextInt(1200);
    final gain = (rng.nextDouble() * 0.7 + 0.2) * (rng.nextBool() ? 1 : -1);
    for (var i = 0; i < src.length; i++) {
      final j = leadSilence + i + delay;
      if (j < out.length) out[j] += src[i] * gain;
    }
  }

  if (scenario.reverbTail > 0) {
    final tap = (sampleRate * 0.035).round();
    var g = scenario.reverbTail;
    for (var k = 1; k <= 6; k++) {
      for (var i = 0; i < src.length; i++) {
        final j = leadSilence + i + tap * k;
        if (j < out.length) out[j] += src[i] * g;
      }
      g *= scenario.reverbTail;
    }
  }

  for (var s = 0; s < scenario.rolloffStages; s++) {
    var prev = 0.0;
    const alpha = 0.35;
    for (var i = 0; i < out.length; i++) {
      prev = prev + alpha * (out[i] - prev);
      out[i] = prev;
    }
  }

  var power = 0.0;
  for (var i = leadSilence; i < leadSilence + src.length; i++) {
    power += out[i] * out[i];
  }
  power /= src.length;
  final noiseAmp = sqrt(power / pow(10, scenario.snrDb / 10));
  for (var i = 0; i < out.length; i++) {
    final gauss = (rng.nextDouble() +
            rng.nextDouble() +
            rng.nextDouble() +
            rng.nextDouble() -
            2) *
        1.41;
    out[i] += noiseAmp * gauss;
    if (out[i] > 1.0) out[i] = 1.0;
    if (out[i] < -1.0) out[i] = -1.0;
  }
  return out;
}
