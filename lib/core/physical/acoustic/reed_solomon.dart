import 'dart:typed_data';

/// Systematic Reed-Solomon codec over GF(256).
///
/// The acoustic channel delivers a few percent of bytes wrong even in a quiet
/// room — multipath nulls can wipe out the winning tone of a group — so a
/// plain checksum would reject almost every frame. Reed-Solomon repairs up to
/// `parityBytes / 2` wrong bytes per codeword instead, which is what makes
/// data over sound practical at all.
///
/// Codewords are laid out data-first, so `encode` appends parity and the
/// leading [dataLength] bytes of a corrected codeword are the payload.
class ReedSolomon {
  ReedSolomon(this.parityBytes)
      : assert(parityBytes > 0 && parityBytes < 255) {
    _generator = _buildGenerator(parityBytes);
  }

  /// Parity bytes per codeword. Corrects up to `parityBytes ~/ 2` byte errors.
  final int parityBytes;

  late final Uint8List _generator;

  int get correctableBytes => parityBytes ~/ 2;

  int maxDataLength() => 255 - parityBytes;

  static final Uint8List _exp = Uint8List(512);
  static final Uint8List _log = Uint8List(256);
  static bool _tablesReady = false;

  static void _ensureTables() {
    if (_tablesReady) return;
    // Primitive polynomial x^8 + x^4 + x^3 + x^2 + 1 (0x11D), generator 2.
    var x = 1;
    for (var i = 0; i < 255; i++) {
      _exp[i] = x;
      _log[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) x ^= 0x11D;
    }
    for (var i = 255; i < 512; i++) {
      _exp[i] = _exp[i - 255];
    }
    _tablesReady = true;
  }

