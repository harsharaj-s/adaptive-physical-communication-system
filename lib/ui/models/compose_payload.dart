import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';

/// Outgoing message composed on the send screen before physical transmission.
class ComposePayload {
  const ComposePayload({
    required this.type,
    required this.data,
    this.text,
    this.fileName,
    this.mimeType,
  });

  final ChatMessageType type;
  final Uint8List data;
  final String? text;
  final String? fileName;
  final String? mimeType;

  int get byteSize => data.length;

  String get preview => switch (type) {
        ChatMessageType.text => text ?? '',
        ChatMessageType.link => text ?? fileName ?? 'Link',
        ChatMessageType.image => fileName ?? 'Image',
        ChatMessageType.video => fileName ?? 'Video',
        ChatMessageType.file => fileName ?? 'File',
      };

  Uint8List toEnvelope() {
    return switch (type) {
      ChatMessageType.text when text != null => ChatPayloadCodec.encodeText(text!),
      ChatMessageType.link when text != null => ChatPayloadCodec.encodeLink(text!),
      _ => ChatPayloadCodec.encode(
          type: type,
          data: data,
          fileName: fileName,
          mimeType: mimeType,
        ),
    };
  }

  bool get isEmpty {
    if (type == ChatMessageType.text || type == ChatMessageType.link) {
      return (text ?? '').trim().isEmpty;
    }
    return data.isEmpty;
  }
}
