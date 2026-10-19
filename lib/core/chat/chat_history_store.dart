import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';

/// Persists send/receive chat history on device (not over the air).
class ChatHistoryStore {
  ChatHistoryStore._();

  static const _indexFile = 'messages.json';
  static const _mediaDir = 'media';

  static Future<Directory?> _root() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/chat_history');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory?> _media() async {
    final root = await _root();
    if (root == null) return null;
    final dir = Directory('${root.path}/$_mediaDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<ChatMessage>> load() async {
    try {
      final root = await _root();
      if (root == null) return const [];
      final index = File('${root.path}/$_indexFile');
      if (!await index.exists()) return const [];

      final decoded = jsonDecode(await index.readAsString());
      if (decoded is! Map<String, dynamic>) return const [];
      final list = decoded['messages'];
      if (list is! List) return const [];

      final media = await _media();
      final out = <ChatMessage>[];
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) continue;
        final msg = await _fromJson(entry, media);
        if (msg != null) out.add(msg);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<ChatMessage> messages) async {
    try {
      final root = await _root();
      if (root == null) return;
      final media = await _media();
      if (media == null) return;

      final keepFiles = <String>{};
      final encoded = <Map<String, dynamic>>[];
      for (final msg in messages) {
        encoded.add(await _toJson(msg, media, keepFiles));
      }

      final index = File('${root.path}/$_indexFile');
      await index.writeAsString(
        jsonEncode({'version': 1, 'messages': encoded}),
        flush: true,
      );

      // Drop media files no longer referenced.
      await for (final entity in media.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (!keepFiles.contains(name)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Persistence must never break transfers.
    }
  }

  static Future<void> clear() async {
    try {
      final root = await _root();
      if (root == null) return;
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _toJson(
    ChatMessage msg,
    Directory media,
    Set<String> keepFiles,
  ) async {
    String? dataFile;
    if (msg.data != null && msg.data!.isNotEmpty) {
      dataFile = '${msg.id}.bin';
      keepFiles.add(dataFile);
      final file = File('${media.path}/$dataFile');
      await file.writeAsBytes(msg.data!, flush: true);
    }

    return {
      'id': msg.id,
      'isOutgoing': msg.isOutgoing,
      'type': msg.type.index,
      'status': msg.status.index,
      'timestamp': msg.timestamp.toIso8601String(),
      'text': msg.text,
      'fileName': msg.fileName,
      'mimeType': msg.mimeType,
      'byteSize': msg.byteSize,
      'senderName': msg.senderName,
      'dataFile': dataFile,
    };
  }

  static Future<ChatMessage?> _fromJson(
    Map<String, dynamic> json,
    Directory? media,
  ) async {
    try {
      final typeIndex = json['type'];
      final statusIndex = json['status'];
      if (typeIndex is! int || statusIndex is! int) return null;
      if (typeIndex < 0 || typeIndex >= ChatMessageType.values.length) {
        return null;
      }
      if (statusIndex < 0 || statusIndex >= ChatMessageStatus.values.length) {
        return null;
      }

      Uint8List? data;
      final dataFile = json['dataFile'];
      if (dataFile is String && media != null) {
        final file = File('${media.path}/$dataFile');
        if (await file.exists()) {
          data = await file.readAsBytes();
        }
      }

      final ts = json['timestamp'];
      return ChatMessage(
        id: '${json['id']}',
        isOutgoing: json['isOutgoing'] == true,
        type: ChatMessageType.values[typeIndex],
        status: ChatMessageStatus.values[statusIndex],
        timestamp: ts is String
            ? DateTime.tryParse(ts) ?? DateTime.now()
            : DateTime.now(),
        text: json['text'] as String?,
        data: data,
        fileName: json['fileName'] as String?,
        mimeType: json['mimeType'] as String?,
        byteSize: json['byteSize'] as int?,
        senderName: json['senderName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
