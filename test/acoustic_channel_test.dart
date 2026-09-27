import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_frame_sync.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acoustic_channel_sim.dart';

/// Modulate a run of fountain symbols into one continuous waveform.
Float32List transmit({
  required AcousticTxProfile profile,
  required LtEncoder encoder,
  required int sessionId,
  required int firstSymbol,
  required int symbolCount,
}) {
  final codec = profile.buildCodec();
  final frameCodec = profile.buildFrameCodec();
  final chunks = <Float32List>[];
  for (var i = 0; i < symbolCount; i++) {
    final index = firstSymbol + i;
    final codeword = frameCodec.encode(
      AcousticFrame(
        sessionId: sessionId,
        symbolIndex: index,
        k: encoder.K,
        blockLen: encoder.blockLen,
        fileLen: encoder.fileLen,
        payload: encoder.symbolAt(index),
      ),
    );
    chunks.add(codec.encode(codeword));
  }
  final total = chunks.fold<int>(0, (a, c) => a + c.length);
  final out = Float32List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return out;
}

/// Run a whole transfer and report what got through.
({
  bool recovered,
  int framesSent,
  int framesDecoded,
  double seconds,
  double netBytesPerSecond,
}) runTransfer({
  required AcousticTxProfile profile,
  required Uint8List envelope,
  required AcousticScenario scenario,
  int seed = 3,
  double symbolBudget = 3.0,
}) {
  const sessionId = 0x5A;
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
  final sync = AcousticFrameSync(profile: profile);

  // The sender is rateless, so send in small bursts until the receiver is
  // done. Keeping the burst short makes the reported time reflect when the
  // payload actually became decodable rather than a burst boundary.
  const burst = 2;
  var nextSymbol = 0;
  var framesSent = 0;
  var samplesSent = 0;
  final maxSymbols = (encoder.K * symbolBudget).ceil() + 24;

  while (nextSymbol < maxSymbols && !decoder.isComplete) {
    final clean = transmit(
      profile: profile,
      encoder: encoder,
      sessionId: sessionId,
      firstSymbol: nextSymbol,
      symbolCount: burst,
    );
    final heard = simulateAcoustic(
      clean,
      scenario: scenario,
      seed: seed + nextSymbol,
      leadSilence: 1200 + (nextSymbol * 37) % 900,
    );
    // Feed it in mic-sized chunks so the streaming path is what gets tested.
    for (var at = 0; at < heard.length; at += 2048) {
      final end = at + 2048 > heard.length ? heard.length : at + 2048;
      sync.addSamples(Float32List.sublistView(heard, at, end));
    }
    for (final frame in sync.takeFrames()) {
      if (frame.sessionId != sessionId) continue;
      decoder.addSymbol(frame.symbolIndex, frame.payload);
    }
    framesSent += burst;
    samplesSent += clean.length;
    nextSymbol += burst;
  }

  final recovered = decoder.isComplete ? decoder.takeBytes() : null;
  final seconds = samplesSent / 44100;
  return (
    recovered: recovered != null && _equal(recovered, envelope),
    framesSent: framesSent,
    framesDecoded: sync.framesRepaired,
    seconds: seconds,
    netBytesPerSecond: seconds > 0 ? envelope.length / seconds : 0,
  );
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('acoustic profiles', () {
    test('advertised rates and frame geometry', () {
      for (final profile in AcousticTxProfile.values) {
        final codec = profile.buildCodec();
        // ignore: avoid_print
        print('${profile.label.padRight(9)} '
            '${profile.groups} tones x ${profile.framesPerSymbol} frames  '
            'sym=${codec.symbolMs.toStringAsFixed(0).padLeft(3)}ms  '
            'block=${profile.blockLen}B parity=${profile.parityBytes}B '
            '(corrects ${profile.buildFrameCodec().correctableBytes}) '
            'frame=${profile.frameSeconds().toStringAsFixed(2)}s  '
            'net=${profile.netBytesPerSecond().toStringAsFixed(1)}B/s');
        expect(profile.netBytesPerSecond(), greaterThan(7.0),
            reason: '${profile.label} must beat the old single-bit FSK');
      }
    });

    test('frame recovery rate per scenario', () {
      for (final profile in AcousticTxProfile.values) {
        final line = StringBuffer('${profile.label.padRight(9)} ');
        for (final scenario in AcousticScenario.all) {
          final encoder = LtEncoder(
            data: Uint8List.fromList(
              List.generate(600, (i) => (i * 37 + 11) & 0xFF),
            ),
            blockLen: profile.blockLen,
            sessionId: 0x5A,
          );
          final sync = AcousticFrameSync(profile: profile);
          const count = 16;
          final heard = simulateAcoustic(
            transmit(
              profile: profile,
              encoder: encoder,
              sessionId: 0x5A,
              firstSymbol: 0,
              symbolCount: count,
            ),
            scenario: scenario,
            seed: 9,
          );
          for (var at = 0; at < heard.length; at += 2048) {
            final end = at + 2048 > heard.length ? heard.length : at + 2048;
            sync.addSamples(Float32List.sublistView(heard, at, end));
          }
          line.write('${scenario.name}='
              '${sync.takeFrames().length}/$count '
              '(mk${sync.markersFound}) ');
        }
        // ignore: avoid_print
        print(line.toString());
      }
    });

    test('text message arrives in a normal room', () {
      final envelope = ChatPayloadCodec.encodeText(
        'Sound channel check: multi-tone FSK with Reed-Solomon and fountain '
        'coding.',
      );
      final run = runTransfer(
        profile: AcousticTxProfile.standard,
        envelope: envelope,
        scenario: AcousticScenario.room,
      );
      // ignore: avoid_print
      print('text ${envelope.length}B in ${run.seconds.toStringAsFixed(1)}s '
          '= ${run.netBytesPerSecond.toStringAsFixed(1)}B/s '
          '(${run.framesDecoded} frames decoded)');
      expect(run.recovered, isTrue);
    });

    test('every profile recovers a payload in a normal room', () {
      for (final profile in AcousticTxProfile.values) {
        final envelope = ChatPayloadCodec.encode(
          type: ChatMessageType.file,
          data: Uint8List.fromList(
            List.generate(400, (i) => (i * 101 + 7) & 0xFF),
          ),
          fileName: 'blob.bin',
        );
        final run = runTransfer(
          profile: profile,
          envelope: envelope,
          scenario: AcousticScenario.room,
          seed: 17,
        );
        // ignore: avoid_print
        print('${profile.label.padRight(9)} ${envelope.length}B '
            '${run.recovered ? "ok" : "FAILED"} in '
            '${run.seconds.toStringAsFixed(1)}s '
            '= ${run.netBytesPerSecond.toStringAsFixed(1)}B/s');
        expect(run.recovered, isTrue, reason: '${profile.label} failed');
      }
    });

    test('safe profile still works in a noisy room', () {
      final envelope = ChatPayloadCodec.encodeText('noisy room check ok');
      final run = runTransfer(
        profile: AcousticTxProfile.safe,
        envelope: envelope,
        scenario: AcousticScenario.noisyRoom,
        seed: 23,
        symbolBudget: 6,
      );
      // ignore: avoid_print
      print('safe/noisy ${envelope.length}B '
          '${run.recovered ? "ok" : "FAILED"} in '
          '${run.seconds.toStringAsFixed(1)}s');
      expect(run.recovered, isTrue);
    });

    test('rugged profile carries a message through a hostile room', () {
      // Nothing faster survives these conditions, which is the whole reason
      // the rugged setting exists.
      final envelope = ChatPayloadCodec.encodeText('sos');
      final run = runTransfer(
        profile: AcousticTxProfile.rugged,
        envelope: envelope,
        scenario: AcousticScenario.hostile,
        seed: 5,
        symbolBudget: 20,
      );
      // ignore: avoid_print
      print('rugged/hostile ${envelope.length}B '
          '${run.recovered ? "ok" : "FAILED"} in '
          '${run.seconds.toStringAsFixed(1)}s');
      expect(run.recovered, isTrue);
    });

    test('the ladder is ordered slowest to fastest', () {
      // Automatic backoff walks this list, so the ordering is load-bearing.
      for (var i = 1; i < AcousticTxProfile.values.length; i++) {
        final slower = AcousticTxProfile.values[i - 1];
        final faster = AcousticTxProfile.values[i];
        expect(faster.netBytesPerSecond(),
            greaterThan(slower.netBytesPerSecond()),
            reason: '${faster.label} should out-run ${slower.label}');
        expect(faster.slower, slower);
      }
      expect(AcousticTxProfile.rugged.slower, AcousticTxProfile.rugged);
    });
  });
}
