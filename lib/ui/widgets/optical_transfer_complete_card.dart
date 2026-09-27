import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';

/// Success card after a fountain QR transfer completes.
class OpticalTransferCompleteCard extends StatelessWidget {
  const OpticalTransferCompleteCard({
    super.key,
    required this.metrics,
    this.onDismiss,
  });

  final OpticalTransferMetrics metrics;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kb = metrics.payloadBytes / 1000.0;
    final secs = metrics.elapsedSec;
    final rate = metrics.goodputKBps;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.lightGreenAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.lightGreenAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.lightGreenAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Transfer complete',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB in '
            '${secs.toStringAsFixed(1)}s'
            '${rate > 0 ? ' (${rate.toStringAsFixed(1)} KB/s)' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