  static int _mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _exp[_log[a] + _log[b]];
  }

  static int _div(int a, int b) {
    if (b == 0) throw ArgumentError('division by zero in GF(256)');
    if (a == 0) return 0;
    return _exp[(_log[a] + 255 - _log[b]) % 255];
  }

  static int _pow(int a, int n) {
    if (a == 0) return 0;
    return _exp[(_log[a] * n) % 255];
  }

  static int _inverse(int a) => _exp[255 - _log[a]];

  /// Polynomials are stored with index 0 holding the highest-degree term.
  static Uint8List _polyMul(Uint8List p, Uint8List q) {
    final out = Uint8List(p.length + q.length - 1);
    for (var i = 0; i < p.length; i++) {
      if (p[i] == 0) continue;
      for (var j = 0; j < q.length; j++) {
        out[i + j] ^= _mul(p[i], q[j]);
      }
    }
    return out;
  }

  static int _polyEval(Uint8List p, int x) {
    var y = p[0];
    for (var i = 1; i < p.length; i++) {
      y = _mul(y, x) ^ p[i];
    }
    return y;
  }

  static Uint8List _buildGenerator(int parity) {
    _ensureTables();
    var g = Uint8List.fromList([1]);
    for (var i = 0; i < parity; i++) {
      g = _polyMul(g, Uint8List.fromList([1, _pow(2, i)]));
    }
    return g;
  }

  /// Append [parityBytes] of parity to [data].
  Uint8List encode(Uint8List data) {
    _ensureTables();
    if (data.length > maxDataLength()) {
      throw ArgumentError(
        'data of ${data.length} B exceeds RS limit of ${maxDataLength()} B',
      );
    }
    final out = Uint8List(data.length + parityBytes);
    out.setRange(0, data.length, data);

    // Synthetic division of data * x^parity by the generator.
    for (var i = 0; i < data.length; i++) {
      final coefficient = out[i];
      if (coefficient == 0) continue;
      for (var j = 1; j < _generator.length; j++) {
        out[i + j] ^= _mul(_generator[j], coefficient);
      }
    }
    out.setRange(0, data.length, data);
    return out;
  }

  /// Recover the payload from a possibly corrupted [codeword].
  ///
  /// [erasures] names byte positions the caller already suspects. Parity
  /// repairs `e` unknown errors plus `f` erasures whenever `2e + f` fits in
  /// [parityBytes], so a known-bad byte costs half as much as an unknown one.
  ///
  /// Returns null when the damage exceeds what the parity can repair, so a
  /// caller can simply drop the frame and wait for another.
  Uint8List? decode(
    Uint8List codeword, {
    int? dataLength,
    List<int> erasures = const [],
  }) {
    _ensureTables();
    final length = dataLength ?? (codeword.length - parityBytes);
    if (length <= 0 || codeword.length != length + parityBytes) return null;

    final work = Uint8List.fromList(codeword);
    final syndromes = _syndromes(work);
    if (syndromes.every((s) => s == 0)) {
      return Uint8List.sublistView(work, 0, length);
    }

    final List<int>? positions;
    if (erasures.isEmpty) {
      final locator = _errorLocator(syndromes);
      if (locator == null) return null;
      positions = _errorPositions(locator, work.length);
    } else {
      final distinct = erasures
          .where((p) => p >= 0 && p < work.length)
          .toSet()
          .toList(growable: false);
      if (distinct.length > parityBytes) return null;
      positions = _errataPositions(syndromes, distinct, work.length);
    }
    if (positions == null || positions.isEmpty) return null;

    if (!_correct(work, syndromes, positions)) return null;

    // A wrong guess can still leave a consistent-looking codeword, so verify.
    if (!_syndromes(work).every((s) => s == 0)) return null;
    return Uint8List.sublistView(work, 0, length);
  }

  List<int> _syndromes(Uint8List codeword) {
    return List<int>.generate(
      parityBytes,
      (i) => _polyEval(codeword, _pow(2, i)),
      growable: false,
    );
  }

  /// Berlekamp-Massey.
  Uint8List? _errorLocator(List<int> syndromes) {
    var locator = Uint8List.fromList([1]);
    var previous = Uint8List.fromList([1]);

    for (var i = 0; i < parityBytes; i++) {
      // Shift the fallback polynomial by one.
      final shifted = Uint8List(previous.length + 1)
        ..setRange(0, previous.length, previous);
      previous = shifted;

      var delta = syndromes[i];
      for (var j = 1; j < locator.length && j <= i; j++) {
        delta ^= _mul(locator[locator.length - 1 - j], syndromes[i - j]);
      }

      if (delta == 0) continue;

      if (previous.length > locator.length) {
        final scaled = _polyScale(previous, delta);
        previous = _polyScale(locator, _inverse(delta));
        locator = scaled;
      }
      locator = _polyAdd(locator, _polyScale(previous, delta));
    }

    // Strip leading zeros.
    var start = 0;
    while (start < locator.length && locator[start] == 0) {
      start++;
    }
    final trimmed = Uint8List.sublistView(locator, start);
    final errors = trimmed.length - 1;
    if (errors * 2 > parityBytes || errors == 0) return null;
    return Uint8List.fromList(trimmed);
  }

  /// Berlekamp-Massey seeded with the erasure locator, then Chien search.
  ///
  /// Polynomials here are lowest-degree-first. Starting from
  /// Gamma(z) = prod (1 - X_j z) over the erasures, with the register length
  /// already at their count, the iteration only has to discover the unknown
  /// errors — which is why each erasure costs one parity byte instead of two.
  List<int>? _errataPositions(
    List<int> syndromes,
    List<int> erasures,
    int codewordLength,
  ) {
    final f = erasures.length;
    var c = <int>[1];
    for (final position in erasures) {
      final xj = _pow(2, codewordLength - 1 - position);
      final next = List<int>.filled(c.length + 1, 0);
      for (var i = 0; i < c.length; i++) {
        next[i] ^= c[i];
        next[i + 1] ^= _mul(c[i], xj);
      }
      c = next;
    }

    var b = List<int>.of(c);
    var registerLength = f;
    var shift = 1;
    var lastDelta = 1;

    for (var r = f; r < parityBytes; r++) {
      var delta = 0;
      for (var j = 0; j < c.length && j <= r; j++) {
        delta ^= _mul(c[j], syndromes[r - j]);
      }
      if (delta == 0) {
        shift++;
        continue;
      }

      final previous = List<int>.of(c);
      final scale = _div(delta, lastDelta);
      if (b.length + shift > c.length) {
        c = [...c, ...List<int>.filled(b.length + shift - c.length, 0)];
      }
      for (var j = 0; j < b.length; j++) {
        c[j + shift] ^= _mul(scale, b[j]);
      }

      if (2 * registerLength <= r + f) {
        registerLength = r + f + 1 - registerLength;
        b = previous;
        lastDelta = delta;
        shift = 1;
      } else {
        shift++;
      }
    }

    var degree = c.length - 1;
    while (degree > 0 && c[degree] == 0) {
      degree--;
    }
    final errors = degree - f;
    if (errors < 0 || 2 * errors + f > parityBytes) return null;

    // A root at X_p^-1 marks position p as errata.
    final positions = <int>[];
    for (var p = 0; p < codewordLength; p++) {
      final xInverse = _inverse(_pow(2, codewordLength - 1 - p));
      var y = 0;
      for (var j = degree; j >= 0; j--) {
        y = _mul(y, xInverse) ^ c[j];
      }
      if (y == 0) positions.add(p);
    }
    if (positions.length != degree) return null;
    return positions;
  }

  static Uint8List _polyScale(Uint8List p, int scalar) {
    final out = Uint8List(p.length);
    for (var i = 0; i < p.length; i++) {
      out[i] = _mul(p[i], scalar);
    }
    return out;
  }

  static Uint8List _polyAdd(Uint8List p, Uint8List q) {
    final out = Uint8List(p.length > q.length ? p.length : q.length);
    for (var i = 0; i < p.length; i++) {
      out[i + out.length - p.length] ^= p[i];
    }
    for (var i = 0; i < q.length; i++) {
      out[i + out.length - q.length] ^= q[i];
    }
    return out;
  }

  /// Chien search: roots of the locator give the error positions.
  ///
  /// Berlekamp-Massey yields Lambda(z) = prod (1 - X_i z), whose roots are the
  /// inverses of the error locations. Reversing the coefficients gives the
  /// reciprocal polynomial prod (z - X_i), so a root at alpha^i names position
  /// i directly.
  List<int>? _errorPositions(Uint8List locator, int codewordLength) {
    final errors = locator.length - 1;
    final reciprocal = Uint8List(locator.length);
    for (var i = 0; i < locator.length; i++) {
      reciprocal[i] = locator[locator.length - 1 - i];
    }

    final positions = <int>[];
    for (var i = 0; i < codewordLength; i++) {
      if (_polyEval(reciprocal, _pow(2, i)) == 0) {
        positions.add(codewordLength - 1 - i);
      }
    }
    if (positions.length != errors) return null;
    return positions;
  }

  /// Forney: solve for each error magnitude and subtract it.
  ///
  /// Worked in lowest-degree-first form, and using the product form of the
  /// locator derivative, because both are far harder to get wrong than the
  /// equivalent index arithmetic.
  bool _correct(Uint8List codeword, List<int> syndromes, List<int> positions) {
    final n = codeword.length;
    final x = [
      for (final position in positions) _pow(2, n - 1 - position),
    ];

    // Lambda(z) = prod (1 - X_i z)
    var lambda = <int>[1];
    for (final xi in x) {
      final next = List<int>.filled(lambda.length + 1, 0);
      for (var i = 0; i < lambda.length; i++) {
        next[i] ^= lambda[i];
        next[i + 1] ^= _mul(lambda[i], xi);
      }
      lambda = next;
    }

    // Omega(z) = S(z) * Lambda(z) mod z^parity
    final omega = List<int>.filled(parityBytes, 0);
    for (var i = 0; i < syndromes.length; i++) {
      if (syndromes[i] == 0) continue;
      for (var j = 0; j < lambda.length && i + j < parityBytes; j++) {
        omega[i + j] ^= _mul(syndromes[i], lambda[j]);
      }
    }

    for (var i = 0; i < x.length; i++) {
      final xi = x[i];
      final xiInverse = _inverse(xi);

      var numerator = 0;
      for (var d = omega.length - 1; d >= 0; d--) {
        numerator = _mul(numerator, xiInverse) ^ omega[d];
      }

      // Subtraction is XOR, so `1 - a` is `1 ^ a`.
      //
      // This product is the formal derivative divided by X_i: for
      // Lambda(z) = prod (1 - X_j z) every term but one vanishes at
      // z = X_i^-1, leaving Lambda'(X_i^-1) = X_i * prod_{j!=i}(1 - X_j/X_i).
      // Forney's numerator carries a matching X_i, so the two cancel.
      var denominator = 1;
      for (var j = 0; j < x.length; j++) {
        if (j == i) continue;
        denominator = _mul(denominator, 1 ^ _mul(xiInverse, x[j]));
      }
      if (denominator == 0) return false;

      codeword[positions[i]] ^= _div(numerator, denominator);
    }
    return true;
  }
}
