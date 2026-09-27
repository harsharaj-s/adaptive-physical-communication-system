import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LtCodec', () {
    test('systematic path recovers with exactly K symbols', () {
      final data = Uint8List.fromList(
        List.generate(5000, (i) => i & 0xFF),
      );
      const blockLen = 200;
      final session = 0xABCDEF01;
      final enc = LtEncoder(data: data, blockLen: blockLen, sessionId: session);
      final dec = LtDecoder(
        K: enc.K,
        blockLen: blockLen,
        fileLen: enc.fileLen,
        sessionId: session,
      );

      for (var i = 0; i < enc.K; i++) {
        expect(dec.addSymbol(i, enc.symbolAt(i)), isTrue);
      }
      expect(dec.isComplete, isTrue);
      expect(dec.takeBytes(), orderedEquals(data));
    });

    test('recovers with 30% random erasures using repair symbols', () {
      final data = Uint8List.fromList(
        List.generate(12000, (i) => (i * 17) & 0xFF),
      );
      const blockLen = 250;
      final session = 42;
      final enc = LtEncoder(data: data, blockLen: blockLen, sessionId: session);
      final dec = LtDecoder(
        K: enc.K,
        blockLen: blockLen,
        fileLen: enc.fileLen,
        sessionId: session,
      );

      final rng = Random(7);
      final total = (enc.K * 1.6).ceil() + 20;
      for (var i = 0; i < total; i++) {
        if (rng.nextDouble() < 0.30) continue; // erasure
        dec.addSymbol(i, enc.symbolAt(i));
        if (dec.isComplete) break;
      }
      expect(dec.isComplete, isTrue);
      expect(dec.takeBytes(), orderedEquals(data));
    });

    test('duplicate symbols are ignored', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final enc = LtEncoder(data: data, blockLen: 4, sessionId: 1);
      final dec = LtDecoder(
        K: enc.K,
        blockLen: 4,
        fileLen: enc.fileLen,
        sessionId: 1,
      );
      expect(dec.addSymbol(0, enc.symbolAt(0)), isTrue);
      expect(dec.addSymbol(0, enc.symbolAt(0)), isFalse);
      expect(dec.duplicateSymbols, 1);
    });
  });

  group('QrFountainFrameCodec', () {
    test('round-trips and verifies CRC', () {
      final payload = Uint8List.fromList(List.generate(64, (i) => i));
      final frame = QrFountainFrame(
        sessionId: 0x11223344,
        symbolIndex: 9,
        k: 10,
        blockLen: 64,
        fileLen: 600,
        payload: payload,
      );
      final bytes = qrFountainFrameCodec.encode(frame);
      final parsed = qrFountainFrameCodec.decode(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, frame.sessionId);
      expect(parsed.symbolIndex, frame.symbolIndex);
      expect(parsed.payload, orderedEquals(payload));
    });

    test('rejects corrupted CRC', () {
      final frame = QrFountainFrame(
        sessionId: 1,
        symbolIndex: 0,
        k: 1,
        blockLen: 8,
        fileLen: 8,
        payload: Uint8List(8),
      );
      final bytes = qrFountainFrameCodec.encode(frame);
      bytes[bytes.length - 1] ^= 0xFF;
      expect(qrFountainFrameCodec.decode(bytes), isNull);
    });

    test('binary frame round-trips through the raw QR byte path', () {
      final frame = QrFountainFrame(
        sessionId: createSessionId(),
        symbolIndex: 7,
        k: 9,
        blockLen: 48,
        fileLen: 400,
        // Bytes that are invalid UTF-8, to prove nothing re-encodes them.
        payload: Uint8List.fromList(
          List.generate(48, (i) => [0x00, 0xFF, 0xC0, 0xED][i % 4]),
        ),
      );
      final wire = qrFountainFrameCodec.encode(frame);
      final parsed = qrFountainFrameCodec.decodeFromQrBytes(wire);
      expect(parsed, isNotNull);
      expect(parsed!.payload, orderedEquals(frame.payload));
      expect(parsed.symbolIndex, 7);
    });

    test('trailing QR padding after the frame is tolerated', () {
      final frame = QrFountainFrame(
        sessionId: 1234,
        symbolIndex: 2,
        k: 3,
        blockLen: 24,
        fileLen: 60,
        payload: Uint8List.fromList(List.generate(24, (i) => i * 3)),
      );
      final padded = Uint8List(qrFountainOverhead + 24 + 6)
        ..setRange(0, qrFountainOverhead + 24, qrFountainFrameCodec.encode(frame));
      final parsed = qrFountainFrameCodec.decode(padded);
      expect(parsed, isNotNull);
      expect(parsed!.payload, orderedEquals(frame.payload));
    });

    test('qr string path round-trips via FQR3 base64', () {
      final frame = QrFountainFrame(
        sessionId: createSessionId(),
        symbolIndex: 3,
        k: 5,
        blockLen: 32,
        fileLen: 100,
        payload: Uint8List.fromList(List.generate(32, (i) => 200 + i)),
      );
      final s = qrFountainFrameCodec.encodeToQrString(frame);
      expect(s.startsWith(qrFountainQrPrefix), isTrue);
      // The web sampler can only read text, so this path must stay ASCII.
      expect(s.codeUnits.every((c) => c < 128), isTrue);
      final parsed = qrFountainFrameCodec.decodeFromQrString(s);
      expect(parsed, isNotNull);
      expect(parsed!.payload, orderedEquals(frame.payload));
    });

    test('decodeFromQrBytes accepts FQR3 utf8 bytes', () {
      final frame = QrFountainFrame(
        sessionId: 99,
        symbolIndex: 1,
        k: 2,
        blockLen: 16,
        fileLen: 20,
        payload: Uint8List.fromList(List.generate(16, (i) => i + 1)),
      );
      final s = qrFountainFrameCodec.encodeToQrString(frame);
      final bytes = Uint8List.fromList(utf8.encode(s));
      final parsed = qrFountainFrameCodec.decodeFromQrBytes(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.payload, orderedEquals(frame.payload));
    });
  });
}
