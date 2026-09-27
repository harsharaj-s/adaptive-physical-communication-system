import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/simulation/scenarios.dart';
import 'package:adaptive_physical_communication/core/simulation/simulation_orchestrator.dart';

void main() {
  test('optical always good scenario completes', () async {
    final scenario = getScenario('optical-always-good')!;
    final orchestrator = SimulationOrchestrator(scenario.createPair());
    final result = await orchestrator.runTransfer(generateTestData(1024));
    expect(result.dataMatch, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('acoustic always good scenario completes', () async {
    final scenario = getScenario('acoustic-always-good')!;
    final orchestrator = SimulationOrchestrator(scenario.createPair());
    final result = await orchestrator.runTransfer(generateTestData(scenario.dataSize));
    expect(result.dataMatch, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('random loss scenario completes with retransmission', () async {
    final scenario = getScenario('random-loss')!;
    final orchestrator = SimulationOrchestrator(scenario.createPair());
    final result = await orchestrator.runTransfer(generateTestData(1024));
    expect(result.dataMatch, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
