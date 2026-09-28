import 'dart:math' as math;
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/acoustic/tone_timeline.dart';

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
///
/// The same engine drives the near-ultrasonic band: one tone at a time
/// (`groups: 1`), wider [toneSpacing] and a [sequentialMarker]. A single
/// sinusoid has no intermodulation products, which matters up there — two
/// tones 1 kHz apart at 19 kHz make an audible 1 kHz buzz in any slightly
/// non-linear phone speaker.
class MtFskCodec {
  MtFskCodec({
    this.sampleRate = 44100,
    this.frameSamples = 1024,
    this.baseBin = 40,
    this.groups = 6,
    this.framesPerSymbol = 4,
    this.markerFrames = 2,
    this.toneSpacing = 1,
    this.guardFrames = 0,
    this.sequentialMarker = false,
    this.peakAmplitude = 0.98,
    int? syncBinA,
    int? syncBinB,
  })  : syncBinA = syncBinA ?? baseBin - 12,
        syncBinB = syncBinB ?? baseBin - 4,
        assert(groups >= 1),
        assert(framesPerSymbol >= 1),
        assert(guardFrames >= 0 && guardFrames < framesPerSymbol),
        assert(toneSpacing >= 1),
        assert(!sequentialMarker || markerFrames.isEven,
            'each marker half must be whole frames'),
        assert(peakAmplitude > 0 && peakAmplitude <= 1) {
    _coefficients = Float64List(groups * _tonesPerGroup);
    for (var g = 0; g < groups; g++) {
      for (var v = 0; v < _tonesPerGroup; v++) {
        _coefficients[g * _tonesPerGroup + v] = _coeffForBin(binFor(g, v));
      }
    }
    _syncCoeffA = _coeffForBin(this.syncBinA);
    _syncCoeffB = _coeffForBin(this.syncBinB);
  }

  static const _tonesPerGroup = 16; // 4 bits

  final int sampleRate;

  /// Analysis window length. Bin spacing is `sampleRate / frameSamples`.
  final int frameSamples;

  /// Lowest data bin. 40 at 44.1 kHz/1024 is ~1.7 kHz, where phone speakers
  /// and microphones are both well behaved.
  final int baseBin;

  /// Simultaneous tones. Each carries a nibble, so `groups / 2` bytes per
  /// symbol; with an odd count a byte straddles two symbols. More groups means
  /// more throughput but less power per tone.
  final int groups;

  /// Frames per symbol. Longer symbols survive reverberation better.
  final int framesPerSymbol;

  /// Length of the sync burst that opens each frame.
  final int markerFrames;

  /// Bins between neighbouring data tones. Wider spacing tolerates the
  /// Doppler shift of a moving hand, which at 19 kHz is ~17 Hz for 0.3 m/s —
  /// most of a 43 Hz bin.
  final int toneSpacing;

  /// Leading frames of each symbol left out of the analysis window, so echoes
  /// of the previous tone decay before the decision. Tones are exact bins of
  /// one frame, so any whole number of frames stays orthogonal.
  final int guardFrames;

  /// Marker plays tone A then tone B instead of both at once. Keeps the
  /// output a single sinusoid, and the ordering makes the onset unambiguous.
  final bool sequentialMarker;

  /// Peak output level. Below full scale leaves headroom for the platform
  /// resampler; clipping a 19 kHz tone folds harmonics back into the audible
  /// band on a 48 kHz output.
  final double peakAmplitude;

  /// Sync tones sit just below the data band so the receiver can hunt for
  /// frame starts with two Goertzel evaluations instead of ninety-six.
  ///
  /// Both are deliberately low: detection scores on the weaker of the two, and
  /// speaker roll-off starves the top of the band precisely when conditions
  /// are worst, so a high sync tone would fail when it is needed most.
  final int syncBinA;
  final int syncBinB;

  late final Float64List _coefficients;
  late final double _syncCoeffA;
  late final double _syncCoeffB;

  double get bytesPerSymbol => groups / 2;
  int get samplesPerSymbol => frameSamples * framesPerSymbol;
  int get samplesPerMarker => frameSamples * markerFrames;
  double get binHz => sampleRate / frameSamples;
  double get symbolMs => samplesPerSymbol * 1000 / sampleRate;

  int get _analysisOffset => guardFrames * frameSamples;
  int get _analysisLength => samplesPerSymbol - _analysisOffset;

  /// Payload bytes per second, ignoring the per-frame marker.
  double get rawBytesPerSecond => bytesPerSymbol * 1000 / symbolMs;

  int binFor(int group, int value) =>
      baseBin + (group * _tonesPerGroup + value) * toneSpacing;

  double frequencyFor(int group, int value) => binFor(group, value) * binHz;

  /// Lowest and highest frequency this codec ever emits, sync included.
  double get lowestHz =>
      math.min(math.min(syncBinA, syncBinB), baseBin) * binHz;
  double get highestHz => math.max(
        math.max(syncBinA, syncBinB),
        binFor(groups - 1, _tonesPerGroup - 1),
      ) *
      binHz;

