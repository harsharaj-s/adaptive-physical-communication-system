import 'dart:typed_data';

enum ChatMessageType { text, image, video, file, link }

enum ChatMessageStatus { sending, sent, delivered, failed }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.isOutgoing,
    required this.type,
    required this.status,
    required this.timestamp,
    this.text,
    this.data,
    this.fileName,
    this.mimeType,
    this.byteSize,
  });

  final String id;
  final bool isOutgoing;
  final ChatMessageType type;
  final ChatMessageStatus status;
  final DateTime timestamp;
  final String? text;
  final Uint8List? data;
  final String? fileName;
  final String? mimeType;
  final int? byteSize;

  ChatMessage copyWith({
    String? id,
    ChatMessageStatus? status,
    bool? isOutgoing,
    String? text,
    Uint8List? data,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      type: type,
      status: status ?? this.status,
      timestamp: timestamp,
      text: text ?? this.text,
      data: data ?? this.data,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: byteSize,
    );
  }

  String get preview {
    if (text != null && text!.isNotEmpty) return text!;
    if (fileName != null) return fileName!;
    return switch (type) {
      ChatMessageType.image => 'Photo',
      ChatMessageType.video => 'Video',
      ChatMessageType.file => 'File',
      ChatMessageType.link => text ?? 'Link',
      ChatMessageType.text => 'Message',
    };
  }
}
