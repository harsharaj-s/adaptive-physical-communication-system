import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isOutgoing;
    final theme = Theme.of(context);
    final maxW = MediaQuery.sizeOf(context).width * 0.82;

    final bg = isMe
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55);
    final fg = isMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onTertiaryContainer;
    final borderColor = isMe
        ? theme.colorScheme.primary.withValues(alpha: 0.35)
        : Colors.lightGreenAccent.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.lightGreenAccent.withValues(alpha: 0.15),
              child: const Icon(Icons.sensors, size: 16, color: Colors.lightGreenAccent),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Received',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.lightGreenAccent.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      _Content(message: message, color: fg),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            _timeLabel(message.timestamp),
                            style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.65)),
                          ),
                          const SizedBox(width: 6),
                          Icon(_statusIcon(message.status), size: 14, color: _statusColor(message.status)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _statusLabel(message.status, isMe),
                              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.65)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (message.byteSize != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              _sizeLabel(message.byteSize!),
                              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.65)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  static String _timeLabel(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _statusLabel(ChatMessageStatus s, bool isMe) => switch (s) {
        ChatMessageStatus.sending => 'Sending…',
        ChatMessageStatus.sent => 'Sent',
        ChatMessageStatus.delivered => isMe ? 'Delivered' : 'Received',
        ChatMessageStatus.failed => 'Failed',
      };

  static IconData _statusIcon(ChatMessageStatus s) => switch (s) {
        ChatMessageStatus.sending => Icons.schedule,
        ChatMessageStatus.sent => Icons.check,
        ChatMessageStatus.delivered => Icons.done_all,
        ChatMessageStatus.failed => Icons.error_outline,
      };

  static Color _statusColor(ChatMessageStatus s) => switch (s) {
        ChatMessageStatus.failed => Colors.redAccent,
        ChatMessageStatus.delivered => Colors.lightBlueAccent,
        ChatMessageStatus.sending => Colors.amberAccent,
        ChatMessageStatus.sent => Colors.white54,
      };
}

class _Content extends StatelessWidget {
  const _Content({required this.message, required this.color});

  final ChatMessage message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (message.type) {
      ChatMessageType.text => SelectableText(
          message.text ?? '',
          style: TextStyle(color: color, fontSize: 15, height: 1.4),
        ),
      ChatMessageType.link => SelectableText(
          message.text ?? '',
          style: TextStyle(
            color: color,
            fontSize: 15,
            height: 1.4,
            decoration: TextDecoration.underline,
          ),
        ),
      ChatMessageType.image => message.data != null
          ? GestureDetector(
              onTap: () => _showImage(context, message.data!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  message.data!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      _attachmentCard(Icons.broken_image, 'Image unavailable', color),
                ),
              ),
            )
          : _attachmentCard(Icons.image, message.fileName ?? 'Photo', color),
      ChatMessageType.video => _attachmentCard(
          Icons.videocam,
          message.fileName ?? 'Video',
          color,
          subtitle: message.byteSize != null ? ChatBubble._sizeLabel(message.byteSize!) : null,
        ),
      ChatMessageType.file => _attachmentCard(
          Icons.insert_drive_file,
          message.fileName ?? 'File',
          color,
          subtitle: message.byteSize != null ? ChatBubble._sizeLabel(message.byteSize!) : null,
        ),
    };
  }

  void _showImage(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _attachmentCard(IconData icon, String label, Color color, {String? subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