  int symbolsForBytes(int byteCount) => (2 * byteCount + groups - 1) ~/ groups;

  /// Total samples one framed transmission occupies.
  int samplesForBytes(int byteCount) =>
      samplesPerMarker + symbolsForBytes(byteCount) * samplesPerSymbol;

  double _coeffForBin(int bin) => 2 * math.cos(2 * math.pi * bin / frameSamples);

  /// Modulate [payload] as a marker burst followed by data symbols.
  Float32List encode(Uint8List payload) {
    final symbolCount = symbolsForBytes(payload.length);
    final out = Float32List(samplesPerMarker + symbolCount * samplesPerSymbol);

    final half = samplesPerMarker ~/ 2;
    for (var h = 0; h < 2; h++) {
      _writeTones(out, h * half, half, _markerBins(h));
    }

    var offset = samplesPerMarker;
    for (var s = 0; s < symbolCount; s++) {
      _writeTones(out, offset, samplesPerSymbol, _symbolBins(payload, s));
      offset += samplesPerSymbol;
    }
    return out;
  }

  /// Append what [encode] would play for [payload] to [into], without
  /// synthesising any audio.
  void describe(Uint8List payload, ToneTimeline into) {
    List<double> hz(List<int> bins) => [for (final b in bins) b * binHz];
    final half = samplesPerMarker ~/ 2;
    for (var h = 0; h < 2; h++) {
      into.addTones(half, ToneKind.marker, hz(_markerBins(h)));
    }
    final symbolCount = symbolsForBytes(payload.length);
    for (var s = 0; s < symbolCount; s++) {
      into.addTones(
          samplesPerSymbol, ToneKind.data, hz(_symbolBins(payload, s)));
    }
  }

  List<int> _symbolBins(Uint8List payload, int symbol) => [
        for (var g = 0; g < groups; g++)
          binFor(g, _nibbleAt(payload, symbol * groups + g)),
      ];

  static int _nibbleAt(Uint8List payload, int nibbleIndex) {
    final byteIndex = nibbleIndex ~/ 2;
    final byte = byteIndex < payload.length ? payload[byteIndex] : 0;
    return nibbleIndex.isEven ? (byte >> 4) & 0x0F : byte & 0x0F;
  }

  List<int> _markerBins(int half) => sequentialMarker
      ? [half == 0 ? syncBinA : syncBinB]
      : [syncBinA, syncBinB];

  List<double> _markerCoeffs(int half) => sequentialMarker
      ? [half == 0 ? _syncCoeffA : _syncCoeffB]
      : [_syncCoeffA, _syncCoeffB];

  void _writeTones(Float32List out, int start, int length, List<int> bins) {
    // Amplitude is split evenly so a worst-case in-phase sum cannot clip.
    final amplitude = peakAmplitude / bins.length;
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
  ///
  /// An aligned marker scores `half / 2` (512 at the defaults) whether the
  /// half holds one tone or two, so one threshold serves both marker styles.
  double markerScore(Float32List samples, int start) {
    if (start < 0 || start + samplesPerMarker > samples.length) return 0;
    final half = samplesPerMarker ~/ 2;
    var worst = double.infinity;
    for (var h = 0; h < 2; h++) {
      final at = start + h * half;
      final energy = _meanSquare(samples, at, half);
      if (energy <= 1e-12) return 0;
      final coeffs = _markerCoeffs(h);
      // Every expected tone must be present, so score on the weakest one.
      var weakest = double.infinity;
      for (final c in coeffs) {
        weakest = math.min(weakest, _power(samples, at, half, c));
      }
      final score = coeffs.length * weakest / energy;
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
          start + _analysisOffset,
          _analysisLength,
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
          start + _analysisOffset,
          _analysisLength,
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
    final out = Uint8List(byteCount);
    // Bytes whose symbols never arrived keep reliability 0, so an erasure
    // decoder spends parity on them first.
    final reliability = Float64List(byteCount);
    final nibbles = List<int>.filled(groups, 0);
    final margins = Float64List(groups);
    var confidenceSum = 0.0;
    var offset = start;

    for (var s = 0; s < symbolCount; s++) {
      if (offset + samplesPerSymbol > samples.length) break;
      confidenceSum += _demodulate(samples, offset, nibbles, margins);
      for (var g = 0; g < groups; g++) {
        final nibbleIndex = s * groups + g;
        final byteIndex = nibbleIndex >> 1;
        if (byteIndex >= byteCount) break;
        if (nibbleIndex.isEven) {
          out[byteIndex] = nibbles[g] << 4;
          reliability[byteIndex] = margins[g];
        } else {
          out[byteIndex] |= nibbles[g];
          reliability[byteIndex] =
              math.min(reliability[byteIndex], margins[g]);
        }
      }
      offset += samplesPerSymbol;
    }

    return (
      bytes: out,
      confidence: symbolCount > 0 ? confidenceSum / symbolCount : 0.0,
      reliability: reliability,
    );
  }
}
