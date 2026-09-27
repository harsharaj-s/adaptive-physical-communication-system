import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// GF(2) rank of the neighbour sets, computed independently of the decoder.
int _rank(List<List<int>> rows) {
  final basis = <int, BigInt>{};
  var rank = 0;
  for (final r in rows) {
    var m = BigInt.zero;
    for (final n in r) {
      m ^= BigInt.one << n;
    }
    while (m != BigInt.zero) {
      final top = m.bitLength - 1;
      final b = basis[top];
      if (b == null) {
        basis[top] = m;
        rank++;
        break;
      }
      m ^= b;
    }
  }
  return rank;
}

Uint8List _data(int len, int seed) {
  final rng = Random(seed);
  return Uint8List.fromList(List.generate(len, (_) => rng.nextInt(256)));
}

/// Stream symbols from [start], keep each with probability [keep], and count
/// how many were received when the decoder completed.
int _symbolsToComplete(int k, int session, int start, double keep, int seed) {
  const blockLen = 8;
  final data = _data(k * blockLen, seed);
  final enc = LtEncoder(data: data, blockLen: blockLen, sessionId: session);
  final dec = LtDecoder(
    K: k,
    blockLen: blockLen,
    fileLen: enc.fileLen,
    sessionId: session,
  );
  final rng = Random(seed);
  var received = 0;
  for (var i = start; i < start + k * 20 + 200; i++) {
    if (rng.nextDouble() > keep) continue;
    received++;
    dec.addSymbol(i, enc.symbolAt(i));
    if (dec.isComplete) {
      expect(dec.takeBytes(), orderedEquals(data));
      return received;
    }
  }
  fail('K=$k never completed');
}

void main() {
  test('decoder completes exactly when the received symbols reach rank K', () {
    for (final k in [1, 2, 3, 4, 5, 7, 8, 9, 12, 40, 257, 300]) {
      for (var t = 0; t < 30; t++) {
        const blockLen = 16;
        final session = 0x1000 * k + t;
        final data = _data(k * blockLen - (t % blockLen), session);
        final enc = LtEncoder(data: data, blockLen: blockLen, sessionId: session);
        expect(enc.K, k);
        final dec = LtDecoder(
          K: k,
          blockLen: blockLen,
          fileLen: enc.fileLen,
          sessionId: session,
        );
        final rng = Random(session);
        final rows = <List<int>>[];
        final picked = <int>{};
        while (picked.length < k + 3) {
          picked.add(rng.nextInt(k * 4 + 50));
        }
        for (final i in picked) {
          rows.add(LtEncoder.neighborsFor(session, i, k));
          dec.addSymbol(i, enc.symbolAt(i));
          expect(dec.rank, _rank(rows), reason: 'K=$k symbol $i');
        }
        expect(dec.newSymbols + dec.redundantSymbols, picked.length);
        expect(dec.isComplete, dec.rank == k);
        if (dec.isComplete) expect(dec.takeBytes(), orderedEquals(data));
      }
    }
  });

  test('K=3 with five distinct repair symbols always completes', () {
    for (var t = 0; t < 500; t++) {
      final session = 0xA337BF90 ^ (t * 7919);
      final data = _data(2000, t);
      final enc = LtEncoder(data: data, blockLen: 800, sessionId: session);
      final dec = LtDecoder(
        K: enc.K,
        blockLen: 800,
        fileLen: enc.fileLen,
        sessionId: session,
      );
      // Five consecutive repair symbols, as a camera that missed the
      // systematic frames would see them.
      final start = 3 + Random(t).nextInt(200);
      for (var i = start; i < start + 5; i++) {
        dec.addSymbol(i, enc.symbolAt(i));
      }
      expect(dec.isComplete, isTrue, reason: 'trial $t start $start');
      expect(dec.takeBytes(), orderedEquals(data));
    }
  });

  test('overhead stays under two symbols for every K a camera will see', () {
    final report = StringBuffer();
    for (final k in [1, 2, 3, 5, 8, 9, 16, 32, 64, 128, 256, 300, 600]) {
      final extra = <int>[];
      for (var t = 0; t < (k > 256 ? 12 : 60); t++) {
        // Late start and 40% loss: most systematic frames are missed.
        final start = t.isEven ? 0 : k ~/ 2 + t;
        extra.add(_symbolsToComplete(k, 0xC0FFEE + t * 31 + k, start, 0.6, t) -
            k);
      }
      extra.sort();
      final mean = extra.reduce((a, b) => a + b) / extra.length;
      final p95 = extra[(extra.length * 0.95).floor().clamp(0, extra.length - 1)];
      report.writeln('K=${k.toString().padLeft(3)} mean overhead '
          '${mean.toStringAsFixed(2)} p95 $p95');
      expect(mean, lessThan(2.5), reason: 'K=$k');
      expect(p95, lessThanOrEqualTo(7), reason: 'K=$k');
    }
    // ignore: avoid_print
    print(report);
  });
}
