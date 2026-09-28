import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/application/app_controller.dart';
import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_receiver_state.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/platform/vibration_transmitter_state.dart';
import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/models/physical_channel_mode.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/ui/widgets/acoustic_transfer_hud.dart';
import 'package:adaptive_physical_communication/ui/widgets/live_tone_meter.dart';
import 'package:adaptive_physical_communication/ui/widgets/mode_picker_sheet.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_aim_guide.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_camera_preview.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_transfer_complete_card.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_transfer_hud.dart';
import 'package:adaptive_physical_communication/ui/widgets/received_content_view.dart';

/// Receive flow — pick mode, listen, display incoming content.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  PhysicalChannelMode? _mode;
  AppController? _app;

  String? _lastPresentedId;
  ChatMessage? _displayedMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _app = AppProvider.of(context);
      _pickMode();
    });
  }

  @override
  void dispose() {
    _app?.stopListening();
    super.dispose();
  }

  Future<void> _pickMode() async {
    final mode = await showPhysicalModePicker(
      context,
      title: 'Choose receive mode',
      subtitle: 'How should this device listen for messages?',
    );
    if (!mounted) return;
    if (mode == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _mode = mode;
      _displayedMessage = null;
      _lastPresentedId = null;
    });
    await AppProvider.of(context).startListening(mode.channelId);
  }

  void _clearDisplay(AppController app) {
    app.prepareForNextMessage();
    setState(() => _displayedMessage = null);
  }

  ChatMessage? _resolveVisibleMessage(AppController app) {
    final latest = app.latestIncomingMessage;
    if (latest != null && latest.id != _lastPresentedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (latest.id == _lastPresentedId) return;
        setState(() {
          _lastPresentedId = latest.id;
          _displayedMessage = latest;
        });
      });
      return latest;
    }
    return _displayedMessage;
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final app = AppProvider.of(context);
    final mode = _mode!;
    final visible = _resolveVisibleMessage(app);

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final visibleNow = _resolveVisibleMessage(app) ?? visible;
        final showingNow = visibleNow != null;

        return Scaffold(
          appBar: AppBar(
            title: BrandedTitle('Receive via ${mode.label}'),
            actions: [
              IconButton(
                tooltip: 'Change mode',
                icon: const Icon(Icons.tune),
                onPressed: () async {
                  await app.stopListening();
                  await _pickMode();
                },
              ),
            ],
          ),
          body: PageContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ListeningBanner(
                  mode: mode,
                  app: app,
                  showingMessage: showingNow,
                ),
                const SizedBox(height: 12),
                if (showingNow) ...[
                  Expanded(
                    child: _ReceivedMediaPane(message: visibleNow),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    visibleNow.type == ChatMessageType.video
                        ? 'Playing received video — still listening for more'
                        : visibleNow.type == ChatMessageType.image
                            ? 'Photo received — still listening for more'
                            : 'Still listening — send another message anytime',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                        ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _clearDisplay(app),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Clear & keep listening'),
                  ),
                ] else
                  Expanded(
                    child: _ListeningBody(mode: mode, app: app),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full-area media display after a successful receive (photo / video auto-shows).
class _ReceivedMediaPane extends StatelessWidget {
  const _ReceivedMediaPane({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ReceivedContentView(
        message: message,
        compact: false,
      ),
    );
  }
}

class _ListeningBanner extends StatelessWidget {
  const _ListeningBanner({
    required this.mode,
    required this.app,
    required this.showingMessage,
  });

  final PhysicalChannelMode mode;
  final AppController app;
  final bool showingMessage;

  @override
  Widget build(BuildContext context) {
    final listening = app.hardwareChannelsActive && !app.running;
    final csk = app.opticalQrChunkProgress;
    final collecting = csk != null && csk.$1 < csk.$2;
    final acoustic = acousticReceiverState;

    if (mode == PhysicalChannelMode.sound) {
      final (color, icon, title, subtitle) = switch ((
        showingMessage,
        acoustic.phase,
        listening,
      )) {
        (true, _, _) => (
            Colors.lightGreenAccent,
            Icons.check_circle,
            'Message received — still listening',
            app.statusMessage,
          ),
        (_, AcousticRxPhase.decoded, _) => (
            Colors.lightGreenAccent,
            Icons.check_circle,
            'Sound message decoded',
            app.statusMessage,
          ),
        (_, AcousticRxPhase.tonesDetected, _) => (
            Colors.amberAccent,
            Icons.graphic_eq,
            'Tones detected — decoding…',
            'Hold phones close until message appears',
          ),
        (_, AcousticRxPhase.permissionDenied, _) => (
            Colors.redAccent,
            Icons.mic_off,
            'Microphone blocked',
            'Tap Enable microphone below',
          ),
        (_, AcousticRxPhase.starting, _) => (
            Colors.white54,
            Icons.mic,
            'Starting microphone…',
            app.statusMessage,
          ),
        (_, _, true) when app.acousticMicActive => (
            Colors.lightBlueAccent,
            Icons.mic,
            'Mic live — listening for tones',
            'Hold within ~30 cm of sender in a quiet room',
          ),
        (_, _, true) => (
            Colors.orangeAccent,
            Icons.mic_none,
            'Waiting for microphone…',
            app.statusMessage,
          ),
        _ => (
            Colors.white54,
            Icons.hourglass_empty,
            'Starting…',
            app.statusMessage,
          ),
      };

      return _BannerBox(
        color: color,
        icon: icon,
        title: title,
        subtitle: subtitle,
      );
    }

    final (color, icon, title, subtitle) = switch ((
      showingMessage,
      collecting,
      listening,
    )) {
      (true, _, _) => (
          Colors.lightGreenAccent,
          Icons.check_circle,
          'Message received — still listening',
          app.statusMessage,
        ),
      (_, true, _) => (
          Colors.amberAccent,
          Icons.qr_code_scanner,
          'Receiving fountain QR ${csk!.$1} / ${csk.$2} symbols',
          'Keep camera aimed at the sender QR',
        ),
      (_, _, true) => (
          Colors.lightBlueAccent,
          Icons.hearing,
          'Listening on ${mode.label}',
          mode.subtitle,
        ),
      _ => (
          Colors.white54,
          Icons.hourglass_empty,
          'Starting…',
          app.statusMessage,
        ),
    };

    return _BannerBox(
      color: color,
      icon: icon,
      title: title,
      subtitle: subtitle,
    );
  }
}

class _BannerBox extends StatelessWidget {
  const _BannerBox({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListeningBody extends StatelessWidget {
  const _ListeningBody({required this.mode, required this.app});

  final PhysicalChannelMode mode;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      PhysicalChannelMode.light => _LightListenView(app: app),
      PhysicalChannelMode.sound => _SoundListenView(app: app),
      PhysicalChannelMode.vibrate => _VibrateListenView(app: app),
    };
  }
}

class _LightListenView extends StatelessWidget {
  const _LightListenView({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final metricsListenable = app.opticalMetricsNotifier ?? app;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      // Tap to re-run autofocus where the QR is.
                      onTapUp: (d) => app.opticalChannel?.focusAt(
                        Offset(
                          (d.localPosition.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0),
                          (d.localPosition.dy / constraints.maxHeight)
                              .clamp(0.0, 1.0),
                        ),
                      ),
                      child: OpticalCameraPreview(
                        controller: app.opticalChannel?.cameraController,
                        height: constraints.maxHeight,
                      ),
                    ),
                    const OpticalAimGuide(),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _ZoomChips(app: app),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: ListenableBuilder(
                        listenable: metricsListenable,
                        builder: (context, _) {
                          return OpticalTransferHud(
                            metrics: app.opticalTransferMetrics,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: Listenable.merge([
            opticalTransmitterState,
            metricsListenable,
          ]),
          builder: (context, _) {
            final m = app.opticalTransferMetrics;
            if (m.complete && m.payloadBytes > 0) {
              return OpticalTransferCompleteCard(metrics: m);
            }
            final progress = m.symbolsNeeded > 0
                ? m.progress
                : opticalTransmitterState.confidence.clamp(0.0, 1.0);
            final label = m.locked
                ? (m.stalled
                    ? 'Progress kept (${m.symbolsCollected} / ${m.symbolsNeeded}) '
                        '— re-aim: whole QR inside the square, hold steady'
                    : 'Decoding — ${m.symbolsCollected} / ${m.symbolsNeeded} '
                        'symbols · keep steady')
                : opticalTransmitterState.confidence > 0.05
                    ? 'Reading QR…'
                    : 'Hold 15–25 cm away, whole QR inside the square · '
                        'tap to refocus';

            return Column(
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Receive zoom presets. More zoom lets the receiver stand further back,
/// where autofocus works, while the QR still fills the square.
class _ZoomChips extends StatefulWidget {
  const _ZoomChips({required this.app});

  final AppController app;

  @override
  State<_ZoomChips> createState() => _ZoomChipsState();
}

class _ZoomChipsState extends State<_ZoomChips> {
  static const _levels = [1.0, 1.5, 2.0, 3.0];

  @override
  Widget build(BuildContext context) {
    final channel = widget.app.opticalChannel;
    if (channel == null || channel.maxZoom <= 1.01) {
      return const SizedBox.shrink();
    }
    final levels = [
      for (final z in _levels)
        if (z <= channel.maxZoom + 0.01 && z >= channel.minZoom - 0.01) z,
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final z in levels)
            GestureDetector(
              onTap: () async {
                await channel.setZoom(z);
                if (mounted) setState(() {});
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (channel.zoom - z).abs() < 0.05
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${z == z.roundToDouble() ? z.toStringAsFixed(0) : z.toStringAsFixed(1)}x',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: (channel.zoom - z).abs() < 0.05
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SoundListenView extends StatelessWidget {
  const _SoundListenView({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: acousticReceiverState,
      builder: (context, _) {
        final rx = acousticReceiverState;
        final micLive = app.acousticMicActive;
        final input = rx.inputLevel;
        final tone = rx.toneStrength;

        final status = switch (rx.phase) {
          AcousticRxPhase.permissionDenied => 'Microphone permission required',
          AcousticRxPhase.starting => 'Starting microphone…',
          _ when rx.transferActive =>
            'Receiving — ${rx.collected} of ${rx.needed} blocks',
          AcousticRxPhase.tonesDetected => 'Tones detected — decoding message',
          AcousticRxPhase.decoded => 'Message decoded — ready for next',
          AcousticRxPhase.decoding => 'Decoding tones…',
          _ when micLive && input < 0.03 =>
            'Mic live — waiting for audio (speak or play tones nearby)',
          _ when micLive => 'Mic live — listening for sender tones',
          _ => 'Tap Enable microphone if listening does not start',
        };

        return Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MicPulseIcon(
                      active: micLive,
                      detecting: tone > 0.12,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        micLive
                            ? 'Input level shows the mic is working. Point the '
                                'sender\'s speaker this way and turn its volume up. '
                                'Listens for audible and silent (18–20 kHz) '
                                'senders at every speed.'
                            : 'Allow microphone access so this device can hear the sender.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const AcousticRxProgressCard(),
            if (micLive) const LiveToneMeter.hearing(),
            _LevelMeter(
              label: 'Mic input',
              value: input,
              color: micLive ? Colors.lightBlueAccent : Colors.white24,
            ),
            const SizedBox(height: 10),
            _LevelMeter(
              label: 'Tone signal',
              value: tone,
              color: tone > 0.12 ? Colors.amberAccent : Colors.white24,
            ),
            const SizedBox(height: 10),
            _LevelMeter(
              label: 'Silent band 18–20 kHz',
              value: rx.highBandLevel,
              color: rx.highBandLevel > 0.3
                  ? Colors.tealAccent
                  : Colors.white24,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  micLive ? Icons.mic : Icons.mic_off,
                  size: 16,
                  color: micLive ? Colors.lightGreenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  micLive ? 'Microphone streaming' : 'Microphone not active',
                  style: TextStyle(
                    color: micLive ? Colors.lightGreenAccent : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (rx.phase == AcousticRxPhase.permissionDenied ||
                !micLive) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => app.retryAcousticListening(),
                icon: const Icon(Icons.mic),
                label: const Text('Enable microphone'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _MicPulseIcon extends StatefulWidget {
  const _MicPulseIcon({required this.active, required this.detecting});

  final bool active;
  final bool detecting;

  @override
  State<_MicPulseIcon> createState() => _MicPulseIconState();
}

class _MicPulseIconState extends State<_MicPulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.detecting
        ? Colors.amberAccent
        : widget.active
            ? Colors.lightBlueAccent
            : Colors.white38;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.active ? 1.0 + _controller.value * 0.08 : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.45), width: 2),
            ),
            child: Icon(Icons.hearing, size: 56, color: color),
          ),
        );
      },
    );
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white10,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _VibrateListenView extends StatelessWidget {
  const _VibrateListenView({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vibrationTransmitterState,
      builder: (context, _) {
        final mag = vibrationTransmitterState.lastMagnitude;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.vibration,
                size: 72,
                color: Colors.purpleAccent.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 20),
              Text(
                'Detecting vibration…',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Press phones together firmly. Vibration is contact-only '
                  'and best for short text.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
              ),
              if (mag > 0) ...[
                const SizedBox(height: 20),
                Text(
                  'Signal ${(mag * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.purpleAccent),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
