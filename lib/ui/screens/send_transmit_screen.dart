import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/application/app_controller.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/platform/vibration_transmitter_state.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/models/compose_payload.dart';
import 'package:adaptive_physical_communication/ui/models/physical_channel_mode.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_transmitter_state.dart';
import 'package:adaptive_physical_communication/ui/widgets/acoustic_transfer_hud.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_transfer_hud.dart';

/// Channel-specific transmit UI after mode selection (Light / Sound / Vibrate).
class SendTransmitScreen extends StatefulWidget {
  const SendTransmitScreen({
    super.key,
    required this.mode,
    required this.payload,
  });

  final PhysicalChannelMode mode;
  final ComposePayload payload;

  @override
  State<SendTransmitScreen> createState() => _SendTransmitScreenState();
}

class _SendTransmitScreenState extends State<SendTransmitScreen> {
  _TxPhase _phase = _TxPhase.ready;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppProvider.of(context);
      app.configurePhysicalFlow(
        role: EndpointRole.sender,
        channel: widget.mode.channelId,
      );
      // Auto picks the sparsest QR that keeps the transfer short; dense codes
      // were what made real cameras miss most frames.
      if (widget.mode == PhysicalChannelMode.light) {
        app.setOpticalTxProfile(OpticalTxProfile.auto);
      }
    });
  }

  Future<void> _startTransmit() async {
    final app = AppProvider.of(context);
    setState(() {
      _phase = _TxPhase.transmitting;
      _errorMessage = null;
    });

    final success = await app.sendPhysicalMessage(
      payload: widget.payload,
      channel: widget.mode.channelId,
    );

    if (!mounted) return;
    // Light streams until the user taps Stop (or the safety cap): the sender
    // cannot know whether the receiver finished, so it never claims success.
    if (widget.mode == PhysicalChannelMode.light &&
        (success || app.cancelRequested)) {
      setState(() => _phase = _TxPhase.stopped);
      return;
    }
    if (app.cancelRequested) {
      setState(() => _phase = _TxPhase.ready);
      return;
    }
    setState(() {
      _phase = success ? _TxPhase.success : _TxPhase.error;
      if (!success) _errorMessage = app.statusMessage;
    });
  }

  Future<void> _cancel() async {
    AppProvider.of(context).requestCancelTransfer();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppProvider.of(context);
    final theme = Theme.of(context);
    final mode = widget.mode;

    return PopScope(
      canPop: _phase != _TxPhase.transmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _TxPhase.transmitting) {
          _cancel();
        }
      },
      child: Scaffold(
        backgroundColor: mode == PhysicalChannelMode.light && _phase == _TxPhase.transmitting
            ? Colors.white
            : null,
        appBar: AppBar(
          backgroundColor: mode == PhysicalChannelMode.light && _phase == _TxPhase.transmitting
              ? Colors.white
              : null,
          foregroundColor: mode == PhysicalChannelMode.light && _phase == _TxPhase.transmitting
              ? Colors.black87
              : null,
          // The mark's white centre would vanish on the white Light TX bar.
          title: mode == PhysicalChannelMode.light && _phase == _TxPhase.transmitting
              ? Text('Send via ${mode.label}')
              : BrandedTitle('Send via ${mode.label}'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _cancel,
          ),
        ),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            return PageContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildBody(context, app, theme)),
                  if (_phase != _TxPhase.transmitting || mode != PhysicalChannelMode.light)
                    _buildBottomActions(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppController app, ThemeData theme) {
    return switch (_phase) {
      _TxPhase.ready => _ReadyBody(mode: widget.mode, payload: widget.payload),
      _TxPhase.transmitting => _TransmittingBody(mode: widget.mode, app: app),
      _TxPhase.success => _ResultBody(
          icon: Icons.check_circle,
          color: Colors.lightGreenAccent,
          title: 'Sent successfully',
          subtitle: app.statusMessage,
        ),
      _TxPhase.stopped => _ResultBody(
          icon: Icons.stop_circle_outlined,
          color: Colors.lightBlueAccent,
          title: 'Streaming stopped',
          subtitle: app.statusMessage,
        ),
      _TxPhase.error => _ResultBody(
          icon: Icons.error_outline,
          color: Colors.redAccent,
          title: 'Send failed',
          subtitle: _errorMessage ?? app.statusMessage,
        ),
    };
  }

  Widget _buildBottomActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: switch (_phase) {
        _TxPhase.ready => FilledButton.icon(
            onPressed: _startTransmit,
            icon: Icon(_actionIcon(widget.mode)),
            label: Text(_actionLabel(widget.mode)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        _TxPhase.transmitting => OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancel transmission'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        _TxPhase.success => FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        _TxPhase.stopped => Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Receiver shows DONE'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startTransmit,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume streaming'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        _TxPhase.error => Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() => _phase = _TxPhase.ready),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
      },
    );
  }

  static IconData _actionIcon(PhysicalChannelMode mode) => switch (mode) {
        PhysicalChannelMode.light => Icons.grid_view_rounded,
        PhysicalChannelMode.sound => Icons.play_arrow_rounded,
        PhysicalChannelMode.vibrate => Icons.vibration,
      };

  static String _actionLabel(PhysicalChannelMode mode) => switch (mode) {
        PhysicalChannelMode.light => 'Show QR & send',
        PhysicalChannelMode.sound => 'Play & send',
        PhysicalChannelMode.vibrate => 'Start vibration',
      };
}

