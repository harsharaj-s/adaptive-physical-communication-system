import 'package:flutter/foundation.dart';

import 'package:adaptive_physical_communication/core/simulation/scenarios.dart';
import 'package:adaptive_physical_communication/core/simulation/simulation_orchestrator.dart';

Future<void> main() async {
  final scenario = getScenario('optical-always-good')!;
  final pair = scenario.createPair();
  final orchestrator = SimulationOrchestrator(pair);
  final data = generateTestData(512);
  debugPrint('Starting transfer ${data.length} bytes...');
  final result = await orchestrator.runTransfer(data).timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      debugPrint('TIMEOUT - sender ack: ${pair.endpointA.transport?.lastAckedSequence}');
      debugPrint('receiver buf: ${pair.endpointB.transport?.isTransferComplete()}');
      throw StateError('timeout');
    },
  );
  debugPrint('Done: success=${result.success} ack=${result.senderSnapshot.progress?.acknowledgedPackets}');
}
