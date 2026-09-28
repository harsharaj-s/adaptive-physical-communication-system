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
    this.chatterSnrDb,
    this.wobblePpm = 0,
    this.micGain = 1.0,
  });

  /// Level the data signal reaches the ADC at. Loud chatter needs headroom;
  /// clipping it would smear distortion across every band, which a real
  /// microphone with AGC off does not do.
  final double micGain;

  final String name;
  final double snrDb;
  final double reverbTail;
  final int rolloffStages;
  final double clockDriftPpm;
  final int multipathTaps;

  /// Signal-to-babble ratio of simulated voices (harmonic, 100–250 Hz
  /// fundamentals, energy below ~5 kHz), or null for a silent room. This is
  /// the noise real rooms actually have, and the reason the audible band
  /// struggles where the near-ultrasonic one does not.
  final double? chatterSnrDb;

  /// Peak Doppler of a hand-held phone moving back and forth at ~1 Hz, as a
  /// time-varying clock ratio. 600 ppm is about 0.2 m/s.
  final double wobblePpm;

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

  // Near-ultrasonic scenarios. No roll-off stages: the audible model's
  // low-pass is a stand-in for a small speaker's top end, and at 19 kHz what
  // matters is how weak the tone arrives relative to the microphone's own
  // noise, which [snrDb] already expresses.

  /// Phones on a desk 20 cm apart, quiet room, weak high-band response.
  static const ultraDesk = AcousticScenario(
    name: 'ultra desk',
    snrDb: 10,
    reverbTail: 0.2,
    rolloffStages: 0,
    clockDriftPpm: 80,
    multipathTaps: 3,
  );

  /// Held in hand across a table, some echo, a little movement.
  static const ultraHand = AcousticScenario(
    name: 'ultra hand',
    snrDb: 4,
    reverbTail: 0.35,
    rolloffStages: 0,
    clockDriftPpm: 200,
    multipathTaps: 5,
    wobblePpm: 500,
  );

  /// People talking nearby: voices 6 dB above the data signal.
  static const chatter = AcousticScenario(
    name: 'chatter',
    snrDb: 10,
    reverbTail: 0.3,
    rolloffStages: 0,
    clockDriftPpm: 100,
    multipathTaps: 3,
    chatterSnrDb: -6,
    micGain: 0.2,
  );

  /// A loud crowd: voices 15 dB above the data signal.
  static const crowd = AcousticScenario(
    name: 'crowd',
    snrDb: 10,
    reverbTail: 0.3,
    rolloffStages: 0,
    clockDriftPpm: 100,
    multipathTaps: 3,
    chatterSnrDb: -15,
    micGain: 0.08,
  );

  static const ultra = [ultraDesk, ultraHand, chatter, crowd];
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
  if (scenario.clockDriftPpm != 0 || scenario.wobblePpm != 0) {
    final drift = 1 + scenario.clockDriftPpm / 1e6;
    final wobble = scenario.wobblePpm / 1e6;
    final n = (clean.length * drift * (1 + wobble)).ceil();
    final resampled = Float32List(n);
    var pos = 0.0;
    var written = 0;
    // Cubic (Catmull-Rom) interpolation: linear interpolation is itself a
    // low-pass that would knock ~6 dB off a 19 kHz tone and flatter nothing.
    double at(int i) => i >= 0 && i < clean.length ? clean[i] : 0.0;
    while (written < n && pos < clean.length) {
      final i0 = pos.floor();
      final t = pos - i0;
      final p0 = at(i0 - 1), p1 = at(i0), p2 = at(i0 + 1), p3 = at(i0 + 2);
      resampled[written] = p1 +
          0.5 *
              t *
              (p2 -
                  p0 +
                  t *
                      (2 * p0 -
                          5 * p1 +
                          4 * p2 -
                          p3 +
                          t * (3 * (p1 - p2) + p3 - p0)));
      final ratio =
          drift * (1 + wobble * sin(2 * pi * written / sampleRate));
      pos += 1 / ratio;
      written++;
    }
    src = Float32List.sublistView(resampled, 0, written);
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

  if (scenario.micGain != 1.0) {
    for (var i = 0; i < out.length; i++) {
      out[i] *= scenario.micGain;
    }
  }

  var power = 0.0;
  for (var i = leadSilence; i < leadSilence + src.length; i++) {
    power += out[i] * out[i];
  }
  power /= src.length;
  final chatterDb = scenario.chatterSnrDb;
  if (chatterDb != null) {
    _addChatter(out, rng, sampleRate, power / pow(10, chatterDb / 10));
  }
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

/// Three talkers: harmonic series on gliding 100–250 Hz fundamentals with
/// 1/k harmonic roll-off up to 5 kHz, gated at a syllable rate. Harmonic
/// babble is far harder on tone detectors than white noise because its
/// energy comes in narrow peaks that land on data bins.
void _addChatter(Float32List out, Random rng, int sampleRate, double power) {
  const voices = 3;
  final buffer = Float32List(out.length);
  for (var v = 0; v < voices; v++) {
    final f0 = 100 + rng.nextDouble() * 150;
    final glideHz = 0.3 + rng.nextDouble() * 0.5;
    final syllableHz = 3 + rng.nextDouble() * 2;
    final harmonics = (5000 / f0).floor();
    final phases = List.generate(harmonics, (_) => rng.nextDouble() * 2 * pi);
    var phase = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final pitch = f0 * (1 + 0.15 * sin(2 * pi * glideHz * t + v));
      phase += 2 * pi * pitch / sampleRate;
      final gate = max(0.0, sin(2 * pi * syllableHz * t + v * 1.7));
      var s = 0.0;
      for (var k = 1; k <= harmonics; k++) {
        s += sin(k * phase + phases[k - 1]) / k;
      }
      buffer[i] += gate * s;
    }
  }
  var have = 0.0;
  for (final s in buffer) {
    have += s * s;
  }
  have /= buffer.length;
  if (have <= 0) return;
  final gain = sqrt(power / have);
  for (var i = 0; i < out.length; i++) {
    out[i] += buffer[i] * gain;
  }
}
