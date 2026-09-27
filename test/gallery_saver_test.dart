import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/media/gallery_saver.dart';

ChatMessage _msg(ChatMessageType type, [List<int> bytes = const [1, 2, 3]]) => ChatMessage(
      id: '${type.name}-${bytes.length}',
      isOutgoing: false,
      type: type,
      status: ChatMessageStatus.delivered,
      timestamp: DateTime(2026),
      data: Uint8List.fromList(bytes),
    );

void main() {
  test('only non-empty photos and videos are saveable', () {
    expect(GallerySaver.canSave(_msg(ChatMessageType.image)), isTrue);
    expect(GallerySaver.canSave(_msg(ChatMessageType.video)), isTrue);
    expect(GallerySaver.canSave(_msg(ChatMessageType.text)), isFalse);
    expect(GallerySaver.canSave(_msg(ChatMessageType.file)), isFalse);
    expect(GallerySaver.canSave(_msg(ChatMessageType.image, const [])), isFalse);
  });

  test('desktop test host reports unsupported and saves nothing', () async {
    final saver = GallerySaver.instance;
    expect(saver.isSupported, isFalse);
    final m = _msg(ChatMessageType.image);
    expect(await saver.save(m), isFalse);
    expect(saver.isSaved(m.id), isFalse);
    expect(saver.isSaving(m.id), isFalse);
  });
}
