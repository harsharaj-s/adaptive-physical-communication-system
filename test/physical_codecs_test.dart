import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/physical_codecs.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

void main() {
  group('OpticalBitCodec', () {
    final codec = OpticalBitCodec();

    test('encodes and decodes bytes', () {
      final data = Uint8List.fromList('HELLO'.codeUnits);
      final bits = codec.bytesToBits(data);
      expect(bits.length, greaterThan(data.length * 8));
      final decoded = codec.bitsToBytes(bits, expectedLength: data.length);
      expect(String.fromCharCodes(decoded), 'HELLO');
    });
  });

  group('FskCodec', () {
    final codec = FskCodec(symbolDurationMs: 40);

    test('encodes bytes to samples', () {
      final samples = codec.encodeBytes(Uint8List.fromList([0xAA]));
      expect(samples.length, greaterThan(0));
    });

    test('decodes generated tone', () {
      final tone0 = codec.generateToneSamples(0).toList();
      final tone1 = codec.generateToneSamples(1).toList();
      expect(codec.decodeSymbol(tone0), 0);
      expect(codec.decodeSymbol(tone1), 1);
    });
  });

  group('Goertzel', () {
    test('detects target frequency', () {
      final codec = FskCodec(symbolDurationMs: 40);
      final tone = codec.generateToneSamples(1).toList();
      final g = Goertzel(sampleRate: 44100, targetFrequency: 3200);
      final energy = g.detect(tone);
      expect(energy, greaterThan(0));
    });
  });

  group('VibrationBitCodec', () {
    final codec = VibrationBitCodec();

    test('encodes and decodes bytes with preamble', () {
      final data = Uint8List.fromList('VIB'.codeUnits);
      final bits = codec.bytesToBits(data);
      expect(bits.sublist(0, codec.preamble.length), codec.preamble);
      final decoded = codec.bitsToBytes(bits, expectedLength: data.length);
      expect(String.fromCharCodes(decoded), 'VIB');
    });

    test('maps pulse durations to bits', () {
      expect(codec.decodePulseDuration(codec.shortPulseMs.toDouble()), 0);
      expect(codec.decodePulseDuration(codec.longPulseMs.toDouble()), 1);
    });

    test('detects vibration from accelerometer magnitude', () {
      expect(codec.isVibrationActive(10.0), false);
      expect(codec.isVibrationActive(codec.detectionThreshold), true);
      expect(codec.isVibrationActive(15.0), true);
    });

    test('detects vibration relative to baseline', () {
      expect(codec.isVibrationActive(9.8, baseline: 9.8), false);
      expect(codec.isVibrationActive(11.5, baseline: 9.8), true);
    });
  });

  group('FskStreamDecoder', () {
    test('recovers a full CRC-valid packet from generated tones', () {
      final codec = FskCodec(symbolDurationMs: 20);
      final decoder = FskStreamDecoder(codec: codec);
      final payload = Uint8List.fromList('PING'.codeUnits);
      final packet = packetCodec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: 1,
          transferId: 2,
          packetType: PacketType.data,
          channelId: CommChannelId.acoustic,
          sequenceNumber: 1,
          payloadLength: payload.length,
          totalPackets: 1,
        ),
        payload,
      );
      final samples = codec.encodeBytes(packet);
      decoder.addSamples(samples.toList());
      final decoded = decoder.pollPacket();
      expect(decoded, isNotNull);
      final parsed = packetCodec.decode(decoded!);
      expect(parsed, isNotNull);
      expect(String.fromCharCodes(parsed!.payload), 'PING');
      expect(parsed.totalPackets, 1);
    });
    test('decodes length-prefixed direct envelope', () {
      final codec = FskCodec(symbolDurationMs: 12);
      final decoder = FskStreamDecoder(codec: codec);
      final envelope = ChatPayloadCodec.encodeText('Hi');
      final framed = frameDirectEnvelope(envelope);
      final samples = codec.encodeBytes(framed);
      decoder.addSamples(samples.toList());
      final decoded = decoder.pollDirectEnvelope();
      expect(decoded, isNotNull);
      expect(String.fromCharCodes(decoded!), contains('Hi'));
    });
  });
}
