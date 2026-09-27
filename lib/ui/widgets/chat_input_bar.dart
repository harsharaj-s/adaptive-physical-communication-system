import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickFile,
    this.hintText = 'Type a message…',
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onPickFile;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Attach',
              onPressed: enabled ? () => _showAttachMenu(context) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: hintText,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: enabled ? (_) => onSend() : null,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: enabled ? onSend : null,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
              ),
              child: const Icon(Icons.send, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.greenAccent),
              title: const Text('Photo / Image'),
              subtitle: const Text('Send a picture (JPEG, PNG…)'),
              onTap: () {
                Navigator.pop(ctx);
                onPickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.orangeAccent),
              title: const Text('Video'),
              subtitle: const Text('Small clips work best on physical channels'),
              onTap: () {
                Navigator.pop(ctx);
                onPickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.lightBlueAccent),
              title: const Text('Document / File'),
              subtitle: const Text('Any file type'),
              onTap: () {
                Navigator.pop(ctx);
                onPickFile();
              },
            ),
          ],
        ),
      ),
    );
  }
}
