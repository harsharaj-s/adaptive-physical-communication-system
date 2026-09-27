import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/application/app_controller.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/platform/vibration_transmitter_state.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';
import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/ui/widgets/log_panel.dart';

class HardwareScreen extends StatefulWidget {
  const HardwareScreen({super.key});

  @override
  State<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends State<HardwareScreen> {
  final _messageController = TextEditingController(text: 'HELLO');
  AppController? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppProvider.of(context);
  }

  @override
  void dispose() {
    _app?.stopHardwareChannels();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppProvider.of(context);

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final optical = app.opticalChannel;
        final busy = app.running;
        final wide = isWideLayout(context);
        final cameraActive = app.cameraActive;

        return Scaffold(
      appBar: AppBar(
        title: const BrandedTitle('Hardware Channels'),
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            onPressed: busy ? null : app.clearLogs,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: PageContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isPhysicalChannelSupported)
                      const SectionCard(
                        title: 'Not Available',
                        icon: Icons.warning_amber,
                        child: Text(
                          'Physical channels require a phone or Chrome browser on a laptop.',
                        ),
                      )
                    else ...[
                      const PlatformCapabilityBanner(),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'Status',
                        icon: Icons.info_outline,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.statusMessage,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              app.hardwareChannelsActive
                                  ? (cameraActive
                                      ? 'Camera: active (receiver mode)'
                                      : 'TX ready — camera off in sender mode')
                                  : 'Channels off — tap Start, Test, or Send to activate.',
                              style: TextStyle(
                                fontSize: 13,
                                color: app.hardwareChannelsActive
                                    ? (cameraActive
                                        ? Colors.lightGreenAccent
                                        : Colors.white70)
                                    : Colors.amber.shade200,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Optical: sender shows QR codes — many cameras can scan (broadcast).\n'
                              'Acoustic: sender plays FSK tones — nearby mics decode (broadcast).\n'
                              'Vibration: contact-only — use 1:1 mode, not broadcast.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    height: 1.45,
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'Role & Message',
                        icon: Icons.tune,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<EndpointRole>(
                              segments: const [
                                ButtonSegment(
                                  value: EndpointRole.sender,
                                  label: Text('Sender'),
                                  icon: Icon(Icons.upload),
                                ),
                                ButtonSegment(
                                  value: EndpointRole.receiver,
                                  label: Text('Receiver'),
                                  icon: Icon(Icons.download),
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
                                      if (app.hardwareChannelsActive) {
                                        app.restartHardwareChannels();
                                      }
                                    },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _messageController,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'Custom message',
                                border: OutlineInputBorder(),
                                isDense: true,
                                prefixIcon: Icon(Icons.message),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _OpticalSection(
                                optical: optical,
                                cameraActive: cameraActive,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                children: [
                                  _AcousticSection(app: app),
                                  if (isVibrationSupported) ...[
                                    const SizedBox(height: 12),
                                    _VibrationSection(app: app),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _OpticalSection(
                          optical: optical,
                          cameraActive: cameraActive,
                        ),
                        const SizedBox(height: 12),
                        _AcousticSection(app: app),
                        if (isVibrationSupported) ...[
                          const SizedBox(height: 12),
                          _VibrationSection(app: app),
                        ],
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: busy ? null : app.testOpticalFlash,
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text('Test QR'),
                          ),
                          if (isVibrationSupported)
                            FilledButton.icon(
                              onPressed: busy ? null : app.testVibration,
                              icon: const Icon(Icons.vibration),
                              label: const Text('Test Vibrate'),
                            ),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => app.sendHardwareMessage(_messageController.text),
                            icon: const Icon(Icons.send),
                            label: const Text('Send Message'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : app.sendHardwareHello,
                            icon: const Icon(Icons.waving_hand),
                            label: const Text('Send HELLO'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : app.startHardwareChannels,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start'),
                          ),
                          OutlinedButton.icon(
                            onPressed: app.stopHardwareChannels,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : app.restartHardwareChannels,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Restart'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: screenSizeOf(context) == ScreenSize.phone ? 180 : 220,
              child: LogPanel(logs: app.liveLogs),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

class _OpticalSection extends StatelessWidget {
  const _OpticalSection({
    required this.optical,
    required this.cameraActive,
  });

  final HardwareOpticalChannel? optical;
  final bool cameraActive;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Optical Channel',
      subtitle: 'QR code TX · Camera RX',
      icon: Icons.qr_code_2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListenableBuilder(
            listenable: opticalTransmitterState,
            builder: (context, _) {
              final tx = opticalTransmitterState.transmitting;
              final qrTotal = opticalTransmitterState.chunkTotal;
              final qrIndex = opticalTransmitterState.chunkIndex;
              return StatusChip(
                label: tx
                    ? (qrTotal > 1 ? 'QR TX $qrIndex/$qrTotal' : 'QR TX')
                    : cameraActive
                        ? 'RX ${(opticalTransmitterState.confidence * 100).toStringAsFixed(0)}%'
                        : 'Camera off',
                icon: tx ? Icons.qr_code_2 : Icons.camera_alt,
                tone: tx ? StatusTone.warning : StatusTone.info,
              );
            },
          ),
          const SizedBox(height: 12),
          if (cameraActive &&
              optical?.cameraController != null &&
              optical!.cameraController!.value.isInitialized)
            AspectRatio(
              aspectRatio: optical!.cameraController!.value.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CameraPreview(optical!.cameraController!),
              ),
            )
          else
            Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: EmptyState(
                icon: Icons.videocam_off,
                message: cameraActive
                    ? 'Starting camera…'
                    : isPhysicalChannelSupported
                        ? 'Camera off — tap Start as Receiver or Test QR as Sender'
                        : 'Camera unavailable on this platform',
              ),
            ),
        ],
      ),
    );
  }
}

class _AcousticSection extends StatelessWidget {
  const _AcousticSection({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Acoustic Channel',
      subtitle: 'Speaker TX · Microphone RX',
      icon: Icons.graphic_eq,
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.tealAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              app.acousticChannel?.isAvailable() == true
                  ? 'Microphone stream active — keep devices close and reduce noise.'
                  : 'Start channels to enable microphone capture.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _VibrationSection extends StatelessWidget {
  const _VibrationSection({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Vibration Channel',
      subtitle: 'Phone only — motor TX · accelerometer RX',
      icon: Icons.vibration,
      child: ListenableBuilder(
        listenable: vibrationTransmitterState,
        builder: (context, _) {
          return Row(
            children: [
              Icon(
                vibrationTransmitterState.vibrating
                    ? Icons.vibration
                    : Icons.smartphone,
                color: vibrationTransmitterState.vibrating
                    ? Colors.orange
                    : Colors.white54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vibrationTransmitterState.transmitting
                      ? 'Transmitting vibration pattern…'
                      : app.hardwareChannelsActive
                          ? 'Accelerometer: ${vibrationTransmitterState.lastMagnitude.toStringAsFixed(1)}'
                          : 'Stopped — tap Test Vibrate or Start',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
