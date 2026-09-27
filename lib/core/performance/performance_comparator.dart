import 'package:adaptive_physical_communication/core/simulation/scenarios.dart';
import 'package:adaptive_physical_communication/core/simulation/simulated_medium.dart';
import 'package:adaptive_physical_communication/core/simulation/simulation_orchestrator.dart';

/// Strategy types for performance comparison experiments.
enum TransferStrategy {
  fixedOptical,
  fixedAcoustic,
  staticSwitch,
  adaptive,
}

class StrategyResult {
  const StrategyResult({
    required this.strategy,
    required this.success,
    required this.durationMs,
    required this.throughput,
    required this.packetLoss,
    required this.retransmissions,
    required this.switchCount,
    required this.goodput,
  });

  final TransferStrategy strategy;
  final bool success;
  final int durationMs;
  final double throughput;
  final double packetLoss;
  final int retransmissions;
  final int switchCount;
  final double goodput;
}

/// Runs baseline vs adaptive comparison using simulation.
class PerformanceComparator {
  Future<List<StrategyResult>> runComparison({int dataSize = 4096}) async {
    final results = <StrategyResult>[];

    results.add(await _runAdaptive(dataSize));
    results.add(await _runFixedOptical(dataSize));
    results.add(await _runFixedAcoustic(dataSize));

    return results;
  }

  Future<StrategyResult> _runAdaptive(int dataSize) async {
    final scenario = getScenario('optical-degrades')!;
    final orchestrator = SimulationOrchestrator(scenario.createPair());
    final result = await orchestrator.runTransfer(generateTestData(dataSize));
    return StrategyResult(
      strategy: TransferStrategy.adaptive,
      success: result.success,
      durationMs: result.durationMs,
      throughput: _calcThroughput(result),
      packetLoss: result.senderSnapshot.metrics?.packetLoss ?? 0,
      retransmissions: result.senderSnapshot.progress?.retryCount ?? 0,
      switchCount: result.switchEvents,
      goodput: result.success ? dataSize / (result.durationMs / 1000) : 0,
    );
  }

  Future<StrategyResult> _runFixedOptical(int dataSize) async {
    final pair = createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(packetLossRate: 0.08),
    );
    final orchestrator = SimulationOrchestrator(pair);
    final result = await orchestrator.runTransfer(generateTestData(dataSize));
    return StrategyResult(
      strategy: TransferStrategy.fixedOptical,
      success: result.success,
      durationMs: result.durationMs,
      throughput: _calcThroughput(result),
      packetLoss: result.senderSnapshot.metrics?.packetLoss ?? 0,
      retransmissions: result.senderSnapshot.progress?.retryCount ?? 0,
      switchCount: 0,
      goodput: result.success ? dataSize / (result.durationMs / 1000) : 0,
    );
  }

  Future<StrategyResult> _runFixedAcoustic(int dataSize) async {
    final pair = createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(discoverable: false),
      opticalProfileB: const ChannelSimulationProfile(discoverable: false),
    );
    final orchestrator = SimulationOrchestrator(pair);
    final result = await orchestrator.runTransfer(generateTestData(dataSize));
    return StrategyResult(
      strategy: TransferStrategy.fixedAcoustic,
      success: result.success,
      durationMs: result.durationMs,
      throughput: _calcThroughput(result),
      packetLoss: result.senderSnapshot.metrics?.packetLoss ?? 0,
      retransmissions: result.senderSnapshot.progress?.retryCount ?? 0,
      switchCount: 0,
      goodput: result.success ? dataSize / (result.durationMs / 1000) : 0,
    );
  }

  double _calcThroughput(SimulationResult result) {
    final m = result.senderSnapshot.metrics;
    return m?.throughput ?? 0;
  }
}

String strategyLabel(TransferStrategy s) {
  switch (s) {
    case TransferStrategy.fixedOptical:
      return 'Fixed Optical';
    case TransferStrategy.fixedAcoustic:
      return 'Fixed Acoustic';
    case TransferStrategy.staticSwitch:
      return 'Static Switch';
    case TransferStrategy.adaptive:
      return 'Adaptive';
  }
}
