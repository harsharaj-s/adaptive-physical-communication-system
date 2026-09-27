import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_bitmap.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/qr_frame_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:zxing2/qrcode.dart';

/// End-to-end optical pipeline with no device: real QR byte-mode encoding,
/// real rasterisation to a luminance frame, real zxing decoding, real LT
/// reassembly. This is what catches transport-level corruption — the kind a
/// codec-only unit test cannot see.
({int recovered, int decoded, int failed, int version, Uint8List? bytes})
    runOpticalRoundTrip({
  required Uint8List envelope,
  required OpticalTxProfile profile,
  double frameLoss = 0,
  int seed = 7,
  int moduleScale = 4,
}) {
  final sessionId = 0x5EED0000 + seed;
  final encoder = LtEncoder(
    data: envelope,
    blockLen: profile.blockLen,
    sessionId: sessionId,
  );
  final decoder = LtDecoder(
    K: encoder.K,
    blockLen: encoder.blockLen,
    fileLen: encoder.fileLen,
    sessionId: sessionId,
  );

  final rng = Random(seed);
  var decoded = 0;
  var failed = 0;
  var version = 0;
  Uint8List? result;

  // Rateless: mint fresh symbols until reassembly completes.
  final budget = (encoder.K * 3).ceil() + 40;
  for (var symbolIndex = 0; symbolIndex < budget; symbolIndex++) {
    if (frameLoss > 0 && rng.nextDouble() < frameLoss) continue;

    final frameBytes = qrFountainFrameCodec.encode(
      QrFountainFrame(
        sessionId: sessionId,
        symbolIndex: symbolIndex,
        k: encoder.K,
        blockLen: encoder.blockLen,
        fileLen: encoder.fileLen,
        payload: encoder.symbolAt(symbolIndex),
      ),
    );

    final bitmap = buildQrBitmap(
      frameBytes,
      errorCorrectLevel: QrErrorCorrectLevel.L,
      maskPattern: 0,
    );
    version = bitmap.typeNumber;

    final raster = rasterizeQrBitmap(bitmap, moduleScale: moduleScale);
    final seen = decodeQrBytesFromLuminance(
      raster.width,
      raster.height,
      raster.lum,
    );
    if (seen == null) {
      failed++;
      continue;
    }
    decoded++;

    final parsed = qrFountainFrameCodec.decodeFromQrBytes(seen);
    expect(parsed, isNotNull, reason: 'frame $symbolIndex failed to parse');
    expect(parsed!.sessionId, sessionId);
    expect(parsed.symbolIndex, symbolIndex);

    decoder.addSymbol(parsed.symbolIndex, parsed.payload);
    if (decoder.isComplete) {
      result = decoder.takeBytes();
      break;
    }
  }

  return (
    recovered: decoder.recoveredCount,
    decoded: decoded,
    failed: failed,
    version: version,
    bytes: result,
  );
}

