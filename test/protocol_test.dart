import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

void main() {
  group('CRC', () {
    test('computes consistent CRC32', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      expect(computeCrc32(data), computeCrc32(data));
      expect(verifyCrc32(data, computeCrc32(data)), isTrue);
    });

    test('detects corruption', () {
      final data = Uint8List.fromList('test data'.codeUnits);
      final crc = computeCrc32(data);
      final corrupted = Uint8List.fromList(data);
      corrupted[0] = corrupted[0] ^ 0xFF;
      expect(verifyCrc32(corrupted, crc), isFalse);
    });
  });

  group('PacketCodec', () {
    final codec = PacketCodec();

    test('encodes and decodes a packet', () {
      final payload = Uint8List.fromList('HELLO'.codeUnits);
      final encoded = codec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: 12345,
          transferId: 67890,
          packetType: PacketType.data,
          channelId: CommChannelId.optical,
          sequenceNumber: 1,
          payloadLength: payload.length,
          totalPackets: 3,
        ),
        payload,
      );

      final decoded = codec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.sessionId, 12345);
      expect(decoded.sequenceNumber, 1);
      expect(decoded.totalPackets, 3);
      expect(String.fromCharCodes(decoded.payload), 'HELLO');
    });

    test('rejects corrupted packets', () {
      final payload = Uint8List.fromList('data'.codeUnits);
      final encoded = codec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: 1,
          transferId: 2,
          packetType: PacketType.data,
          channelId: CommChannelId.optical,
          sequenceNumber: 1,
          payloadLength: payload.length,
        ),
        payload,
      );
      encoded[encoded.length - 1] = encoded[encoded.length - 1] ^ 0xFF;
      expect(codec.decode(encoded), isNull);
    });
  });
}
