import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';

/// Compact live stats strip for fountain / optical transfers.
class OpticalTransferHud extends StatelessWidget {
  const OpticalTransferHud({
    super.key,
    required this.metrics,
    this.compact = false,
  });

  final OpticalTransferMetrics metrics;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sid = metrics.sessionId;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _LockChip(locked: metrics.locked, complete: metrics.complete),
              const SizedBox(width: 8),
              if (sid != null)
                Text(
                  'SID $sid',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              const Spacer(),
              Text(
                metrics.profileLabel,
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _Stat('CAP', metrics.captureFps.toStringAsFixed(0)),
              _Stat('DEC', metrics.decodeFps.toStringAsFixed(1)),
              _Stat('DROP', '${metrics.dropped}'),
              _Stat('GOOD', '${metrics.goodputKBps.toStringAsFixed(1)} KB/s'),
              if (!compact)
                _Stat(
                  'NEW/DUP/RED',
                  '${metrics.framesNew}/${metrics.framesDup}/${metrics.framesRed}',
                ),
            ],
          ),
          if (metrics.symbolsNeeded > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: metrics.progress,
                minHeight: 4,
                backgroundColor: Colors.white12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${metrics.symbolsCollected} / ${metrics.symbolsNeeded} symbols'
              '${metrics.blockLen > 0 ? ' · ${metrics.blockLen} B' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60),
            ),
          ],
          if (metrics.stalled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.center_focus_weak,
                  size: 14,
                  color: Colors.amberAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${metrics.locked ? 'Progress kept. ' : ''}No codes '
                    'readable — whole QR inside the square at 15–25 cm, hold '
                    'steady, tap to refocus, or try 2x zoom',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LockChip extends StatelessWidget {
  const _LockChip({required this.locked, required this.complete});

  final bool locked;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final label = complete ? 'DONE' : (locked ? 'LOCK' : 'SCAN');
    final color = complete
        ? Colors.lightGreenAccent
        : (locked ? Colors.lightBlueAccent : Colors.white54);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