/// Decode using only finder-pattern detection — no pure-barcode rescue.
bool _decodesWithFinderSearch(({int width, int height, Int8List lum}) raster) {
  final source = RGBLuminanceSource.crop(
    raster.lum,
    raster.width,
    raster.height,
    0,
    0,
    raster.width,
    raster.height,
  );
  final hints = DecodeHints()
    ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode]);
  try {
    QRCodeReader().decode(
      BinaryBitmap(GlobalHistogramBinarizer(source)),
      hints: hints,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Uint8List _pseudoMedia(int length, int seed) {
  final rng = Random(seed);
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

void main() {
  group('optical round trip (QR byte mode + zxing + LT)', () {
    test('text message survives the full pipeline', () {
      final envelope = ChatPayloadCodec.encodeText(
        'Light channel check: fountain QR carries raw bytes end to end. '
        'No base64, no UTF-8 mangling, no lost payload.',
      );

      final run = runOpticalRoundTrip(
        envelope: envelope,
        profile: OpticalTxProfile.standard,
      );

      expect(run.failed, 0, reason: 'every rendered QR must decode');
      expect(run.bytes, isNotNull);
      expect(run.bytes, equals(envelope));
      expect(ChatPayloadCodec.isApcmEnvelope(run.bytes!), isTrue);
    });

    test('photo survives with 30% of frames dropped', () {
      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.image,
        data: _pseudoMedia(40 * 1024, 11),
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
      );

      final run = runOpticalRoundTrip(
        envelope: envelope,
        profile: OpticalTxProfile.standard,
        frameLoss: 0.30,
        seed: 11,
      );

      expect(run.failed, 0);
      expect(
        run.bytes,
        isNotNull,
        reason: 'recovered ${run.recovered} symbols, decoded ${run.decoded}',
      );
      expect(run.bytes, equals(envelope));
    });

    test('video survives with 30% of frames dropped', () {
      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.video,
        data: _pseudoMedia(30 * 1024, 23),
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
      );

      final run = runOpticalRoundTrip(
        envelope: envelope,
        profile: OpticalTxProfile.standard,
        frameLoss: 0.30,
        seed: 23,
      );

      expect(run.bytes, isNotNull, reason: 'recovered ${run.recovered}');
      expect(run.bytes, equals(envelope));
    });

    test('every profile stays within a camera-readable QR version', () {
      for (final profile in OpticalTxProfile.values) {
        final run = runOpticalRoundTrip(
          envelope: ChatPayloadCodec.encode(
            type: ChatMessageType.file,
            data: _pseudoMedia(8 * 1024, 5),
            fileName: 'blob.bin',
          ),
          profile: profile,
        );

        expect(run.bytes, isNotNull, reason: '${profile.label} failed');
        expect(run.failed, 0, reason: '${profile.label} had undecodable QRs');
        // Version 25 is 117 modules; denser than that smears on a phone
        // screen at arm's length.
        expect(
          run.version,
          lessThanOrEqualTo(25),
          reason: '${profile.label} needs QR v${run.version} '
              '(${profile.framedSymbolBytes} B per frame)',
        );
        // ignore: avoid_print
        print('${profile.label.padRight(9)} '
            'block=${profile.blockLen} framed=${profile.framedSymbolBytes}B '
            'QRv${run.version} (${run.version * 4 + 17} modules) '
            'K=${run.recovered} decoded=${run.decoded}');
      }
    });

    test('production decoder reads every rendered frame', () {
      // Finder-pattern detection alone loses 3-8% of frames at every QR
      // version, because random payload bytes can form 1:1:3:1:1 runs that
      // outrank the real corners. The pure-barcode rescue in the decoder
      // recovers all of them. This guards that rescue: without it the
      // finder-only column below is what the channel would actually lose.
      for (final profile in OpticalTxProfile.values) {
        var failed = 0;
        var finderOnlyFailed = 0;
        var total = 0;
        var version = 0;

        for (var seed = 0; seed < 3; seed++) {
          final sessionId = 0xB10C0 + seed;
          final enc = LtEncoder(
            data: _pseudoMedia(32 * 1024, seed * 31 + 3),
            blockLen: profile.blockLen,
            sessionId: sessionId,
          );
          for (var i = 0; i < 50; i++) {
            final bitmap = buildQrBitmap(
              qrFountainFrameCodec.encode(
                QrFountainFrame(
                  sessionId: sessionId,
                  symbolIndex: i,
                  k: enc.K,
                  blockLen: enc.blockLen,
                  fileLen: enc.fileLen,
                  payload: enc.symbolAt(i),
                ),
              ),
              errorCorrectLevel: QrErrorCorrectLevel.L,
              maskPattern: 0,
            );
            version = bitmap.typeNumber;
            final raster = rasterizeQrBitmap(bitmap, moduleScale: 4);
            total++;
            if (!_decodesWithFinderSearch(raster)) finderOnlyFailed++;
            final bytes = decodeQrBytesFromLuminance(
              raster.width,
              raster.height,
              raster.lum,
            );
            if (bytes == null) failed++;
          }
        }

        // ignore: avoid_print
        print('${profile.label.padRight(9)} QRv$version '
            '(${version * 4 + 17} modules) n=$total '
            'finder-only loss ${(finderOnlyFailed / total * 100).toStringAsFixed(1)}% '
            '-> decoder loss ${(failed / total * 100).toStringAsFixed(1)}%');

        expect(
          failed / total,
          lessThan(0.01),
          reason: '${profile.label} loses $failed of $total frames; the '
              'pure-barcode rescue path is no longer covering finder '
              'detection misses',
        );
      }
    });

    test('binary payloads that look like text are not mangled', () {
      // Bytes that are invalid UTF-8 and include NUL / 0xFF runs — exactly
      // what broke the old base64-over-string transport.
      final hostile = Uint8List.fromList([
        for (var i = 0; i < 2048; i++) [0x00, 0xFF, 0xC0, 0x80, 0xED, 0xA0][i % 6],
      ]);
      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.file,
        data: hostile,
        fileName: 'hostile.bin',
      );

      final run = runOpticalRoundTrip(
        envelope: envelope,
        profile: OpticalTxProfile.safe,
      );

      expect(run.bytes, equals(envelope));
    });
  });
}
