import 'dart:math';
import 'dart:typed_data';

/// Systematic Luby Transform (LT) fountain codec — UI-free, reusable.
///
/// First [K] symbols are the source blocks (zero overhead on a clean start).
/// Later symbols are XOR mixtures whose neighbour set is deterministic from
/// `(sessionId, i)` so TX/RX stay in sync.
///
/// Up to [denseMaxK] blocks every repair symbol is a uniformly random subset
/// of the blocks. With an exact GF(2) solver that is near-optimal: K+m random
/// symbols are full rank with probability at least 1 - 2^-m, whatever mix of
/// systematic and repair symbols the camera happened to catch. Larger K uses
/// fixed-weight random rows ([sparseDegree]) so encoding stays cheap.
///
/// This replaced a robust soliton distribution, whose spike at small K put
/// most symbols on the same all-blocks equation (47% of symbols at K=3): the
/// receiver kept counting "new" symbols that added no rank.
class LtEncoder {
  LtEncoder({
    required Uint8List data,
    required this.blockLen,
    required this.sessionId,
  }) : assert(blockLen > 0),
       data = Uint8List.fromList(data) {
    K = data.isEmpty ? 1 : (data.length / blockLen).ceil();
    fileLen = data.length;
    _blocks = List.generate(K, (i) {
      final out = Uint8List(blockLen);
      final start = i * blockLen;
      if (start >= data.length) return out;
      final end = min(start + blockLen, data.length);
      out.setRange(0, end - start, data, start);
      return out;
    });
  }

  /// Largest K that uses dense random-subset repair symbols.
  static const denseMaxK = 256;

  final Uint8List data;
  final int blockLen;
  final int sessionId;
  late final int K;
  late final int fileLen;
  late final List<Uint8List> _blocks;

  /// Emit symbol at [symbolIndex] (0-based, unbounded).
  Uint8List symbolAt(int symbolIndex) {
    if (symbolIndex < K) {
      return Uint8List.fromList(_blocks[symbolIndex]);
    }
    final out = Uint8List(blockLen);
    for (final n in neighborsFor(sessionId, symbolIndex, K)) {
      _xorInto(out, _blocks[n]);
    }
    return out;
  }

  /// Neighbor block indices for a repair (or systematic) symbol, ascending.
  static List<int> neighborsFor(int sessionId, int symbolIndex, int k) {
    if (k <= 0) return const [];
    if (symbolIndex < k) return [symbolIndex];
    if (k == 1) return const [0];
    if (k <= _cycleMaxK) return _cycledSubset(sessionId, symbolIndex - k, k);
    final rng = _CounterRng(_mix(sessionId, symbolIndex));
    if (k <= denseMaxK) {
      while (true) {
        final out = <int>[];
        for (var base = 0; base < k; base += 32) {
          final bits = rng.next32();
          final end = min(32, k - base);
          for (var b = 0; b < end; b++) {
            if ((bits >> b) & 1 == 1) out.add(base + b);
          }
        }
        if (out.isNotEmpty) return out;
      }
    }
    final degree = sparseDegree(k);
    final set = <int>{};
    while (set.length < degree) {
      set.add(rng.next32() % k);
    }
    return set.toList()..sort();
  }

  /// Row weight above [denseMaxK]. Leaves an expected K^-1·e^-8 blocks
  /// uncovered after K symbols, so rank deficiency stays that of a dense
  /// matrix while encoding touches only a few dozen blocks.
  static int sparseDegree(int k) => min(k ~/ 2, (2 * log(k)).ceil() + 8);

  /// Tiny K repeats a keyed shuffle of all 2^K - 1 non-empty subsets, so any
  /// window of up to 2^K - 1 consecutive symbols never repeats an equation.
  /// For K=3 any five consecutive repair symbols are guaranteed full rank.
  static const _cycleMaxK = 8;

