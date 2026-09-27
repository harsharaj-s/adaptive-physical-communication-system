import 'dart:math' as math;
import 'dart:typed_data';

/// Multi-tone FSK modem for data over sound.
///
/// Several tones sound at once, each drawn from its own block of 16
/// frequencies, so one symbol carries 4 bits per tone instead of the single
/// bit a two-tone scheme manages. This is the modulation ggwave uses, and it
/// is what lifts the channel from ~7 B/s to tens of B/s.
///
/// Every frequency is an exact FFT bin of [frameSamples] — `bin * sampleRate /
/// frameSamples` — which makes the tones mutually orthogonal over the analysis
/// window and keeps consecutive symbols phase-continuous, so there are no
/// clicks to splatter energy across the band.
class MtFskCodec {
  MtFskCodec({
    this.sampleRate = 44100,
    this.frameSamples = 1024,
    this.baseBin = 40,
    this.groups = 6,
    this.framesPerSymbol = 4,
    this.markerFrames = 2,
  })  : assert(groups >= 1),
        assert(groups.isEven, 'bytes per symbol must be whole'),
        assert(framesPerSymbol >= 1) {
    _coefficients = Float64List(groups * _tonesPerGroup);
    for (var g = 0; g < groups; g++) {
      for (var v = 0; v < _tonesPerGroup; v++) {
        _coefficients[g * _tonesPerGroup + v] = _coeffForBin(binFor(g, v));
      }
    }
    _syncCoeffA = _coeffForBin(syncBinA);
    _syncCoeffB = _coeffForBin(syncBinB);
  }

  static const _tonesPerGroup = 16; // 4 bits

  final int sampleRate;

  /// Analysis window length. Bin spacing is `sampleRate / frameSamples`.
  final int frameSamples;

  /// Lowest data bin. 40 at 44.1 kHz/1024 is ~1.7 kHz, where phone speakers
  /// and microphones are both well behaved.
  final int baseBin;

  /// Simultaneous tones. Each carries a nibble, so `groups / 2` bytes per
  /// symbol. More groups means more throughput but less power per tone.
  final int groups;

  /// Frames per symbol. Longer symbols survive reverberation better.
  final int framesPerSymbol;

  /// Length of the sync burst that opens each frame.
  final int markerFrames;

  late final Float64List _coefficients;
  late final double _syncCoeffA;
  late final double _syncCoeffB;

  /// Sync tones sit just below the data band so the receiver can hunt for
  /// frame starts with two Goertzel evaluations instead of ninety-six.
  ///
  /// Both are deliberately low: detection scores on the weaker of the two, and
  /// speaker roll-off starves the top of the band precisely when conditions
  /// are worst, so a high sync tone would fail when it is needed most.
  int get syncBinA => baseBin - 12;
  int get syncBinB => baseBin - 4;

  int get bytesPerSymbol => groups ~/ 2;
  int get samplesPerSymbol => frameSamples * framesPerSymbol;
  int get samplesPerMarker => frameSamples * markerFrames;
  double get binHz => sampleRate / frameSamples;
  double get symbolMs => samplesPerSymbol * 1000 / sampleRate;

  /// Payload bytes per second, ignoring the per-frame marker.
  double get rawBytesPerSecond => bytesPerSymbol * 1000 / symbolMs;

  int binFor(int group, int value) => baseBin + group * _tonesPerGroup + value;

  double frequencyFor(int group, int value) => binFor(group, value) * binHz;

  int symbolsForBytes(int byteCount) =>
      (byteCount + bytesPerSymbol - 1) ~/ bytesPerSymbol;

  /// Total samples one framed transmission occupies.
  int samplesForBytes(int byteCount) =>
      samplesPerMarker + symbolsForBytes(byteCount) * samplesPerSymbol;

  double _coeffForBin(int bin) => 2 * math.cos(2 * math.pi * bin / frameSamples);

  /// Modulate [payload] as a marker burst followed by data symbols.
  Float32List encode(Uint8List payload) {
    final symbolCount = symbolsForBytes(payload.length);
    final out = Float32List(samplesPerMarker + symbolCount * samplesPerSymbol);

    _writeTones(out, 0, samplesPerMarker, [syncBinA, syncBinB]);

    var offset = samplesPerMarker;
    for (var s = 0; s < symbolCount; s++) {
      final bins = <int>[];
      for (var g = 0; g < groups; g++) {
        final nibbleIndex = s * groups + g;
        final byteIndex = nibbleIndex ~/ 2;
        final byte = byteIndex < payload.length ? payload[byteIndex] : 0;
        final nibble = nibbleIndex.isEven ? (byte >> 4) & 0x0F : byte & 0x0F;
        bins.add(binFor(g, nibble));
      }
      _writeTones(out, offset, samplesPerSymbol, bins);
      offset += samplesPerSymbol;
    }
    return out;
  }

  void _writeTones(Float32List out, int start, int length, List<int> bins) {
    // Amplitude is split evenly so a worst-case in-phase sum cannot clip.
    final amplitude = 0.98 / bins.length;
    for (final bin in bins) {
      final step = 2 * math.pi * bin / frameSamples;
      for (var i = 0; i < length; i++) {
        out[start + i] += amplitude * math.sin(step * i);
      }
    }
  }

