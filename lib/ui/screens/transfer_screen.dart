import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/application/app_controller.dart';
import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/manager/transfer_manager.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';
import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/ui/widgets/chat_bubble.dart';
import 'package:adaptive_physical_communication/ui/widgets/chat_input_bar.dart';
import 'package:adaptive_physical_communication/ui/widgets/endpoint_panel.dart';
import 'package:adaptive_physical_communication/ui/widgets/log_panel.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_camera_preview.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppProvider.of(context);
      app.addListener(_onAppChanged);
      _lastMessageCount = app.chatMessages.length;
    });
  }

  @override
  void dispose() {
    try {
      AppProvider.of(context).removeListener(_onAppChanged);
    } catch (_) {}
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onAppChanged() {
    final app = AppProvider.of(context);
    final count = app.chatMessages.length;
    if (count > _lastMessageCount) {
      _lastMessageCount = count;
      _scrollToBottom();
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppProvider.of(context);

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final busy = app.running;
        final wide = isWideLayout(context);

        return Scaffold(
          appBar: AppBar(
            title: BrandedTitle(
              'Messages',
              subtitle: Text(
                _connectionLabel(app),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Connection & logs',
                icon: const Icon(Icons.tune),
                onPressed: () => _openConnectionSheet(context, app, wide),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'clear_chat') app.clearChat();
                  if (v == 'clear_logs') app.clearLogs();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'clear_chat', child: Text('Clear chat')),
                  const PopupMenuItem(value: 'clear_logs', child: Text('Clear logs')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _RoleModeBar(app: app, busy: busy),
              _ConnectionStatusBanner(app: app, busy: busy),
              if (app.role == EndpointRole.receiver &&
                  app.mode == OperationMode.hardware &&
                  app.hardwareChannelsActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: OpticalCameraPreview(
                    controller: app.opticalChannel?.cameraController,
                    height: screenSizeOf(context) == ScreenSize.phone ? 160 : 200,
                  ),
                ),
              Expanded(
                child: _ChatArea(
                  app: app,
                  scrollController: _scrollController,
                ),
              ),
              if (app.mode == OperationMode.hardware && app.hardwareChannelsActive)
                _LivePairingHint(app: app),
              ChatInputBar(
                controller: _messageController,
                enabled: !busy && (app.role == EndpointRole.sender || app.mode == OperationMode.simulation),
                hintText: !busy && app.role == EndpointRole.receiver && app.mode == OperationMode.hardware
                    ? 'Receiver mode — waiting for incoming messages'
                    : 'Type a message…',
                onSend: () => _sendText(app),
                onPickImage: () => _pickFile(app, FileType.image, ChatMessageType.image),
                onPickVideo: () => _pickFile(app, FileType.video, ChatMessageType.video),
                onPickFile: () => _pickFile(app, FileType.any, ChatMessageType.file),
              ),
            ],
          ),
        );
      },
    );
  }

  String _connectionLabel(AppController app) {
    final role = app.role == EndpointRole.sender ? 'Sender' : 'Receiver';
    final mode = app.mode == OperationMode.hardware ? 'Hardware' : 'Simulation';
    final txMode = app.mode == OperationMode.hardware
        ? (app.transferMode == TransferMode.broadcast ? ' · Broadcast' : ' · 1:1')
        : '';
    return '$role · $mode$txMode · $platformCapabilityLabel';
  }

  Future<void> _sendText(AppController app) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await app.sendChatText(text);
    _scrollToBottom();
  }

  Future<void> _pickFile(
    AppController app,
    FileType pickerType,
    ChatMessageType chatType,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: pickerType,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final maxBytes = app.mode == OperationMode.hardware ? 512 * 1024 : 2 * 1024 * 1024;
    if (bytes.length > maxBytes && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large file'),
          content: Text(
            'This file is ${(bytes.length / 1024).toStringAsFixed(0)} KB. '
            'Physical channels are slow — transfer may take a long time or fail. Continue?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await app.sendChat(
      type: chatType,
      payload: Uint8List.fromList(bytes),
      fileName: file.name,
      mimeType: file.extension != null ? 'application/${file.extension}' : null,
    );
    _scrollToBottom();
  }

  void _openConnectionSheet(BuildContext context, AppController app, bool wide) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: app,
        builder: (ctx, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: wide ? 0.85 : 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: pagePadding(context),
            child: _ConnectionPanel(app: app, wide: wide),
          ),
        ),
      ),
    );
  }
}

class _RoleModeBar extends StatelessWidget {
  const _RoleModeBar({required this.app, required this.busy});

