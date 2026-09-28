import 'dart:math' as math;
import 'dart:typed_data';

/// One look at what the microphone is hearing, for a live readout.
class SpectrumSnapshot {
  const SpectrumSnapshot({
    required this.bands,
    required this.bandHz,
    required this.peaksHz,
    required this.peakDbfs,
  });

  /// Loudest level in each equal-width band from 0 Hz up, mapped from
  /// [SpectrumAnalyzer.floorDbfs]…[SpectrumAnalyzer.ceilingDbfs] onto 0…1.
  final Float32List bands;

  /// Width of one entry in [bands].
  final double bandHz;

  /// Distinct tones standing clear of the noise, strongest first.
  final List<double> peaksHz;

  /// Level of the strongest tone, or null when nothing stands out.
  final double? peakDbfs;

  double? get strongestHz => peaksHz.isEmpty ? null : peaksHz.first;

  static final empty = SpectrumSnapshot(
    bands: Float32List(0),
    bandHz: 0,
    peaksHz: const [],
    peakDbfs: null,
  );
}

/// Windowed FFT over the most recent [size] samples of a stream.
///
/// At 1024 points and 44.1 kHz the bins are 43.07 Hz apart — the modem's own
/// tone grid — and parabolic interpolation between bins places a tone to a
/// few hertz. Samples are only copied into a ring as they arrive; the
/// transform runs when [analyze] is called, so the caller sets the cost by
/// how often it asks.
class SpectrumAnalyzer {
  SpectrumAnalyzer({
    this.size = 1024,
    this.sampleRate = 44100,
    this.bandCount = 96,
    this.minPeakHz = 500,
    this.maxPeakHz = 21000,
    this.maxPeaks = 8,
  })  : assert(size >= 64 && (size & (size - 1)) == 0, 'power of two'),
        _ring = Float32List(size),
        _re = Float64List(size),
        _im = Float64List(size),
        _window = Float64List(size),
        _power = Float64List(size ~/ 2) {
    for (var i = 0; i < size; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1));
    }
    _cos = Float64List(size ~/ 2);
    _sin = Float64List(size ~/ 2);
    for (var i = 0; i < size ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / size);
      _sin[i] = -math.sin(2 * math.pi * i / size);
    }
  }

  static const floorDbfs = -100.0;
  static const ceilingDbfs = -20.0;

  /// How far above the median bin a peak must stand to count as a tone.
  static const peakMarginDb = 18.0;

  /// A tone quieter than this is treated as noise however clean it looks.
  static const peakMinDbfs = -85.0;

  final int size;
  final int sampleRate;
  final int bandCount;
  final double minPeakHz;
  final double maxPeakHz;
  final int maxPeaks;

  final Float32List _ring;
  final Float64List _re;
  final Float64List _im;
  final Float64List _window;
  final Float64List _power;
  late final Float64List _cos;
  late final Float64List _sin;
  int _write = 0;
  int _filled = 0;

  double get binHz => sampleRate / size;

  void add(Float32List samples) {
    var start = 0;
    if (samples.length > size) start = samples.length - size;
    for (var i = start; i < samples.length; i++) {
      _ring[_write] = samples[i];
      _write = (_write + 1) & (size - 1);
    }
    _filled = math.min(size, _filled + samples.length - start);
  }

  void reset() {
    _ring.fillRange(0, size, 0);
    _write = 0;
    _filled = 0;
  }

  SpectrumSnapshot analyze() {
    if (_filled < size) return SpectrumSnapshot.empty;
    for (var i = 0; i < size; i++) {
      _re[i] = _ring[(_write + i) & (size - 1)] * _window[i];
      _im[i] = 0;
    }
    _fft();

    // A full-scale sine through a Hann window peaks at size/4 in magnitude.
    final ref = (size / 4) * (size / 4);
    final half = size ~/ 2;
    for (var k = 0; k < half; k++) {
      _power[k] = (_re[k] * _re[k] + _im[k] * _im[k]) / ref;
    }

    final peaks = _peaks(half);
    return SpectrumSnapshot(
      bands: _bands(half),
      bandHz: sampleRate / 2 / bandCount,
      peaksHz: [for (final p in peaks) p.hz],
      peakDbfs: peaks.isEmpty ? null : peaks.first.db,
    );
  }

  Float32List _bands(int half) {
    final out = Float32List(bandCount);
    final perBand = half / bandCount;
    for (var b = 0; b < bandCount; b++) {
      final from = (b * perBand).floor();
      final to = math.min(half, ((b + 1) * perBand).ceil());
      var best = 0.0;
      for (var k = from; k < to; k++) {
        if (_power[k] > best) best = _power[k];
      }
      out[b] = _level(_db(best));
    }
    return out;
  }

  /// Local maxima standing [peakMarginDb] above the median bin, strongest
  /// first. A peak within [_lobeBins] of a stronger one, or more than
  /// [_rangeDb] below the strongest, is that tone's window leakage rather
  /// than a tone of its own.
  List<({double hz, double db, int bin})> _peaks(int half) {
    final lo = math.max(1, (minPeakHz / binHz).ceil());
    final hi = math.min(half - 2, (maxPeakHz / binHz).floor());
    if (hi <= lo) return const [];

    final sorted = Float64List.sublistView(_power, lo, hi + 1).toList()..sort();
    final floor = _db(sorted[sorted.length ~/ 2]);
    final threshold = math.max(floor + peakMarginDb, peakMinDbfs);

    final candidates = <({double hz, double db, int bin})>[];
    for (var k = lo; k <= hi; k++) {
      final p = _power[k];
      if (p <= _power[k - 1] || p < _power[k + 1]) continue;
      final db = _db(p);
      if (db < threshold) continue;
      candidates.add((hz: _interpolate(k) * binHz, db: db, bin: k));
    }
    candidates.sort((a, b) => b.db.compareTo(a.db));

    final kept = <({double hz, double db, int bin})>[];
    for (final c in candidates) {
      if (kept.length == maxPeaks) break;
      if (kept.isNotEmpty && c.db < kept.first.db - _rangeDb) break;
      if (kept.any((k) => (k.bin - c.bin).abs() <= _lobeBins)) continue;
      kept.add(c);
    }
    return kept;
  }

  static const _lobeBins = 4;
  static const _rangeDb = 35.0;

  /// Fractional bin of the peak at [k], from a parabola through the log
  /// magnitudes of it and its neighbours.
  double _interpolate(int k) {
    final a = _db(_power[k - 1]);
    final b = _db(_power[k]);
    final c = _db(_power[k + 1]);
    final denom = a - 2 * b + c;
    if (denom.abs() < 1e-9) return k.toDouble();
    return k + (0.5 * (a - c) / denom).clamp(-0.5, 0.5);
  }

  static double _db(double power) =>
      power <= 1e-20 ? -200 : 10 * math.log(power) / math.ln10;

  static double _level(double db) =>
      ((db - floorDbfs) / (ceilingDbfs - floorDbfs)).clamp(0.0, 1.0);

  /// In-place iterative radix-2 FFT of [_re] and [_im].
  void _fft() {
    final n = size;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = _re[i];
        _re[i] = _re[j];
        _re[j] = tr;
        final ti = _im[i];
        _im[i] = _im[j];
        _im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final step = n ~/ len;
      final halfLen = len >> 1;
      for (var i = 0; i < n; i += len) {
        for (var j = 0; j < halfLen; j++) {
          final wr = _cos[j * step];
          final wi = _sin[j * step];
          final a = i + j;
          final b = a + halfLen;
          final xr = _re[b] * wr - _im[b] * wi;
          final xi = _re[b] * wi + _im[b] * wr;
          _re[b] = _re[a] - xr;
          _im[b] = _im[a] - xi;
          _re[a] += xr;
          _im[a] += xi;
        }
      }
    }
  }
}