  /// Goertzel power at a precomputed coefficient over `samples[start, start+len)`.
  double _power(Float32List samples, int start, int length, double coeff) {
    var s1 = 0.0;
    var s2 = 0.0;
    final end = start + length;
    for (var i = start; i < end; i++) {
      final s0 = samples[i] + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return (s1 * s1 + s2 * s2 - coeff * s1 * s2) / length;
  }

  double _meanSquare(Float32List samples, int start, int length) {
    var sum = 0.0;
    final end = start + length;
    for (var i = start; i < end; i++) {
      sum += samples[i] * samples[i];
    }
    return sum / length;
  }

  /// Sync-tone strength at [start], normalised by window energy so the score
  /// does not depend on recording volume.
  ///
  /// Scored per half-window and reported as the weaker half. Normalising a
  /// single full window by its own energy makes the score scale-invariant, so
  /// a window holding only the back half of the burst and half silence scores
  /// as well as an aligned one — which locked every frame a full frame early.
  /// Requiring both halves to be tone removes that ambiguity: since the
  /// window is exactly as long as the burst, only the true onset can fill it.
  double markerScore(Float32List samples, int start) {
    if (start < 0 || start + samplesPerMarker > samples.length) return 0;
    final half = samplesPerMarker ~/ 2;
    var worst = double.infinity;
    for (var at = start; at < start + samplesPerMarker; at += half) {
      final energy = _meanSquare(samples, at, half);
      if (energy <= 1e-12) return 0;
      final a = _power(samples, at, half, _syncCoeffA);
      final b = _power(samples, at, half, _syncCoeffB);
      // Both tones must be present, so score on the weaker one.
      final score = (2 * math.min(a, b)) / energy;
      if (score < worst) worst = score;
    }
    return worst;
  }

  /// Cheap alignment objective: how cleanly one symbol resolves to a single
  /// tone per group. Peaks sharply at the correct offset, so it can be used to
  /// fine-tune timing without demodulating the whole frame.
  ///
  /// [groupLimit] trims how many groups are examined, trading a little
  /// discrimination for speed during an offset sweep.
  double symbolConfidence(Float32List samples, int start, {int? groupLimit}) {
    if (start < 0 || start + samplesPerSymbol > samples.length) return 0;
    final examined = (groupLimit ?? groups).clamp(1, groups);
    var sum = 0.0;
    for (var g = 0; g < examined; g++) {
      var best = -1.0;
      var total = 0.0;
      for (var v = 0; v < _tonesPerGroup; v++) {
        final p = _power(
          samples,
          start,
          samplesPerSymbol,
          _coefficients[g * _tonesPerGroup + v],
        );
        total += p;
        if (p > best) best = p;
      }
      sum += total > 1e-12 ? best / total : 0.0;
    }
    return sum / examined;
  }

  /// Demodulate one symbol, returning the chosen nibble per group plus a
  /// confidence in 0..1 (winning tone energy over the group's total).
  ({List<int> nibbles, double confidence}) decodeSymbol(
    Float32List samples,
    int start,
  ) {
    final nibbles = List<int>.filled(groups, 0);
    final margins = Float64List(groups);
    final confidence = _demodulate(samples, start, nibbles, margins);
    return (nibbles: nibbles, confidence: confidence);
  }

  /// Picks the strongest tone per group into [nibbles] and records in
  /// [margins] how decisively it won: `1 - runnerUp / best`, so 0 is a coin
  /// toss and 1 is a lone tone. Returns the mean best-over-total confidence.
  double _demodulate(
    Float32List samples,
    int start,
    List<int> nibbles,
    Float64List margins,
  ) {
    var confidenceSum = 0.0;
    for (var g = 0; g < groups; g++) {
      var best = -1.0;
      var second = 0.0;
      var bestValue = 0;
      var total = 0.0;
      for (var v = 0; v < _tonesPerGroup; v++) {
        final p = _power(
          samples,
          start,
          samplesPerSymbol,
          _coefficients[g * _tonesPerGroup + v],
        );
        total += p;
        if (p > best) {
          second = math.max(best, 0.0);
          best = p;
          bestValue = v;
        } else if (p > second) {
          second = p;
        }
      }
      nibbles[g] = bestValue;
      margins[g] = best > 1e-12 ? 1 - second / best : 0.0;
      confidenceSum += total > 1e-12 ? best / total : 0.0;
    }
    return confidenceSum / groups;
  }

  /// Demodulate [byteCount] bytes of data symbols beginning at [start].
  ({Uint8List bytes, double confidence}) decodeBytes(
    Float32List samples,
    int start,
    int byteCount,
  ) {
    final soft = decodeBytesSoft(samples, start, byteCount);
    return (bytes: soft.bytes, confidence: soft.confidence);
  }

  /// [decodeBytes] plus a per-byte reliability in 0..1, taken from the less
  /// decisive of the byte's two nibbles. Lets an erasure-aware decoder spend
  /// its parity on the bytes most likely to be wrong.
  ({Uint8List bytes, double confidence, Float64List reliability})
      decodeBytesSoft(
    Float32List samples,
    int start,
    int byteCount,
  ) {
    final symbolCount = symbolsForBytes(byteCount);
    final out = Uint8List(symbolCount * bytesPerSymbol);
    final reliability = Float64List(symbolCount * bytesPerSymbol);
    final nibbles = List<int>.filled(groups, 0);
    final margins = Float64List(groups);
    var confidenceSum = 0.0;
    var offset = start;

    for (var s = 0; s < symbolCount; s++) {
      if (offset + samplesPerSymbol > samples.length) break;
      confidenceSum += _demodulate(samples, offset, nibbles, margins);
      for (var g = 0; g < groups; g += 2) {
        final index = s * bytesPerSymbol + g ~/ 2;
        out[index] = (nibbles[g] << 4) | nibbles[g + 1];
        reliability[index] = math.min(margins[g], margins[g + 1]);
      }
      offset += samplesPerSymbol;
    }

    return (
      bytes: Uint8List.sublistView(out, 0, byteCount),
      confidence: symbolCount > 0 ? confidenceSum / symbolCount : 0.0,
      reliability: Float64List.sublistView(reliability, 0, byteCount),
    );
  }
}
