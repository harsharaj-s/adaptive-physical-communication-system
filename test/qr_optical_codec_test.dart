import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/physical/qr_optical_codec.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

void main() {
  group('QrOpticalCodec', () {
    test('single-chunk roundtrip for small packet', () {
      final header = PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: 42,
        transferId: 7,
        packetType: PacketType.data,
        channelId: CommChannelId.optical,
        sequenceNumber: 1,
        payloadLength: 5,
      );
      final encoded = packetCodec.encode(header, Uint8List.fromList('HELLO'.codeUnits));

      final qrStrings = qrOpticalCodec.encodeToQrStrings(encoded);
      expect(qrStrings, hasLength(1));
      expect(qrStrings.first, startsWith('$qrOpticalMagic:'));

      final chunk = qrOpticalCodec.decodeQrString(qrStrings.first);
      expect(chunk, isNotNull);
      expect(chunk!.index, 1);
      expect(chunk.total, 1);

      final reassembled = QrOpticalReassembler().addChunk(chunk);
      expect(reassembled, encoded);

      final decoded = packetCodec.decode(reassembled!);
      expect(decoded, isNotNull);
      expect(String.fromCharCodes(decoded!.payload), 'HELLO');
    });

    test('multi-chunk roundtrip for large payload', () {
      final payload = Uint8List.fromList(List.generate(1400, (i) => i % 256));
      final header = PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: 99,
        transferId: 3,
        packetType: PacketType.data,
        channelId: CommChannelId.optical,
        sequenceNumber: 2,
        payloadLength: payload.length,
      );
      final encoded = packetCodec.encode(header, payload);

      final qrStrings = qrOpticalCodec.encodeToQrStrings(encoded);
      expect(qrStrings.length, greaterThan(1));

      final reassembler = QrOpticalReassembler();
      Uint8List? result;
      for (final qr in qrStrings) {
        final chunk = qrOpticalCodec.decodeQrString(qr);
        expect(chunk, isNotNull);
        result = reassembler.addChunk(chunk!);
      }

      expect(result, encoded);
      final decoded = packetCodec.decode(result!);
      expect(decoded, isNotNull);
      expect(decoded!.payload, payload);
    });

    test('ignores non-APCS QR strings', () {
      expect(qrOpticalCodec.decodeQrString('https://example.com'), isNull);
      expect(qrOpticalCodec.decodeQrString('APCS2:abc:1/1:QQ'), isNull);
    });
  });
}