  final AppController app;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final onPhone = screenSizeOf(context) == ScreenSize.phone;

    Widget roleToggle({required double? width}) {
      final button = SegmentedButton<EndpointRole>(
        segments: const [
          ButtonSegment(
            value: EndpointRole.sender,
            label: Text('Send'),
            icon: Icon(Icons.upload, size: 18),
          ),
          ButtonSegment(
            value: EndpointRole.receiver,
            label: Text('Receive'),
            icon: Icon(Icons.download, size: 18),
          ),
        ],
        selected: {app.role},
        showSelectedIcon: true,
        emptySelectionAllowed: false,
        onSelectionChanged: busy
            ? null
            : (selection) {
                if (selection.isEmpty) return;
                app.setRole(selection.first);
              },
      );
      return width != null ? SizedBox(width: width, child: button) : button;
    }

    Widget modeToggle({required double? width}) {
      final button = SegmentedButton<OperationMode>(
        segments: [
          const ButtonSegment(value: OperationMode.simulation, label: Text('Sim')),
          ButtonSegment(
            value: OperationMode.hardware,
            label: const Text('Live'),
            enabled: isPhysicalChannelSupported,
          ),
        ],
        selected: {app.mode},
        showSelectedIcon: true,
        emptySelectionAllowed: false,
        onSelectionChanged: busy
            ? null
            : (selection) {
                if (selection.isEmpty) return;
                app.setMode(selection.first);
              },
      );
      return width != null ? SizedBox(width: width, child: button) : button;
    }

    Widget broadcastToggle({required double? width}) {
      final button = SegmentedButton<TransferMode>(
        segments: const [
          ButtonSegment(
            value: TransferMode.broadcast,
            label: Text('Broadcast'),
            icon: Icon(Icons.cell_tower, size: 18),
          ),
          ButtonSegment(
            value: TransferMode.unicast,
            label: Text('1:1'),
            icon: Icon(Icons.link, size: 18),
          ),
        ],
        selected: {app.transferMode},
        showSelectedIcon: true,
        emptySelectionAllowed: false,
        onSelectionChanged: busy
            ? null
            : (selection) {
                if (selection.isEmpty) return;
                app.setTransferMode(selection.first);
              },
      );
      return width != null ? SizedBox(width: width, child: button) : button;
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onPhone) ...[
              roleToggle(width: null),
              const SizedBox(height: 8),
              modeToggle(width: null),
              if (app.mode == OperationMode.hardware) ...[
                const SizedBox(height: 8),
                broadcastToggle(width: null),
              ],
            ] else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  roleToggle(width: 240),
                  modeToggle(width: 180),
                  if (app.mode == OperationMode.hardware)
                    broadcastToggle(width: 260),
                ],
              ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusBanner extends StatefulWidget {
  const _ConnectionStatusBanner({required this.app, required this.busy});

  final AppController app;
  final bool busy;

  @override
  State<_ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<_ConnectionStatusBanner> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(_ConnectionStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.lastIncomingAt != widget.app.lastIncomingAt) {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final last = widget.app.lastIncomingAt;
    if (last == null) return;
    _refreshTimer = Timer(const Duration(seconds: 9), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final busy = widget.busy;
    if (app.mode != OperationMode.hardware) return const SizedBox.shrink();

    final isReceiver = app.role == EndpointRole.receiver;
    final recentlyReceived = app.lastIncomingAt != null &&
        DateTime.now().difference(app.lastIncomingAt!).inSeconds < 8;

    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    if (busy) {
      bg = Colors.amber.withValues(alpha: 0.14);
      fg = Colors.amberAccent;
      icon = Icons.sync;
      title = isReceiver ? 'Receiving…' : 'Sending…';
      subtitle = app.statusMessage;
    } else if (recentlyReceived && isReceiver) {
      bg = Colors.lightGreenAccent.withValues(alpha: 0.14);
      fg = Colors.lightGreenAccent;
      icon = Icons.check_circle;
      title = 'Message received';
      subtitle = '${app.incomingMessageCount} message(s) via physical channel';
    } else if (app.hardwareChannelsActive && isReceiver) {
      bg = Colors.blue.withValues(alpha: 0.12);
      fg = Colors.lightBlueAccent;
      icon = Icons.hearing;
      title = app.transferMode == TransferMode.broadcast ? 'Listening (broadcast)' : 'Listening';
      subtitle = app.transferMode == TransferMode.broadcast
          ? 'Any number of receivers can decode — aim camera at sender QR or stay within earshot'
          : 'Mic & camera active — hold phones close or aim camera at sender';
    } else if (app.hardwareChannelsActive) {
      bg = Colors.orange.withValues(alpha: 0.12);
      fg = Colors.orangeAccent;
      icon = Icons.upload;
      title = app.transferMode == TransferMode.broadcast ? 'Broadcast ready' : 'Sender ready';
      subtitle = app.transferMode == TransferMode.broadcast
          ? 'Send once — all receivers in Live + Receive mode get the message'
          : 'Tap send — receiver must be in Receive + Live mode';
    } else {
      bg = Colors.white.withValues(alpha: 0.06);
      fg = Colors.white70;
      icon = Icons.link_off;
      title = 'Channels starting…';
      subtitle = app.statusMessage;
    }

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: 13)),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.85), height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatArea extends StatelessWidget {
  const _ChatArea({
    required this.app,
    required this.scrollController,
  });

  final AppController app;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final messages = app.chatMessages;

    if (messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'Physical messaging — no internet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            platformCapabilitySummary,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54, height: 1.45),
          ),
          const SizedBox(height: 20),
          const PairingInstructionsCard(),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How to send', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _step('1', 'Set one device to Sender, others to Receiver'),
                  _step('2', 'Choose Live mode + Broadcast (one sender → many receivers)'),
                  _step('3', 'All receivers: Live + Receive — channels auto-start'),
                  _step('4', 'Sender: type a message and tap send'),
                  _step('5', 'Optical: receivers aim cameras at sender QR; acoustic: stay within 30 cm'),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final isNewIncoming = !msg.isOutgoing &&
            app.lastIncomingAt != null &&
            msg.timestamp.difference(app.lastIncomingAt!).inSeconds.abs() < 2;
        return _AnimatedIncomingBubble(
          key: ValueKey(msg.id),
          highlight: isNewIncoming,
          child: ChatBubble(message: msg),
        );
      },
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text(n, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ],
      ),
    );
  }
}

