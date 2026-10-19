import 'dart:convert';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/user/user_profile_store.dart';

/// Envelope: magic "APCM" + type byte + utf8 name + raw bytes.
///
/// The name field carries an optional short sender display name:
/// - text / link: name = sender (file name unused)
/// - image / video / file: name = `sender\x1ffileName` when a sender is set,
///   otherwise just the file name (legacy)
class ChatPayloadCodec {
  static const _magic = [0x41, 0x50, 0x43, 0x4D]; // APCM

  /// Separates sender from file name inside the APCM name field.
  static const senderFileSep = '\x1f';

  static Uint8List encode({
    required ChatMessageType type,
    required Uint8List data,
    String? fileName,
    String? mimeType,
    String? senderName,
  }) {
    final nameBytes = utf8.encode(
      packNameField(type: type, senderName: senderName, fileName: fileName),
    );
    final mimeBytes = utf8.encode(mimeType ?? '');
    final buffer = BytesBuilder();
    buffer.add(_magic);
    buffer.addByte(type.index);
    buffer.addByte(nameBytes.length);
    buffer.add(nameBytes);
    buffer.addByte(mimeBytes.length);
    buffer.add(mimeBytes);
    buffer.add(data);
    return buffer.toBytes();
  }

  /// Bytes [encode] adds around the data, without building the envelope.
  static int overheadBytes({
    String? fileName,
    String? mimeType,
    String? senderName,
    ChatMessageType type = ChatMessageType.file,
  }) =>
      _magic.length +
      3 +
      utf8
          .encode(
            packNameField(
              type: type,
              senderName: senderName,
              fileName: fileName,
            ),
          )
          .length +
      utf8.encode(mimeType ?? '').length;

  /// Packs sender + optional file name into the APCM name field.
  static String packNameField({
    required ChatMessageType type,
    String? senderName,
    String? fileName,
  }) {
    final sender = UserProfileStore.sanitize(senderName);
    final file = fileName ?? '';
    if (sender == null) return file;

    if (type == ChatMessageType.text || type == ChatMessageType.link) {
      return sender;
    }
    if (file.isEmpty) return sender;
    return '$sender$senderFileSep$file';
  }

  /// Splits the APCM name field into sender and file name.
  static ({String? senderName, String? fileName}) unpackNameField(
    String raw,
    ChatMessageType type,
  ) {
    if (raw.isEmpty) return (senderName: null, fileName: null);

    final sep = raw.indexOf(senderFileSep);
    if (sep >= 0) {
      final sender = UserProfileStore.sanitize(raw.substring(0, sep));
      final file = raw.substring(sep + 1);
      return (
        senderName: sender,
        fileName: file.isEmpty ? null : file,
      );
    }

    if (type == ChatMessageType.text || type == ChatMessageType.link) {
      // Legacy builds used message.txt / link.url here; ignore those.
      if (raw == 'message.txt' || raw == 'link.url') {
        return (senderName: null, fileName: null);
      }
      return (senderName: UserProfileStore.sanitize(raw), fileName: null);
    }

    return (senderName: null, fileName: raw);
  }

  /// Text and links leave MIME empty: the type byte already says what they
  /// are. An optional short [senderName] uses the name field (~name length + 1
  /// byte on air).
  static Uint8List encodeText(String text, {String? senderName}) {
    return encode(
      type: ChatMessageType.text,
      data: Uint8List.fromList(utf8.encode(text)),
      senderName: senderName,
    );
  }

  static Uint8List encodeLink(String url, {String? senderName}) {
    return encode(
      type: ChatMessageType.link,
      data: Uint8List.fromList(utf8.encode(url)),
      senderName: senderName,
    );
  }

  /// True when bytes begin with the APCM chat envelope magic.
  static bool isApcmEnvelope(Uint8List raw) =>
      raw.length >= 4 &&
      raw[0] == _magic[0] &&
      raw[1] == _magic[1] &&
      raw[2] == _magic[2] &&
      raw[3] == _magic[3];

