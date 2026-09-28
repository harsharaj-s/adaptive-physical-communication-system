import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_frame.dart';
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
                  Icon(tx.silent ? Icons.hearing_disabled : Icons.volume_up,
                      size: 18, color: Colors.amberAccent),
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
                tx.silent
                    ? 'Playing 18–20 kHz tones — you will not hear them. Media '
                        'volume up, speaker towards the other phone. About '
                        '${tx.estimateSeconds.round()}s if it is heard cleanly.'
                    : 'Turn the volume up and point the speaker at the other '
                        'phone. About ${tx.estimateSeconds.round()}s if it is '
                        'heard cleanly.',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Band and speed picker for the sound channel.
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

  static String _rate(AcousticTxProfile p) {
    final bps = p.netBytesPerSecond();
    return bps < 10 ? bps.toStringAsFixed(1) : bps.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sound band',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        SegmentedButton<AcousticBand>(
          segments: const [
            ButtonSegment(
              value: AcousticBand.audible,
              icon: Icon(Icons.graphic_eq, size: 16),
              label: Text('Audible'),
            ),
            ButtonSegment(
              value: AcousticBand.nearUltrasonic,
              icon: Icon(Icons.hearing_disabled, size: 16),
              label: Text('Silent'),
            ),
          ],
          selected: {selected.band},
          onSelectionChanged: enabled
              ? (set) {
                  if (set.isEmpty || set.first == selected.band) return;
                  onChanged(AcousticTxProfile.defaultFor(set.first));
                }
              : null,
        ),
        const SizedBox(height: 12),
        const Text(
          'Speed',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile
                in AcousticTxProfile.forBand(selected.band).reversed)
              ChoiceChip(
                label: Text('${profile.label} · ${_rate(profile)} B/s'),
                selected: profile == selected,
                onSelected: enabled ? (_) => onChanged(profile) : null,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${selected.conditionHint}. The receiving phone detects the band '
          'and speed by itself.',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

/// How one sound frame spends its airtime, and what a payload will cost.
///
/// Segments are drawn by time on air, not bytes, so the marker shows up at
/// its true share and parity reads as the price of surviving a noisy room.
class AcousticFrameBreakdown extends StatelessWidget {
  const AcousticFrameBreakdown({
    super.key,
    required this.profile,
    required this.envelopeBytes,
  });

  final AcousticTxProfile profile;
  final int envelopeBytes;

  @override
  Widget build(BuildContext context) {
    final codec = profile.buildCodec();
    final byteSamples = codec.samplesPerSymbol * 2 / profile.groups;
    final segments = <(String, Color, double)>[
      ('Marker', Colors.purpleAccent, codec.samplesPerMarker.toDouble()),
      ('Header', Colors.cyanAccent, acousticHeaderSize * byteSamples),
      ('Message', Colors.blueGrey, profile.blockLen * byteSamples),
      ('CRC', Colors.greenAccent, acousticCrcSize * byteSamples),
      ('Parity', Colors.orangeAccent, profile.parityBytes * byteSamples),
    ];
    final total = segments.fold<double>(0, (a, s) => a + s.$3);
    final k = envelopeBytes <= 0
        ? 1
        : (envelopeBytes / profile.blockLen).ceil();
    final frameSeconds = profile.frameSeconds();
    final label = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: Colors.white54, letterSpacing: 0.8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FRAME TO BE SENT', style: label),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final s in segments)
                  Expanded(
                    flex: (s.$3 / total * 1000).round().clamp(1, 1000),
                    child: ColoredBox(color: s.$2.withValues(alpha: 0.75)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.$2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${s.$1} ${(s.$3 / total * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _stat(label, 'TONES',
                '${(codec.lowestHz / 1000).toStringAsFixed(1)}–'
                    '${(codec.highestHz / 1000).toStringAsFixed(1)} kHz'),
            _stat(label, 'FRAME', '${frameSeconds.toStringAsFixed(1)} s'),
            _stat(
              label,
              k == 1 ? 'FRAMES' : 'FRAMES (MIN)',
              '$k · ${(k * frameSeconds).toStringAsFixed(1)} s',
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(TextStyle? label, String title, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: label),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      );
}
