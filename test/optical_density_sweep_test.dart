import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/fountain_qr_modem.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_bitmap.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/qr_frame_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'optical_camera_sim.dart';

/// Fountain QRs through a simulated phone camera (see optical_camera_sim).
///
/// The full density table is slow (minutes), so it only runs on request:
///   $env:OPTICAL_SWEEP=1; flutter test test/optical_density_sweep_test.dart
({double rate, double msPerFrame, int version}) measure({
  required int blockLen,
  required CameraDegradation d,
  int frames = 16,
  int seed = 1,
}) {
  final rng = Random(seed * 7919 + blockLen);
  final session = 0x0D5E0000 + blockLen;
  final data = Uint8List.fromList(
    List.generate(blockLen * 40, (_) => rng.nextInt(256)),
  );
  final enc = LtEncoder(data: data, blockLen: blockLen, sessionId: session);
  var ok = 0;
  var version = 0;
  final sw = Stopwatch();
  for (var i = 0; i < frames; i++) {
    final symbol = 50 + i;
    final bitmap = _symbolBitmap(enc, symbol);
    version = bitmap.typeNumber;
    final frame = renderCameraFrame(bitmap, d, rng);
    sw.start();
    final bytes = decodeQrBytesFromLuminance(
      frame.width,
      frame.height,
      frame.lum,
    );
    sw.stop();
    if (bytes == null) continue;
    final parsed = qrFountainFrameCodec.decodeFromQrBytes(bytes);
    expect(parsed, isNotNull, reason: 'RS-checked decode must parse');
    expect(parsed!.symbolIndex, symbol);
    ok++;
  }
  return (
    rate: ok / frames,
    msPerFrame: sw.elapsedMilliseconds / frames,
    version: version,
  );
}

QrBitmap _symbolBitmap(LtEncoder enc, int symbol) => buildQrBitmap(
      qrFountainFrameCodec.encode(
        QrFountainFrame(
          sessionId: enc.sessionId,
          symbolIndex: symbol,
          k: enc.K,
          blockLen: enc.blockLen,
          fileLen: enc.fileLen,
          payload: enc.symbolAt(symbol),
        ),
      ),
      errorCorrectLevel: QrErrorCorrectLevel.L,
      maskPattern: 0,
    );

/// Stream [envelope] as the sender would (profile resolved from its size,
/// content-derived session), capture every frame through [d] with
/// [frameLoss] torn/missed frames, and count frames until the file is back.
({int shown, int decoded, int k, int blockLen, Uint8List? bytes}) streamThroughCamera({
  required Uint8List envelope,
  required OpticalTxProfile profile,
  required CameraDegradation d,
  double frameLoss = 0.3,
  int seed = 1,
  int maxFrames = 400,
}) {
  final tx = profile.resolveFor(envelope.length);
  final session = FountainQrModem.sessionIdFor(envelope, tx.blockLen);
  final enc = LtEncoder(data: envelope, blockLen: tx.blockLen, sessionId: session);
  final dec = LtDecoder(
    K: enc.K,
    blockLen: enc.blockLen,
    fileLen: enc.fileLen,
    sessionId: session,
  );
  final rng = Random(seed);
  var decoded = 0;
  for (var i = 0; i < maxFrames; i++) {
    if (rng.nextDouble() < frameLoss) continue;
    final frame = renderCameraFrame(_symbolBitmap(enc, i), d, rng);
    final bytes = decodeQrBytesFromLuminance(frame.width, frame.height, frame.lum);
    if (bytes == null) continue;
    final parsed = qrFountainFrameCodec.decodeFromQrBytes(bytes);
    if (parsed == null) continue;
    decoded++;
    dec.addSymbol(parsed.symbolIndex, parsed.payload);
    if (dec.isComplete) {
      return (
        shown: i + 1,
        decoded: decoded,
        k: enc.K,
        blockLen: enc.blockLen,
        bytes: dec.takeBytes(),
      );
    }
  }
  return (shown: maxFrames, decoded: decoded, k: enc.K, blockLen: enc.blockLen, bytes: null);
}

Uint8List _media(int len, int seed) {
  final rng = Random(seed);
  return Uint8List.fromList(List.generate(len, (_) => rng.nextInt(256)));
}

const sweepBlocks = [100, 160, 240, 330, 430, 600, 800, 1200];