class _AnimatedIncomingBubble extends StatefulWidget {
  const _AnimatedIncomingBubble({
    super.key,
    required this.child,
    required this.highlight,
  });

  final Widget child;
  final bool highlight;

  @override
  State<_AnimatedIncomingBubble> createState() => _AnimatedIncomingBubbleState();
}

class _AnimatedIncomingBubbleState extends State<_AnimatedIncomingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
    if (!widget.highlight) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.lightGreenAccent.withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LivePairingHint extends StatelessWidget {
  const _LivePairingHint({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final isSender = app.role == EndpointRole.sender;
    final isBroadcast = app.transferMode == TransferMode.broadcast;
    final text = isSender
        ? (isBroadcast
            ? 'Broadcast sender: QR codes on screen or speaker tones — all nearby receivers decode the same message.'
            : 'Sender: keep phones within 30 cm. You will hear tones (acoustic) or see QR codes (optical).')
        : (isBroadcast
            ? 'Broadcast receiver: point camera at sender QR OR hold within earshot. Multiple phones can receive simultaneously.'
            : 'Receiver: point camera at sender QR code OR hold phones close to hear tones.');

    return Material(
      color: Colors.green.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isSender ? Icons.upload : Icons.download,
              size: 18,
              color: Colors.lightGreenAccent,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.app, required this.wide});

  final AppController app;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connection', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(app.statusMessage, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        const PlatformCapabilityBanner(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (app.mode == OperationMode.hardware) ...[
              FilledButton.icon(
                onPressed: app.running ? null : () => app.startHardwareChannels(forRole: app.role),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start channels'),
              ),
              OutlinedButton.icon(
                onPressed: app.stopHardwareChannels,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
            OutlinedButton.icon(
              onPressed: app.running || app.role != EndpointRole.sender
                  ? null
                  : () => app.sendChatText('HELLO'),
              icon: const Icon(Icons.waving_hand),
              label: const Text('Send HELLO'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (wide)
          SizedBox(
            height: 280,
            child: Row(
              children: [
                Expanded(child: EndpointPanel(title: 'Sender', snapshot: app.senderSnapshot)),
                const SizedBox(width: 8),
                Expanded(child: EndpointPanel(title: 'Receiver', snapshot: app.receiverSnapshot)),
              ],
            ),
          )
        else ...[
          SizedBox(
            height: 160,
            child: EndpointPanel(
              title: app.role == EndpointRole.sender ? 'This device' : 'Remote sender',
              snapshot: app.senderSnapshot,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: EndpointPanel(
              title: app.role == EndpointRole.receiver ? 'This device' : 'Remote receiver',
              snapshot: app.receiverSnapshot,
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(height: wide ? 220 : 180, child: LogPanel(logs: app.liveLogs)),
      ],
    );
  }
}
