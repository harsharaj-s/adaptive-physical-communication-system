import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/ui/models/physical_channel_mode.dart';

/// Bottom sheet for choosing Light / Sound / Vibrate transmission mode.
Future<PhysicalChannelMode?> showPhysicalModePicker(
  BuildContext context, {
  required String title,
  String? subtitle,
}) {
  return showModalBottomSheet<PhysicalChannelMode>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final modes = availablePhysicalModes;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              for (final mode in modes) ...[
                _ModeTile(mode: mode, onTap: () => Navigator.pop(ctx, mode)),
                if (mode != modes.last) const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              Text(
                'Tip: Light uses fountain QR — hold phones 15–25 cm apart.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.onTap});

  final PhysicalChannelMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (mode) {
      PhysicalChannelMode.light => Colors.amberAccent,
      PhysicalChannelMode.sound => Colors.lightBlueAccent,
      PhysicalChannelMode.vibrate => Colors.purpleAccent,
    };

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(mode.icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mode.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.65),
                        height: 1.35,
                      ),
                    ),
                    if (!mode.supportsBroadcast) ...[
                      const SizedBox(height: 6),
                      Text(
                        '1:1 only — phones must touch',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orangeAccent.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
