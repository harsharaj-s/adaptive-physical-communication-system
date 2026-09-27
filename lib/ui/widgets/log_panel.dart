import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/types/types.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';

class LogPanel extends StatelessWidget {
  const LogPanel({
    super.key,
    required this.logs,
    this.emptyMessage,
  });

  final List<LogEntry> logs;
  final String? emptyMessage;

  Color _categoryColor(String category) {
    switch (category) {
      case 'WARNING':
        return Colors.amberAccent;
      case 'ERROR':
        return Colors.redAccent;
      case 'DECISION':
        return Colors.greenAccent;
      case 'SWITCH':
        return Colors.purpleAccent;
      case 'ADAPT':
        return Colors.cyanAccent;
      case 'TRANSFER':
        return Colors.lightBlueAccent;
      default:
        return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  'LIVE LOGS',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (logs.isNotEmpty)
                  StatusChip(
                    label: '${logs.length}',
                    icon: Icons.receipt_long,
                    tone: StatusTone.neutral,
                  ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: logs.isEmpty
                ? EmptyState(
                    icon: Icons.terminal,
                    message: emptyMessage ?? 'Logs will appear here during transfer',
                    subtitle: 'Discovery, channel tests, and transfer events are logged live',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                            children: [
                              TextSpan(
                                text: '[${log.category}] ',
                                style: TextStyle(
                                  color: _categoryColor(log.category),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(text: log.message),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
