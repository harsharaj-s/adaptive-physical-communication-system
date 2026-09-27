import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/application/app_controller.dart';
import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/ui/widgets/endpoint_panel.dart';
import 'package:adaptive_physical_communication/ui/widgets/log_panel.dart';

class SimulationScreen extends StatelessWidget {
  const SimulationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppProvider.of(context);

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final wide = isWideLayout(context);

        return Scaffold(
          appBar: AppBar(
            title: const BrandedTitle('Simulation Lab'),
            actions: [
              TextButton.icon(
                onPressed: app.running ? null : app.runAllScenarios,
                icon: const Icon(Icons.playlist_play),
                label: Text(wide ? 'Run All Scenarios' : 'Run All'),
              ),
            ],
          ),
          body: PageContainer(
            child: Column(
              children: [
                _Controls(app: app),
                const SizedBox(height: 12),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(
                              child: EndpointPanel(
                                title: 'Sender (A)',
                                snapshot: app.senderSnapshot,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: EndpointPanel(
                                title: 'Receiver (B)',
                                snapshot: app.receiverSnapshot,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: LogPanel(logs: app.liveLogs)),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              flex: 2,
                              child: EndpointPanel(
                                title: 'Sender (A)',
                                snapshot: app.senderSnapshot,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              flex: 2,
                              child: EndpointPanel(
                                title: 'Receiver (B)',
                                snapshot: app.receiverSnapshot,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(flex: 3, child: LogPanel(logs: app.liveLogs)),
                          ],
                        ),
                ),
                if (app.lastSimResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: StatusChip(
                      label: app.lastSimResult!.success ? 'SUCCESS' : 'FAILED',
                      icon: app.lastSimResult!.success ? Icons.check_circle : Icons.error,
                      tone: app.lastSimResult!.success ? StatusTone.success : StatusTone.error,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);

    return SectionCard(
      title: 'Scenario',
      icon: Icons.science,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: wide ? 320 : double.infinity,
            child: DropdownButtonFormField<String>(
              key: ValueKey(app.scenarioId),
              isExpanded: true,
              initialValue: app.scenarioId,
              decoration: const InputDecoration(
                labelText: 'Scenario',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: app.availableScenarios
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: app.running
                  ? null
                  : (v) {
                      if (v != null) app.setScenario(v);
                    },
            ),
          ),
          FilledButton.icon(
            onPressed: app.running ? null : app.runSimulation,
            icon: app.running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(app.running ? 'Running…' : 'Run Simulation'),
          ),
          OutlinedButton.icon(
            onPressed: app.running ? null : app.clearLogs,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear Logs'),
          ),
        ],
      ),
    );
  }
}
