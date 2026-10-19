import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';

void main() {
  group('sender display name in APCM envelope', () {
    test('text carries short sender with small overhead', () {
      const text = 'sos';
      const sender = 'Harsh';
      final plain = ChatPayloadCodec.encodeText(text);
      final named = ChatPayloadCodec.encodeText(text, senderName: sender);

      // nameLen byte + UTF-8 sender bytes only.
      expect(named.length - plain.length, utf8.encode(sender).length);

      final msg = ChatPayloadCodec.decodeIncoming(named, isOutgoing: false);
      expect(msg, isNotNull);
      expect(msg!.text, text);
      expect(msg.senderName, sender);
      expect(msg.fileName, isNull);
    });

    test('image keeps file name and sender', () {
      // Minimal JPEG-like header for isDisplayableImage (needs >= 24 bytes).
      final jpeg = Uint8List(32);
      jpeg[0] = 0xFF;
      jpeg[1] = 0xD8;
      for (var i = 2; i < jpeg.length; i++) {
        jpeg[i] = i;
      }

      final envelope = ChatPayloadCodec.encode(
        type: ChatMessageType.image,
        data: jpeg,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        senderName: 'Alex',
      );

      final msg = ChatPayloadCodec.decodeIncoming(envelope, isOutgoing: false);
      expect(msg, isNotNull);
      expect(msg!.senderName, 'Alex');
      expect(msg.fileName, 'photo.jpg');
      expect(msg.mimeType, 'image/jpeg');
      expect(msg.type, ChatMessageType.image);
    });

    test('legacy text envelope without sender still decodes', () {
      final envelope = ChatPayloadCodec.encodeText('hello');
      final msg = ChatPayloadCodec.decodeIncoming(envelope, isOutgoing: false);
      expect(msg!.text, 'hello');
      expect(msg.senderName, isNull);
    });

    test('sanitize clamps long names via packNameField', () {
      final long = 'A' * 40;
      final packed = ChatPayloadCodec.packNameField(
        type: ChatMessageType.text,
        senderName: long,
      );
      expect(packed.length, 20);
    });
  });
}
