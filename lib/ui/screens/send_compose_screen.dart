import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/media/image_compress.dart';
import 'package:adaptive_physical_communication/core/media/sample_media.dart';
import 'package:adaptive_physical_communication/ui/models/compose_payload.dart';
import 'package:adaptive_physical_communication/ui/screens/send_transmit_screen.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/ui/widgets/mode_picker_sheet.dart';

/// Compose text, image, video, or link before choosing a transmission mode.
class SendComposeScreen extends StatefulWidget {
  const SendComposeScreen({super.key});

  @override
  State<SendComposeScreen> createState() => _SendComposeScreenState();
}

class _SendComposeScreenState extends State<SendComposeScreen> {
  final _textController = TextEditingController();
  ComposePayload? _attachment;
  static const _maxHardwareBytes = 512 * 1024;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  ComposePayload? _buildPayload() {
    final text = _textController.text.trim();
    if (_attachment != null) {
      if (text.isNotEmpty &&
          (_attachment!.type == ChatMessageType.image ||
              _attachment!.type == ChatMessageType.video)) {
        return ComposePayload(
          type: ChatMessageType.text,
          data: Uint8List.fromList(text.codeUnits),
          text: text,
        );
      }
      return _attachment;
    }
    if (text.isEmpty) return null;
    if (_looksLikeUrl(text)) {
      return ComposePayload(
        type: ChatMessageType.link,
        data: Uint8List.fromList(text.codeUnits),
        text: text.startsWith('http') ? text : 'https://$text',
      );
    }
    return ComposePayload(
      type: ChatMessageType.text,
      data: Uint8List.fromList(text.codeUnits),
      text: text,
    );
  }

  bool _looksLikeUrl(String text) {
    return text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('www.') ||
        RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}').hasMatch(text);
  }

  Future<void> _pickFile(FileType pickerType, ChatMessageType chatType) async {
    final result = await FilePicker.platform.pickFiles(
      type: pickerType,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    var data = Uint8List.fromList(bytes);
    String? fileName = file.name;
    String? mime = file.extension != null
        ? _mimeForExtension(file.extension!)
        : null;

    if (chatType == ChatMessageType.image) {
      try {
        data = await compressImageForTransfer(data);
      } on ImageTransferException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
      fileName = fileName.replaceAll(
        RegExp(r'\.(png|webp|gif)$', caseSensitive: false),
        '.jpg',
      );
      mime = 'image/jpeg';
    }

    if (data.length > _maxHardwareBytes && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large file'),
          content: Text(
            'This file is ${(bytes.length / 1024).toStringAsFixed(0)} KB. '
            'Physical channels work best under ${(_maxHardwareBytes / 1024).toStringAsFixed(0)} KB. '
            'Transfer may be slow or fail. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _attachment = ComposePayload(
        type: chatType,
        data: data,
        fileName: fileName,
        mimeType: mime,
      );
    });
  }

  Future<void> _pickSample() async {
    final sample = await showModalBottomSheet<SampleMedia>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SamplePickerSheet(),
    );
    if (sample == null) return;
    final data = await sample.load();
    if (!mounted) return;
    setState(() {
      _attachment = ComposePayload(
        type: sample.type,
        data: data,
        fileName: sample.fileName,
        mimeType: sample.mimeType,
      );
    });
  }

  String? _mimeForExtension(String ext) {
    return switch (ext.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      _ => 'application/$ext',
    };
  }

  Future<void> _onSendTap() async {
    final payload = _buildPayload();
    if (payload == null || payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a message or attach content')),
      );
      return;
    }

    final mode = await showPhysicalModePicker(
      context,
      title: 'Choose transmission mode',
      subtitle: 'How should this message travel to nearby devices?',
    );
    if (mode == null || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SendTransmitScreen(mode: mode, payload: payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const BrandedTitle('Compose message')),
      body: PageContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'What would you like to share?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your content stays on nearby devices — no account or network needed.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _textController,
                      minLines: 5,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message or paste a link…',
                        labelText: 'Message',
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainer,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Add something else',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose one item to send instead of your message.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _AttachChip(
                          icon: Icons.photo_outlined,
                          label: 'Image',
                          onTap: () =>
                              _pickFile(FileType.image, ChatMessageType.image),
                        ),
                        _AttachChip(
                          icon: Icons.videocam_outlined,
                          label: 'Video',
                          onTap: () =>
                              _pickFile(FileType.video, ChatMessageType.video),
                        ),
                        _AttachChip(
                          icon: Icons.link,
                          label: 'Link',
                          onTap: _promptLink,
                        ),
                        _AttachChip(
                          icon: Icons.collections_outlined,
                          label: 'Demo samples',
                          onTap: _pickSample,
                        ),
                      ],
                    ),
                    if (_attachment != null) ...[
                      const SizedBox(height: 16),
                      _AttachmentPreview(
                        payload: _attachment!,
                        onRemove: () => setState(() => _attachment = null),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _onSendTap,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Choose how to send'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptLink() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add link'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final normalized = url.startsWith('http') ? url : 'https://$url';
    setState(() {
      _attachment = ComposePayload(
        type: ChatMessageType.link,
        data: Uint8List.fromList(normalized.codeUnits),
        text: normalized,
      );
      _textController.clear();
    });
  }
}

class _AttachChip extends StatelessWidget {
  const _AttachChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SamplePickerSheet extends StatefulWidget {
  const _SamplePickerSheet();

  @override
  State<_SamplePickerSheet> createState() => _SamplePickerSheetState();
}

class _SamplePickerSheetState extends State<_SamplePickerSheet> {
  late final Future<List<(SampleMedia, int)>> _items = _loadWithSizes();

  static Future<List<(SampleMedia, int)>> _loadWithSizes() async {
    final samples = await loadSampleMediaCatalog();
    return Future.wait(samples.map((s) async => (s, (await s.load()).length)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => FutureBuilder(
        future: _items,
        builder: (context, snapshot) {
          final items = snapshot.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('Demo samples', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Built-in test files. Anything here works over Light; '
                'keep Sound to about 2 KB.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                ),
              ),
              for (final type in [
                ChatMessageType.image,
                ChatMessageType.video,
              ]) ...[
                const SizedBox(height: 16),
                Text(
                  type == ChatMessageType.image
                      ? 'Photos'
                      : 'Videos with sound',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final (sample, bytes) in items.where(
                  (e) => e.$1.type == type,
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox.square(
                      dimension: 48,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: sample.type == ChatMessageType.image
                            ? Image.asset(sample.assetPath, fit: BoxFit.cover)
                            : ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.play_circle_outline),
                              ),
                      ),
                    ),
                    title: Text(sample.title),
                    subtitle: Text(
                      '${(bytes / 1024).toStringAsFixed(1)} KB · '
                      '${sample.fileName.split('.').last.toUpperCase()}',
                    ),
                    onTap: () => Navigator.pop(context, sample),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.payload, required this.onRemove});

  final ComposePayload payload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(switch (payload.type) {
                ChatMessageType.image => Icons.image,
                ChatMessageType.video => Icons.videocam,
                ChatMessageType.link => Icons.link,
                _ => Icons.attach_file,
              }, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(payload.preview, overflow: TextOverflow.ellipsis),
                  Text(
                    '${(payload.byteSize / 1024).toStringAsFixed(1)} KB',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: 'Remove attachment',
            ),
          ],
        ),
      ),
    );
  }
}
