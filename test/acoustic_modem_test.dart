import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_modem.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acoustic_channel_sim.dart';

/// Play a modem transmission through a simulated room and back into a second
/// modem, exactly as the channel wires it up: WAV out of the speaker, PCM16
/// chunks in from the microphone.
Future<({bool recovered, int bursts})> loopback({
  required Uint8List envelope,
  required AcousticTxProfile profile,
  required AcousticScenario scenario,
  int seed = 11,
  AcousticFountainModem? receiver,
}) async {
  final sender = AcousticFountainModem(profile: profile);
  final rx = receiver ?? (AcousticFountainModem(profile: profile)..startReceive());

  var bursts = 0;
  var recovered = false;

  // Must be awaited: each `await play(...)` yields even when the fake player
  // finishes at once, so an unawaited call would only ever play one burst.
  await sender.transmit(
    envelope: envelope,
    shouldContinue: () => !recovered,
    play: (wav) async {
      bursts++;
      final heard = simulateAcoustic(
        _wavToFloat32(wav),
        scenario: scenario,
        seed: seed + bursts,
      );
      for (var at = 0; at < heard.length; at += 2048) {
        final end = at + 2048 > heard.length ? heard.length : at + 2048;
        rx.addSamples(_toPcm16AndBack(heard, at, end));
      }
      if (rx.takeEnvelopes().isNotEmpty) recovered = true;
    },
  );

  return (recovered: recovered, bursts: bursts);
}

/// Strip the 44-byte WAV header and undo the 16-bit quantisation.
Float32List _wavToFloat32(Uint8List wav) {
  final count = (wav.length - 44) ~/ 2;
  final out = Float32List(count);
  final view = ByteData.sublistView(wav, 44);
  for (var i = 0; i < count; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Round-trip a slice through PCM16 so the receiver sees the same
/// quantisation the microphone would deliver.
Float32List _toPcm16AndBack(Float32List samples, int from, int to) {
  final bytes = Uint8List((to - from) * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < to - from; i++) {
    view.setInt16(
      i * 2,
      (samples[from + i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return pcm16ToFloat32(bytes);
}

void main() {
  group('acoustic modem', () {
    test('a text message survives speaker, room and microphone', () async {
      final envelope = ChatPayloadCodec.encodeText(
        'Sound transfer over multi-tone FSK, end to end.',
      );
      final run = await loopback(
        envelope: envelope,
        profile: AcousticTxProfile.standard,
        scenario: AcousticScenario.room,
      );
      expect(run.recovered, isTrue);
      // ignore: avoid_print
      print('modem loopback: ${envelope.length}B in ${run.bursts} bursts');
    });

    test('rateless sender stops as soon as the receiver has enough', () async {
      final envelope = ChatPayloadCodec.encodeText('short');
      final run = await loopback(
        envelope: envelope,
        profile: AcousticTxProfile.standard,
        scenario: AcousticScenario.easy,
      );
      expect(run.recovered, isTrue);
      // One block of payload, so a couple of bursts is all it should take.
      expect(run.bursts, lessThanOrEqualTo(3));
    });

    test('every profile completes a loopback in a normal room', () async {
      for (final profile in AcousticTxProfile.values) {
        final run = await loopback(
          envelope: Uint8List.fromList(
            List.generate(220, (i) => (i * 29 + 3) & 0xFF),
          ),
          profile: profile,
          scenario: AcousticScenario.room,
          seed: 31,
        );
        expect(run.recovered, isTrue, reason: '${profile.label} failed');
      }
    });

    test('a file spanning many bursts completes in a noisy room', () async {
      final envelope = Uint8List.fromList(
        List.generate(1200, (i) => (i * 131 + 7) & 0xFF),
      );
      final run = await loopback(
        envelope: envelope,
        profile: AcousticTxProfile.safe,
        scenario: AcousticScenario.noisyRoom,
        seed: 5,
      );
      expect(run.recovered, isTrue);
      final k = (envelope.length / AcousticTxProfile.safe.blockLen).ceil();
      // Rateless overshoot should stay modest, well inside the budget.
      expect(run.bursts * 4, lessThan(AcousticFountainModem.symbolBudget(k)));
      // ignore: avoid_print
      print('noisy room: ${envelope.length}B (K=$k) in ${run.bursts} bursts');
    });

    test('receiver finds the sender\'s profile without being told', () async {
      final receiver = AcousticFountainModem(profile: AcousticTxProfile.fast)
        ..startReceive();
      expect(receiver.rxProfile, isNull);

      // Consecutive messages at different speeds, one listening receiver.
      for (final profile in [
        AcousticTxProfile.rugged,
        AcousticTxProfile.standard,
        AcousticTxProfile.safe,
      ]) {
        final run = await loopback(
          envelope: ChatPayloadCodec.encodeText('sent at ${profile.label}'),
          profile: profile,
          scenario: AcousticScenario.room,
          receiver: receiver,
        );
        expect(run.recovered, isTrue, reason: '${profile.label} not heard');
        expect(receiver.rxProfile, isNull,
            reason: 'should reopen to every profile after a message lands');
      }
    });

    test('fixed-profile receiver ignores other profiles', () async {
      final receiver = AcousticFountainModem(
        profile: AcousticTxProfile.standard,
        autoDetectProfile: false,
      )..startReceive();
      expect(receiver.rxProfile, AcousticTxProfile.standard);
      final sender = AcousticFountainModem(profile: AcousticTxProfile.rugged);
      var bursts = 0;
      await sender.transmit(
        envelope: ChatPayloadCodec.encodeText('wrong speed'),
        maxSymbols: 8,
        play: (wav) async {
          bursts++;
          receiver.addSamples(_wavToFloat32(wav));
        },
      );
      expect(bursts, greaterThan(0));
      expect(receiver.takeEnvelopes(), isEmpty);
      expect(receiver.progress.framesRepaired, 0);
    });

    test('changing profile mid-listen restarts the receiver cleanly', () {
      final modem = AcousticFountainModem(profile: AcousticTxProfile.safe)
        ..startReceive();
      modem.profile = AcousticTxProfile.fast;
      expect(modem.profile, AcousticTxProfile.fast);
      expect(modem.progress.active, isFalse);
      // Must not throw on audio arriving straight after the switch.
      modem.addSamples(Float32List(4096));
      expect(modem.takeEnvelopes(), isEmpty);
    });

    test('pcm16 conversion round-trips within quantisation error', () {
      final source = Float32List.fromList([0, 0.5, -0.5, 0.999, -0.999]);
      final bytes = Uint8List(source.length * 2);
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i < source.length; i++) {
        view.setInt16(i * 2, (source[i] * 32767).round(), Endian.little);
      }
      final back = pcm16ToFloat32(bytes);
      for (var i = 0; i < source.length; i++) {
        // Encoding scales by 32767 and decoding by 32768, the usual
        // asymmetry, so allow a shade over one quantisation step.
        expect(back[i], closeTo(source[i], 2 / 32767));
      }
    });
  });
}
