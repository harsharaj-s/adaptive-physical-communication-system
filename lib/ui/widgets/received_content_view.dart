import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/media/gallery_saver.dart';

/// Unified display for received text, images, videos, and links.
class ReceivedContentView extends StatelessWidget {
  const ReceivedContentView({
    super.key,
    required this.message,
    this.compact = false,
  });

  final ChatMessage message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(_typeIcon(message.type), color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _typeLabel(message.type),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (message.byteSize != null)
                  Text(
                    _sizeLabel(message.byteSize!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                        ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 12 : 20),
            _ContentBody(message: message, compact: compact),
            if (GallerySaver.canSave(message) && GallerySaver.instance.isSupported) ...[
              const SizedBox(height: 12),
              _GallerySaveButton(message: message),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _typeIcon(ChatMessageType type) => switch (type) {
        ChatMessageType.text => Icons.chat_bubble_outline,
        ChatMessageType.link => Icons.link,
        ChatMessageType.image => Icons.image_outlined,
        ChatMessageType.video => Icons.videocam_outlined,
        ChatMessageType.file => Icons.insert_drive_file_outlined,
      };

  static String _typeLabel(ChatMessageType type) => switch (type) {
        ChatMessageType.text => 'Text message',
        ChatMessageType.link => 'Link',
        ChatMessageType.image => 'Image',
        ChatMessageType.video => 'Video',
        ChatMessageType.file => 'File',
      };

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ContentBody extends StatelessWidget {
  const _ContentBody({required this.message, required this.compact});

  final ChatMessage message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (message.type) {
      ChatMessageType.text => SelectableText(
          message.text ?? '',
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      ChatMessageType.link => _LinkContent(url: message.text ?? ''),
      ChatMessageType.image => message.data != null
          ? _ImageContent(
              data: message.data!,
              compact: compact,
              onTapFull: (ctx, bytes) => _showFullImage(ctx, bytes),
            )
          : const _ErrorPlaceholder(
              icon: Icons.image_not_supported,
              message: 'No image data',
            ),
      ChatMessageType.video => message.data != null
          ? _VideoPlayerWidget(data: message.data!, mimeType: message.mimeType)
          : const _ErrorPlaceholder(icon: Icons.videocam_off, message: 'No video data'),
      ChatMessageType.file => _FileContent(message: message),
    };
  }

  void _showFullImage(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.high),
        ),
      ),
    );
  }
}

/// Renders received image bytes — temp file first (most reliable on Android).
class _ImageContent extends StatefulWidget {
  const _ImageContent({
    required this.data,
    required this.compact,
    required this.onTapFull,
  });

  final Uint8List data;
  final bool compact;
  final void Function(BuildContext context, Uint8List bytes) onTapFull;

  @override
  State<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends State<_ImageContent> {
  File? _file;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _prepareFile();
  }

  Future<void> _prepareFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/rx_img_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(widget.data, flush: true);
      if (!mounted) return;
      setState(() => _file = file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _memoryFallback(context);
    }
    final file = _file;
    if (file == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final height = widget.compact ? 220.0 : 420.0;
    return GestureDetector(
      onTap: () => widget.onTapFull(context, widget.data),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          height: height,
          width: double.infinity,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stack) => _memoryFallback(context),
        ),
      ),
    );
  }

  Widget _memoryFallback(BuildContext context) {
    final height = widget.compact ? 220.0 : 420.0;
    return GestureDetector(
      onTap: () => widget.onTapFull(context, widget.data),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          widget.data,
          fit: BoxFit.contain,
          height: height,
          width: double.infinity,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stack) => const _ErrorPlaceholder(
            icon: Icons.broken_image,
            message: 'Could not display image — data may be incomplete',
          ),
        ),
      ),
    );
  }
}

class _LinkContent extends StatelessWidget {
  const _LinkContent({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          url,
          style: TextStyle(
            fontSize: 15,
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _openUrl(context, url),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open link'),
        ),
      ],
    );
  }

  Future<void> _openUrl(BuildContext context, String raw) async {
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri == null) {
      _showSnack(context, 'Invalid URL');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) _showSnack(context, 'Could not open link');
    }
  }

  void _showSnack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  const _VideoPlayerWidget({required this.data, this.mimeType});

  final Uint8List data;
  final String? mimeType;

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final ext = _extensionFromMime(widget.mimeType);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/rx_video_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(widget.data, flush: true);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(1.0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not play video (${widget.data.length} bytes)',
        );
      }
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  String _extensionFromMime(String? mime) {
    if (mime == null) return 'mp4';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('quicktime') || mime.contains('mov')) return 'mov';
    return 'mp4';
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorPlaceholder(icon: Icons.videocam_off, message: _error!);
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                if (!controller.value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: const Icon(Icons.play_arrow, size: 48),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
              icon: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_formatDuration(controller.value.position)} / '
              '${_formatDuration(controller.value.duration)}',
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _FileContent extends StatelessWidget {
  const _FileContent({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'Received file',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (message.byteSize != null)
                  Text(
                    ReceivedContentView._sizeLabel(message.byteSize!),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GallerySaveButton extends StatelessWidget {
  const _GallerySaveButton({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final saver = GallerySaver.instance;
    return ListenableBuilder(
      listenable: saver,
      builder: (context, _) {
        final id = message.id;
        if (saver.isSaved(id)) {
          return const OutlinedButton(
            onPressed: null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Text('Saved to Gallery · ${GallerySaver.albumName}'),
              ],
            ),
          );
        }
        if (saver.isSaving(id)) {
          return const OutlinedButton(
            onPressed: null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Saving to Gallery…'),
              ],
            ),
          );
        }
        final error = saver.errorFor(id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => saver.save(message),
              icon: Icon(error == null ? Icons.download_rounded : Icons.refresh),
              label: Text(error == null ? 'Save to Gallery' : 'Retry save'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
