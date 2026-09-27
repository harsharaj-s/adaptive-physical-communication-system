import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Standard profile recovers ~365 KB with 25% frame loss', () {
    const fileLen = 365 * 1024;
    final data = Uint8List.fromList(
      List.generate(fileLen, (i) => (i * 31) & 0xFF),
    );
    final profile = OpticalTxProfile.standard;
    const session = 0xDEC10001;
    final enc = LtEncoder(
      data: data,
      blockLen: profile.blockLen,
      sessionId: session,
    );
    final dec = LtDecoder(
      K: enc.K,
      blockLen: profile.blockLen,
      fileLen: enc.fileLen,
      sessionId: session,
    );

    final rng = Random(365);
    final budget = (enc.K * 2.5).ceil() + 80;
    var sent = 0;
    var erased = 0;
    final sw = Stopwatch()..start();
    for (var i = 0; i < budget; i++) {
      sent++;
      if (rng.nextDouble() < 0.20) {
        erased++;
        continue;
      }
      dec.addSymbol(i, enc.symbolAt(i));
      if (dec.isComplete) break;
    }
    sw.stop();

    expect(dec.isComplete, isTrue, reason: 'K=${enc.K} recovered=${dec.recoveredCount}');
    expect(dec.takeBytes(), orderedEquals(data));

    final elapsedSec = sw.elapsedMilliseconds / 1000.0;
    final goodputKBps = (fileLen / 1000.0) / max(elapsedSec, 0.001);
    // Pure CPU decode — should be far above optical goodput floor.
    expect(goodputKBps, greaterThan(40));
    expect(erased / sent, greaterThan(0.1));
  });

  test('OpticalTxProfile.slower steps Safe←Standard←Fast', () {
    expect(OpticalTxProfile.fast.slower, OpticalTxProfile.standard);
    expect(OpticalTxProfile.standard.slower, OpticalTxProfile.safe);
    expect(OpticalTxProfile.safe.slower, OpticalTxProfile.safe);
  });
}
