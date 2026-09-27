import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_receiver_state.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_transmitter_state.dart';

/// Receive progress for the sound channel.
///
/// Shows blocks recovered rather than bytes, because the fountain code means
/// any frame helps and no particular frame is required — a byte counter would
/// suggest an ordering that does not exist.
class AcousticRxProgressCard extends StatelessWidget {
  const AcousticRxProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: acousticReceiverState,
      builder: (context, _) {
        final rx = acousticReceiverState;
        if (!rx.transferActive) return const SizedBox.shrink();

        final percent = (rx.transferFraction * 100).round();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.graphic_eq,
                      size: 18, color: Colors.lightBlueAccent),
                  const SizedBox(width: 8),
                  Text(
                    rx.profileLabel.isEmpty
                        ? 'Receiving over sound'
                        : 'Receiving over sound · ${rx.profileLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text('$percent%',
                      style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: rx.transferFraction,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(
                    Colors.lightBlueAccent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${rx.collected} of ${rx.needed} blocks · '
                '${rx.framesRepaired} frames read'
                '${rx.framesRejected > 0 ? " · ${rx.framesRejected} too damaged" : ""}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'Keep the sender playing until this completes.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Playback progress for the sound channel.
class AcousticTxProgressCard extends StatelessWidget {
  const AcousticTxProgressCard({super.key, this.onCancel});

  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: acousticTransmitterState,
      builder: (context, _) {
        final tx = acousticTransmitterState;
        if (!tx.playing) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.volume_up, size: 18, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Playing ${tx.totalBytes} B · ${tx.profileLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Stop'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: tx.fraction == 0 ? null : tx.fraction,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Turn the volume up and point the speaker at the other phone. '
                'About ${tx.estimateSeconds.round()}s if it is heard cleanly.',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Speed-versus-robustness picker for the sound channel.
class AcousticProfilePicker extends StatelessWidget {
  const AcousticProfilePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final AcousticTxProfile selected;
  final ValueChanged<AcousticTxProfile> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sound speed',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile in AcousticTxProfile.values.reversed)
              ChoiceChip(
                label: Text(
                  '${profile.label} · '
                  '${profile.netBytesPerSecond().round()} B/s',
                ),
                selected: profile == selected,
                onSelected: enabled ? (_) => onChanged(profile) : null,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${selected.conditionHint}. The receiving phone detects the speed '
          'by itself.',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}