void main() {
  group('optical density through a simulated camera', () {
    test('Auto keeps small payloads on sparse QR versions', () {
      expect(OpticalTxProfile.auto.resolveFor(300).blockLen, 160);
      expect(OpticalTxProfile.auto.resolveFor(2 * 1024).blockLen, 160);
      expect(OpticalTxProfile.auto.resolveFor(10 * 1024).blockLen, 240);
      expect(OpticalTxProfile.auto.resolveFor(15 * 1024).blockLen, 330);
      expect(OpticalTxProfile.auto.resolveFor(200 * 1024).blockLen, 330);
      expect(OpticalTxProfile.standard.resolveFor(300).blockLen, 330);
      // A 2 KB file used to need QR v20; now it is v8.
      final enc = LtEncoder(
        data: _media(2048, 1),
        blockLen: OpticalTxProfile.auto.resolveFor(2048).blockLen,
        sessionId: 1,
      );
      expect(_symbolBitmap(enc, 20).typeNumber, lessThanOrEqualTo(8));
    });

    test('Auto ladder decodes reliably at the field-report pose', () {
      // "typical" = QR at half the camera view, hand-held (screenshot 1).
      final floors = {160: 0.9, 240: 0.8, 330: 0.6};
      for (final e in floors.entries) {
        final r = measure(blockLen: e.key, d: CameraDegradation.typical, frames: 12);
        // ignore: avoid_print
        print('typical ${e.key} B QRv${r.version}: '
            '${(r.rate * 100).round()}% decoded, ${r.msPerFrame.round()} ms/frame');
        expect(r.rate, greaterThanOrEqualTo(e.value), reason: '${e.key} B');
      }
      // The old Standard density, for contrast: most frames are lost.
      final old = measure(blockLen: 800, d: CameraDegradation.typical, frames: 12);
      // ignore: avoid_print
      print('typical 800 B QRv${old.version} (old default): '
          '${(old.rate * 100).round()}% decoded');
      expect(old.rate, lessThan(0.5));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('2 KB file completes through a hand-held camera with 30% frame loss', () {
      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.file,
        data: _media(2000, 42),
        fileName: 'notes.txt',
      );
      final run = streamThroughCamera(
        envelope: envelope,
        profile: OpticalTxProfile.auto,
        d: CameraDegradation.typical,
      );
      // ignore: avoid_print
      print('2 KB typical: K=${run.k} block=${run.blockLen} done after '
          '${run.shown} frames shown (${run.decoded} decoded) '
          '≈ ${(run.shown / 12).toStringAsFixed(1)} s at 12 fps');
      expect(run.bytes, equals(envelope));
      expect(run.shown, lessThan(run.k * 2 + 12));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('2 KB file still completes when the camera is too far and shaky', () {
      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.file,
        data: _media(2000, 43),
        fileName: 'notes.txt',
      );
      final run = streamThroughCamera(
        envelope: envelope,
        profile: OpticalTxProfile.auto,
        d: CameraDegradation.hard.zoomed(1.5),
        seed: 2,
      );
      // ignore: avoid_print
      print('2 KB hard x1.5: K=${run.k} done after ${run.shown} frames shown '
          '(${run.decoded} decoded) ≈ ${(run.shown / 12).toStringAsFixed(1)} s');
      expect(run.bytes, equals(envelope));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('full density table', () {
      final out = StringBuffer('\nblock  QRv  ');
      final tiers = [
        ...CameraDegradation.tiers,
        CameraDegradation.hard.zoomed(1.5),
      ];
      for (final d in tiers) {
        out.write(d.label.padRight(16));
      }
      out.writeln();
      for (final block in sweepBlocks) {
        final cells = <String>[];
        var version = 0;
        for (final d in tiers) {
          final r = measure(blockLen: block, d: d);
          version = r.version;
          cells.add('${(r.rate * 100).toStringAsFixed(0).padLeft(3)}% '
              '${r.msPerFrame.toStringAsFixed(0).padLeft(4)}ms   ');
        }
        out.writeln('${block.toString().padLeft(5)}  '
            'v${version.toString().padRight(3)} ${cells.join()}');
      }
      // ignore: avoid_print
      print(out);
    },
        skip: Platform.environment['OPTICAL_SWEEP'] == null
            ? 'set OPTICAL_SWEEP=1 to print the full table'
            : null,
        timeout: const Timeout(Duration(minutes: 30)));
  });
}
