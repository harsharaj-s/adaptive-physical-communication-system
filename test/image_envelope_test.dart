import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/qr_optical_codec.dart';
import 'package:image/image.dart' as img;

void main() {
  group('Image envelope roundtrip', () {
    test('JPEG envelope survives QR chunk reassembly and decodes to image', () {
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 64, height: 64, numChannels: 3)),
      );
      expect(ChatPayloadCodec.isDisplayableImage(jpeg), isTrue);

      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.image,
        data: jpeg,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
      );
      expect(ChatPayloadCodec.looksComplete(envelope), isTrue);

      final frames = qrOpticalCodec.encodeToQrStrings(envelope);
      expect(frames, isNotEmpty);

      final reassembler = QrOpticalReassembler();
      Uint8List? restored;
      for (final frame in frames) {
        final chunk = qrOpticalCodec.decodeQrString(frame);
        expect(chunk, isNotNull);
        restored = reassembler.addChunk(chunk!) ?? restored;
      }

      expect(restored, isNotNull);
      final msg = ChatPayloadCodec.decodeIncoming(restored!, isOutgoing: false);
      expect(msg, isNotNull);
      expect(msg!.type, ChatMessageType.image);
      expect(msg.data, isNotNull);
      expect(msg.data!.length, jpeg.length);
      expect(ChatPayloadCodec.isDisplayableImage(msg.data!), isTrue);
    });
  });
}