  static List<int> _cycledSubset(int sessionId, int repairIndex, int k) {
    final cycleLen = (1 << k) - 1;
    final pos = repairIndex % cycleLen;
    final order = List<int>.generate(cycleLen, (i) => i + 1);
    final rng = _CounterRng(_mix(sessionId ^ 0x5A17C0DE, k));
    for (var i = cycleLen - 1; i > 0; i--) {
      final j = rng.next32() % (i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    final subset = order[pos];
    return [
      for (var b = 0; b < k; b++)
        if ((subset >> b) & 1 == 1) b,
    ];
  }
}

/// Exact fountain decoder: incremental Gauss-Jordan elimination over GF(2).
///
/// Completes as soon as the received symbols span all K blocks, which is the
/// best any decoder can do. Rows are kept fully reduced, so every received
/// symbol costs one XOR per pivot it touches plus one per row that shares its
/// new pivot, and a solved block becomes readable the moment it is isolated.
class LtDecoder {
  LtDecoder({
    required this.K,
    required this.blockLen,
    required this.fileLen,
    required this.sessionId,
  }) : assert(K > 0 && blockLen > 0 && fileLen >= 0),
       _words = (K + 31) >> 5 {
    _pivotMask = List<Uint32List?>.filled(K, null);
    _pivotValue = List<Uint8List?>.filled(K, null);
    _pivotSet = Uint32List(_words);
    _solved = List<bool>.filled(K, false);
  }

  final int K;
  final int blockLen;
  final int fileLen;
  final int sessionId;
  final int _words;

  late final List<Uint32List?> _pivotMask;
  late final List<Uint8List?> _pivotValue;
  late final Uint32List _pivotSet;
  late final List<bool> _solved;
  final _pivots = <int>[];
  final _seenSymbols = <int>{};
  int _solvedCount = 0;

  /// Symbols that added rank (moved the transfer forward).
  int newSymbols = 0;

  /// Symbol indices seen before.
  int duplicateSymbols = 0;

  /// Fresh symbol indices that were linear combinations of what we had.
  int redundantSymbols = 0;

  /// Source blocks already isolated and readable.
  int get recoveredCount => _solvedCount;

  /// Independent symbols held; the transfer completes when this reaches K.
  int get rank => _pivots.length;

  bool get isComplete => _pivots.length >= K;

  /// Fraction of the rank needed — the honest progress measure.
  double get progress => (rank / K).clamp(0.0, 1.0);

  /// Feed one fountain symbol. Returns true if it added rank.
  bool addSymbol(int symbolIndex, Uint8List payload) {
    if (payload.length != blockLen) return false;
    if (!_seenSymbols.add(symbolIndex)) {
      duplicateSymbols++;
      return false;
    }
    if (isComplete) {
      redundantSymbols++;
      return false;
    }

    final mask = Uint32List(_words);
    for (final n in LtEncoder.neighborsFor(sessionId, symbolIndex, K)) {
      mask[n >> 5] ^= 1 << (n & 31);
    }
    final value = Uint8List.fromList(payload);

    // Pivot rows only carry free columns besides their own pivot, so XORing
    // one in never sets another pivot bit: a single pass is enough.
    for (var w = 0; w < _words; w++) {
      var hits = mask[w] & _pivotSet[w];
      while (hits != 0) {
        final b = _lowestBit(hits);
        hits &= hits - 1;
        final c = (w << 5) + b;
        _xorMask(mask, _pivotMask[c]!);
        _xorInto(value, _pivotValue[c]!);
      }
    }

    final p = _firstSetBit(mask);
    if (p < 0) {
      redundantSymbols++;
      return false;
    }

    final pw = p >> 5;
    final pbit = 1 << (p & 31);
    for (final c in _pivots) {
      final row = _pivotMask[c]!;
      if (row[pw] & pbit == 0) continue;
      _xorMask(row, mask);
      _xorInto(_pivotValue[c]!, value);
      _updateSolved(c);
    }
    _pivotMask[p] = mask;
    _pivotValue[p] = value;
    _pivotSet[pw] |= pbit;
    _pivots.add(p);
    _updateSolved(p);
    newSymbols++;
    return true;
  }

  Uint8List? takeBytes() {
    if (!isComplete) return null;
    final out = Uint8List(fileLen);
    for (var i = 0; i < K; i++) {
      final block = _pivotValue[i];
      if (block == null || !_solved[i]) return null;
      final start = i * blockLen;
      if (start >= fileLen) break;
      final len = min(blockLen, fileLen - start);
      out.setRange(start, start + len, block);
    }
    return out;
  }

  void reset() {
    for (var i = 0; i < K; i++) {
      _pivotMask[i] = null;
      _pivotValue[i] = null;
      _solved[i] = false;
    }
    _pivotSet.fillRange(0, _words, 0);
    _pivots.clear();
    _seenSymbols.clear();
    _solvedCount = 0;
    newSymbols = 0;
    duplicateSymbols = 0;
    redundantSymbols = 0;
  }

  void _updateSolved(int c) {
    final row = _pivotMask[c]!;
    var bits = 0;
    for (var w = 0; w < _words && bits < 2; w++) {
      final v = row[w];
      if (v == 0) continue;
      bits += (v & (v - 1)) == 0 ? 1 : 2;
    }
    final solved = bits == 1;
    if (solved == _solved[c]) return;
    _solved[c] = solved;
    _solvedCount += solved ? 1 : -1;
  }

  static void _xorMask(Uint32List dst, Uint32List src) {
    for (var i = 0; i < dst.length; i++) {
      dst[i] ^= src[i];
    }
  }

  static int _firstSetBit(Uint32List mask) {
    for (var w = 0; w < mask.length; w++) {
      final v = mask[w];
      if (v != 0) return (w << 5) + _lowestBit(v);
    }
    return -1;
  }
}

void _xorInto(Uint8List dst, Uint8List src) {
  final n = dst.length;
  if (n % 4 == 0 && dst.offsetInBytes % 4 == 0 && src.offsetInBytes % 4 == 0) {
    final d = dst.buffer.asUint32List(dst.offsetInBytes, n >> 2);
    final s = src.buffer.asUint32List(src.offsetInBytes, n >> 2);
    for (var i = 0; i < d.length; i++) {
      d[i] ^= s[i];
    }
    return;
  }
  for (var i = 0; i < n; i++) {
    dst[i] ^= src[i];
  }
}

int _lowestBit(int v) {
  var m = v & 0xFFFFFFFF;
  var i = 0;
  if (m & 0xFFFF == 0) {
    m >>= 16;
    i += 16;
  }
  if (m & 0xFF == 0) {
    m >>= 8;
    i += 8;
  }
  if (m & 0xF == 0) {
    m >>= 4;
    i += 4;
  }
  if (m & 0x3 == 0) {
    m >>= 2;
    i += 2;
  }
  if (m & 0x1 == 0) i += 1;
  return i;
}

/// 32-bit multiply that stays exact on the web, where ints are doubles.
int _imul(int a, int b) {
  final lo = (a & 0xFFFF) * b;
  final hi = (((a >> 16) & 0xFFFF) * b) & 0xFFFF;
  return (lo + (hi << 16)) & 0xFFFFFFFF;
}

int _fmix32(int h) {
  var x = h & 0xFFFFFFFF;
  x ^= x >> 16;
  x = _imul(x, 0x85EBCA6B);
  x ^= x >> 13;
  x = _imul(x, 0xC2B2AE35);
  x ^= x >> 16;
  return x & 0xFFFFFFFF;
}

int _mix(int sessionId, int symbolIndex) =>
    _fmix32((sessionId & 0xFFFFFFFF) ^ _fmix32(symbolIndex + 0x632BE5AB));

/// Counter-mode generator: output j is `fmix32(seed + j * golden)`.
class _CounterRng {
  _CounterRng(this._seed);

  final int _seed;
  int _counter = 0;

  int next32() {
    _counter++;
    return _fmix32((_seed + _imul(_counter, 0x9E3779B9)) & 0xFFFFFFFF);
  }
}