enum _TxPhase { ready, transmitting, success, stopped, error }

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.mode, required this.payload});

  final PhysicalChannelMode mode;
  final ComposePayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppProvider.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(mode.icon, size: 44, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              _readyTitle(mode),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                mode.subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70, height: 1.45),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.outgoing_mail),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            payload.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (mode == PhysicalChannelMode.light && payload.byteSize > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${(payload.byteSize / 1000).toStringAsFixed(payload.byteSize >= 100000 ? 0 : 1)} KB · Fountain QR'
                              ' · ${app.opticalTxProfile.resolveFor(payload.byteSize).blockLen} B/frame'
                              ' · ~${app.opticalTxProfile.estimatedSeconds(payload.byteSize)}s',
                              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white54),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (mode == PhysicalChannelMode.light) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tips for a smooth transfer',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('• Screen goes to full brightness automatically', style: TextStyle(color: Colors.white70)),
                      const Text('• Receiver 15–25 cm away, QR inside its square', style: TextStyle(color: Colors.white70)),
                      const Text('• Hold steady — rest elbows or lean phones on something', style: TextStyle(color: Colors.white70)),
                      const Text('• Keep streaming until the receiver shows DONE', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      Text('QR density', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 6),
                      SegmentedButton<OpticalTxProfile>(
                        segments: [
                          for (final p in OpticalTxProfile.values)
                            ButtonSegment(
                              value: p,
                              label: Text(p.label, style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                        selected: {app.opticalTxProfile},
                        onSelectionChanged: (set) {
                          if (set.isNotEmpty) app.setOpticalTxProfile(set.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (mode == PhysicalChannelMode.sound) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tips for a smooth transfer',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('• Volume up, speaker facing the receiver',
                          style: TextStyle(color: Colors.white70)),
                      const Text('• Works across a table; quieter is faster',
                          style: TextStyle(color: Colors.white70)),
                      const Text('• Lost frames are OK — fountain recovers',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      AcousticProfilePicker(
                        selected: app.acousticTxProfile,
                        onChanged: app.setAcousticTxProfile,
                      ),
                      if (payload.byteSize > 0) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${payload.byteSize} B · '
                          '~${app.acousticEtaSeconds(payload.byteSize)}s',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.white54),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (!mode.supportsBroadcast) ...[
              const SizedBox(height: 16),
              const StatusChip(
                label: 'Contact required — 1:1 only',
                icon: Icons.touch_app,
                tone: StatusTone.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _readyTitle(PhysicalChannelMode mode) => switch (mode) {
        PhysicalChannelMode.light => 'Ready to transmit via QR',
        PhysicalChannelMode.sound => 'Ready to play',
        PhysicalChannelMode.vibrate => 'Ready to vibrate',
      };
}

class _TransmittingBody extends StatelessWidget {
  const _TransmittingBody({required this.mode, required this.app});

  final PhysicalChannelMode mode;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      PhysicalChannelMode.light => _OpticalTxView(app: app),
      PhysicalChannelMode.sound => _SoundTxView(app: app),
      PhysicalChannelMode.vibrate => _VibrateTxView(app: app),
    };
  }
}

class _OpticalTxView extends StatelessWidget {
  const _OpticalTxView({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    // Full-bleed QR is drawn by OpticalFountainQrOverlay above the navigator.
    return ListenableBuilder(
      listenable: Listenable.merge([
        opticalTransmitterState,
        app.opticalMetricsNotifier ?? app,
      ]),
      builder: (context, _) {
        final tx = opticalTransmitterState.transmitting;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_2,
              size: 48,
              color: Colors.grey.shade700,
            ),
            const SizedBox(height: 12),
            Text(
              tx
                  ? 'Streaming… tap Stop when the receiver shows DONE'
                  : app.statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Point the receiver camera at this screen',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OpticalTransferHud(
                metrics: app.opticalTransferMetrics,
                compact: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SoundTxView extends StatelessWidget {
  const _SoundTxView({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: acousticTransmitterState,
      builder: (context, _) {
        final tx = acousticTransmitterState;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulsingIcon(
                icon: Icons.graphic_eq,
                color: Colors.lightBlueAccent,
                active: app.running || tx.playing,
              ),
              const SizedBox(height: 24),
              Text(
                'Playing acoustic tones…',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                // There is no return path, so the sender genuinely cannot tell
                // when the receiver is done — say so rather than guess.
                'Volume up, speaker facing the other phone. Keep playing '
                'until the other device says it has the message.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              AcousticTxProgressCard(onCancel: app.cancelAcousticTransmit),
              if (!tx.playing && app.senderSnapshot?.progress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: LinearProgressIndicator(
                    value: app.senderSnapshot!.progress!.progressPercent / 100,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VibrateTxView extends StatelessWidget {
  const _VibrateTxView({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vibrationTransmitterState,
      builder: (context, _) {
        final active = vibrationTransmitterState.transmitting || vibrationTransmitterState.vibrating;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulsingIcon(icon: Icons.vibration, color: Colors.purpleAccent, active: active),
              const SizedBox(height: 24),
              Text(
                active ? 'Vibrating…' : 'Transmitting…',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Hold phones together — vibration is contact-only (1:1)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({
    required this.icon,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: CircleAvatar(
        radius: 52,
        backgroundColor: widget.color.withValues(alpha: 0.15),
        child: Icon(widget.icon, size: 52, color: widget.color),
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