  static ChatMessage? decodeIncoming(Uint8List raw, {required bool isOutgoing}) {
    if (isApcmEnvelope(raw)) {
      if (!looksComplete(raw)) return null;

      var offset = 4;
      if (offset >= raw.length) return null;
      final typeIndex = raw[offset++];
      final type = ChatMessageType.values[typeIndex.clamp(0, ChatMessageType.values.length - 1)];

      if (offset >= raw.length) return null;
      final nameLen = raw[offset++];
      if (offset + nameLen > raw.length) return null;
      final rawName = utf8.decode(raw.sublist(offset, offset + nameLen));
      offset += nameLen;
      final names = unpackNameField(rawName, type);

      if (offset >= raw.length) return null;
      final mimeLen = raw[offset++];
      if (offset + mimeLen > raw.length) return null;
      final mimeType = utf8.decode(raw.sublist(offset, offset + mimeLen));
      offset += mimeLen;

      final data = raw.sublist(offset);
      final text = type == ChatMessageType.text || type == ChatMessageType.link
          ? utf8.decode(data)
          : null;

      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isOutgoing: isOutgoing,
        type: type,
        status: ChatMessageStatus.delivered,
        timestamp: DateTime.now(),
        text: text,
        data: type == ChatMessageType.text || type == ChatMessageType.link ? null : data,
        fileName: names.fileName,
        mimeType: mimeType.isEmpty ? null : mimeType,
        byteSize: data.length,
        senderName: names.senderName,
      );
    }

    // Plain text fallback (legacy HELLO messages).
    try {
      final text = utf8.decode(raw);
      if (text.isEmpty) return null;
      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isOutgoing: isOutgoing,
        type: ChatMessageType.text,
        status: ChatMessageStatus.delivered,
        timestamp: DateTime.now(),
        text: text,
        byteSize: raw.length,
      );
    } catch (_) {
      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isOutgoing: isOutgoing,
        type: ChatMessageType.file,
        status: ChatMessageStatus.delivered,
        timestamp: DateTime.now(),
        data: raw,
        fileName: 'received.bin',
        byteSize: raw.length,
      );
    }
  }

  /// True when [raw] has a complete APCM envelope structure and plausible payload.
  static bool looksComplete(Uint8List raw) {
    if (!isApcmEnvelope(raw)) {
      return raw.isNotEmpty;
    }

    var offset = 4;
    if (offset >= raw.length) return false;
    final typeIndex = raw[offset++];
    if (typeIndex < 0 || typeIndex >= ChatMessageType.values.length) {
      return false;
    }
    final type = ChatMessageType.values[typeIndex];

    if (offset >= raw.length) return false;
    final nameLen = raw[offset++];
    if (offset + nameLen > raw.length) return false;
    offset += nameLen;

    if (offset >= raw.length) return false;
    final mimeLen = raw[offset++];
    if (offset + mimeLen > raw.length) return false;
    offset += mimeLen;

    final data = raw.sublist(offset);
    return switch (type) {
      ChatMessageType.text || ChatMessageType.link => data.isNotEmpty,
      ChatMessageType.image => isDisplayableImage(data),
      ChatMessageType.video => data.length >= 512,
      ChatMessageType.file => data.isNotEmpty,
    };
  }

  /// JPEG / PNG / GIF / WebP magic check — do not require JPEG EOI at exact end.
  static bool isDisplayableImage(Uint8List data) {
    if (data.length < 24) return false;
    if (data[0] == 0xFF && data[1] == 0xD8) return true; // JPEG
    if (data.length >= 8 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return true; // PNG
    }
    if (data.length >= 6 &&
        data[0] == 0x47 &&
        data[1] == 0x49 &&
        data[2] == 0x46) {
      return true; // GIF
    }
    if (data.length >= 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[8] == 0x57 &&
        data[9] == 0x45) {
      return true; // WebP
    }
    return false;
  }
}
