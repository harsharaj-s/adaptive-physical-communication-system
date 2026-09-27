import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/acoustic/reed_solomon.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List randomBytes(int n, Random rng) =>
    Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

void main() {
  group('ReedSolomon', () {
    test('clean codeword decodes unchanged', () {
      final rng = Random(1);
      final rs = ReedSolomon(16);
      for (var length = 1; length <= 100; length += 7) {
        final data = randomBytes(length, rng);
        final codeword = rs.encode(data);
        expect(codeword.length, length + 16);
        expect(rs.decode(codeword), orderedEquals(data));
      }
    });

    test('repairs up to the correctable limit, every position', () {
      final rng = Random(2);
      for (final parity in [4, 8, 16, 32]) {
        final rs = ReedSolomon(parity);
        final limit = rs.correctableBytes;
        for (var trial = 0; trial < 60; trial++) {
          final data = randomBytes(60, rng);
          final codeword = rs.encode(data);
          final damaged = Uint8List.fromList(codeword);

          final positions = <int>{};
          while (positions.length < limit) {
            positions.add(rng.nextInt(damaged.length));
          }
          for (final p in positions) {
            // Guarantee an actual change.
            damaged[p] ^= 1 + rng.nextInt(255);
          }

          expect(
            rs.decode(damaged),
            orderedEquals(data),
            reason: 'parity=$parity failed to repair $limit errors '
                'at ${positions.toList()}',
          );
        }
      }
    });

    test('errors in parity bytes are repaired too', () {
      final rng = Random(3);
      final rs = ReedSolomon(20);
      final data = randomBytes(40, rng);
      final codeword = rs.encode(data);
      final damaged = Uint8List.fromList(codeword);
      for (var i = 0; i < 10; i++) {
        damaged[40 + i] ^= 0xA5;
      }
      expect(rs.decode(damaged), orderedEquals(data));
    });

    test('rejects damage beyond the limit rather than returning garbage', () {
      final rng = Random(4);
      final rs = ReedSolomon(8); // corrects 4
      var wrongAccepted = 0;
      const trials = 400;
      for (var trial = 0; trial < trials; trial++) {
        final data = randomBytes(50, rng);
        final codeword = rs.encode(data);
        final damaged = Uint8List.fromList(codeword);
        final positions = <int>{};
        while (positions.length < 9) {
          positions.add(rng.nextInt(damaged.length));
        }
        for (final p in positions) {
          damaged[p] ^= 1 + rng.nextInt(255);
        }
        final got = rs.decode(damaged);
        // Either a clean refusal, or (very rarely) a valid nearby codeword.
        if (got != null && !_equal(got, data)) wrongAccepted++;
      }
      // Undetected miscorrection must stay rare; the frame CRC catches the rest.
      expect(wrongAccepted / trials, lessThan(0.05),
          reason: '$wrongAccepted of $trials decoded to the wrong payload');
    });

    test('burst errors are repaired', () {
      final rng = Random(5);
      final rs = ReedSolomon(24); // corrects 12
      final data = randomBytes(80, rng);
      final codeword = rs.encode(data);
      final damaged = Uint8List.fromList(codeword);
      for (var i = 30; i < 42; i++) {
        damaged[i] = rng.nextInt(256);
      }
      expect(rs.decode(damaged), orderedEquals(data));
    });

    test('single byte payload and maximum payload both work', () {
      final rng = Random(6);
      final rs = ReedSolomon(10);
      final tiny = randomBytes(1, rng);
      final tinyWord = rs.encode(tiny);
      tinyWord[0] ^= 0xFF;
      expect(rs.decode(tinyWord), orderedEquals(tiny));

      final big = randomBytes(rs.maxDataLength(), rng);
      final bigWord = rs.encode(big);
      bigWord[100] ^= 0x33;
      bigWord[7] ^= 0x91;
      expect(rs.decode(bigWord), orderedEquals(big));
    });

    test('rejects a codeword of the wrong length', () {
      final rs = ReedSolomon(8);
      expect(rs.decode(Uint8List(4)), isNull);
    });

    test('repairs errors plus erasures whenever 2e + f fits the parity', () {
      final rng = Random(7);
      for (final parity in [4, 8, 16, 20, 24]) {
        final rs = ReedSolomon(parity);
        for (var errors = 0; errors * 2 <= parity; errors++) {
          final erasureCount = parity - 2 * errors;
          for (var trial = 0; trial < 25; trial++) {
            final data = randomBytes(50, rng);
            final damaged = Uint8List.fromList(rs.encode(data));
            final chosen = <int>{};
            while (chosen.length < errors + erasureCount) {
              chosen.add(rng.nextInt(damaged.length));
            }
            final picks = chosen.toList();
            final erased = picks.sublist(0, erasureCount);
            for (final p in picks) {
              damaged[p] ^= 1 + rng.nextInt(255);
            }
            // Some flagged bytes are left intact, as a real receiver's
            // suspicion is not always right.
            if (erased.isNotEmpty && trial.isEven) {
              damaged[erased.first] = rs.encode(data)[erased.first];
            }

            expect(
              rs.decode(damaged, erasures: erased),
              orderedEquals(data),
              reason: 'parity=$parity errors=$errors erasures=$erasureCount',
            );
          }
        }
      }
    });

    test('erasures double how many known-bad bytes can be fixed', () {
      final rng = Random(8);
      final rs = ReedSolomon(20); // 10 errors, or 20 erasures
      final data = randomBytes(40, rng);
      final damaged = Uint8List.fromList(rs.encode(data));
      final positions = List<int>.generate(18, (i) => i * 3);
      for (final p in positions) {
        damaged[p] ^= 0x5A;
      }
      expect(rs.decode(damaged), isNull);
      expect(rs.decode(damaged, erasures: positions), orderedEquals(data));
    });
  });
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
