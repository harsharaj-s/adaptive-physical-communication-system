import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/engine/adaptive_decision_engine.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/manager/channel_manager.dart';
import 'package:adaptive_physical_communication/core/manager/transfer_state_machine.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/simulation/simulated_medium.dart';
import 'package:adaptive_physical_communication/core/transport/reliable_transport.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

class VirtualEndpoint {
  VirtualEndpoint({
    required this.id,
    required this.role,
    required this.logger,
    required this.channelManager,
  })  : stateMachine = TransferStateMachine(),
        decisionEngine = AdaptiveDecisionEngine();

  final String id;
  final EndpointRole role;
  final StructuredLogger logger;
  final ChannelManager channelManager;
  final TransferStateMachine stateMachine;
  final AdaptiveDecisionEngine decisionEngine;

  int sessionId = 0;
  int transferId = 0;
  ReliableTransport? transport;
  ChannelDecision? currentDecision;
  final Map<CommChannelId, double> channelScores = {};
  final List<SwitchEvent> switchEvents = [];
  Uint8List? receivedData;
  List<Uint8List> allPackets = [];
  Uint8List? dataToSend;

  DashboardSnapshot getSnapshot() {
    final activeId = channelManager.activeChannelId;
    final metrics =
        activeId != null ? channelManager.getMetricsForAll()[activeId] : null;

    return DashboardSnapshot(
      state: stateMachine.state,
      role: role,
      currentChannel: activeId,
      channelScore: currentDecision?.score ?? 0,
      channelConfidence: currentDecision?.confidence ?? 0,
      metrics: metrics,
      progress: transport?.getProgress(
        allPackets.length,
        dataToSend?.length ?? 0,
      ),
      channelScores: {
        for (final e in channelScores.entries) channelIdToName(e.key): e.value,
      },
      switchEvents: List.from(switchEvents),
      logs: logger.entries,
      availableChannels: channelManager.availableChannelIds,
    );
  }
}

class SimulationPair {
  SimulationPair({required this.endpointA, required this.endpointB});

  final VirtualEndpoint endpointA;
  final VirtualEndpoint endpointB;
}

SimulationPair createSimulationPair({
  ChannelSimulationProfile? opticalProfileA,
  ChannelSimulationProfile? opticalProfileB,
  ChannelSimulationProfile? acousticProfileA,
  ChannelSimulationProfile? acousticProfileB,
  ChannelSimulationProfile? vibrationProfileA,
  ChannelSimulationProfile? vibrationProfileB,
  DegradationSchedule? opticalDegradation,
  DegradationSchedule? acousticDegradation,
  DegradationSchedule? vibrationDegradation,
  DegradationSchedule? opticalRecovery,
  DegradationSchedule? acousticRecovery,
  DegradationSchedule? vibrationRecovery,
}) {
  final opticalConfigA = SimulatedChannelConfig(
    profile: defaultOpticalProfile.copyWith(
      baseThroughput: opticalProfileA?.baseThroughput,
      packetLossRate: opticalProfileA?.packetLossRate,
      baseLatencyMs: opticalProfileA?.baseLatencyMs,
      confidence: opticalProfileA?.confidence,
      stability: opticalProfileA?.stability,
      corruptionRate: opticalProfileA?.corruptionRate,
      discoverable: opticalProfileA?.discoverable,
    ),
    degradation: opticalDegradation,
    recovery: opticalRecovery,
  );

  final opticalConfigB = SimulatedChannelConfig(
    profile: defaultOpticalProfile.copyWith(
      baseThroughput: opticalProfileB?.baseThroughput,
      packetLossRate: opticalProfileB?.packetLossRate,
      baseLatencyMs: opticalProfileB?.baseLatencyMs,
      confidence: opticalProfileB?.confidence,
      stability: opticalProfileB?.stability,
      corruptionRate: opticalProfileB?.corruptionRate,
      discoverable: opticalProfileB?.discoverable,
    ),
  );

  final acousticConfigA = SimulatedChannelConfig(
    profile: defaultAcousticProfile.copyWith(
      baseThroughput: acousticProfileA?.baseThroughput,
      packetLossRate: acousticProfileA?.packetLossRate,
      baseLatencyMs: acousticProfileA?.baseLatencyMs,
      confidence: acousticProfileA?.confidence,
      stability: acousticProfileA?.stability,
      corruptionRate: acousticProfileA?.corruptionRate,
      discoverable: acousticProfileA?.discoverable,
    ),
    degradation: acousticDegradation,
    recovery: acousticRecovery,
  );

  final acousticConfigB = SimulatedChannelConfig(
    profile: defaultAcousticProfile.copyWith(
      baseThroughput: acousticProfileB?.baseThroughput,
      packetLossRate: acousticProfileB?.packetLossRate,
      baseLatencyMs: acousticProfileB?.baseLatencyMs,
      confidence: acousticProfileB?.confidence,
      stability: acousticProfileB?.stability,
      corruptionRate: acousticProfileB?.corruptionRate,
      discoverable: acousticProfileB?.discoverable,
    ),
  );

  final vibrationConfigA = SimulatedChannelConfig(
    profile: defaultVibrationProfile.copyWith(
      baseThroughput: vibrationProfileA?.baseThroughput,
      packetLossRate: vibrationProfileA?.packetLossRate,
      baseLatencyMs: vibrationProfileA?.baseLatencyMs,
      confidence: vibrationProfileA?.confidence,
      stability: vibrationProfileA?.stability,
      corruptionRate: vibrationProfileA?.corruptionRate,
      discoverable: vibrationProfileA?.discoverable,
    ),
    degradation: vibrationDegradation,
    recovery: vibrationRecovery,
  );

  final vibrationConfigB = SimulatedChannelConfig(
    profile: defaultVibrationProfile.copyWith(
      baseThroughput: vibrationProfileB?.baseThroughput,
      packetLossRate: vibrationProfileB?.packetLossRate,
      baseLatencyMs: vibrationProfileB?.baseLatencyMs,
      confidence: vibrationProfileB?.confidence,
      stability: vibrationProfileB?.stability,
      corruptionRate: vibrationProfileB?.corruptionRate,
      discoverable: vibrationProfileB?.discoverable,
    ),
  );

  final loggerA = StructuredLogger();
  final loggerB = StructuredLogger();
  final cmA = ChannelManager(loggerA);
  final cmB = ChannelManager(loggerB);

  final opticalMediumA = SimulatedMedium('A-optical', opticalConfigA);
  final opticalMediumB = SimulatedMedium('B-optical', opticalConfigB);
  final acousticMediumA = SimulatedMedium('A-acoustic', acousticConfigA);
  final acousticMediumB = SimulatedMedium('B-acoustic', acousticConfigB);
  final vibrationMediumA = SimulatedMedium('A-vibration', vibrationConfigA);
  final vibrationMediumB = SimulatedMedium('B-vibration', vibrationConfigB);

  cmA.registerChannel(createOpticalChannel(opticalMediumA, opticalConfigA));
  cmA.registerChannel(createAcousticChannel(acousticMediumA, acousticConfigA));
  cmA.registerChannel(createVibrationChannel(vibrationMediumA, vibrationConfigA));
  cmB.registerChannel(createOpticalChannel(opticalMediumB, opticalConfigB));
  cmB.registerChannel(createAcousticChannel(acousticMediumB, acousticConfigB));
  cmB.registerChannel(createVibrationChannel(vibrationMediumB, vibrationConfigB));

  VirtualLink(opticalMediumA, opticalMediumB);
  VirtualLink(acousticMediumA, acousticMediumB);
  VirtualLink(vibrationMediumA, vibrationMediumB);

  return SimulationPair(
    endpointA: VirtualEndpoint(
      id: 'A',
      role: EndpointRole.sender,
      logger: loggerA,
      channelManager: cmA,
    ),
    endpointB: VirtualEndpoint(
      id: 'B',
      role: EndpointRole.receiver,
      logger: loggerB,
      channelManager: cmB,
    ),
  );
}

class SimulationResult {
  const SimulationResult({
    required this.success,
    required this.dataMatch,
    required this.originalSize,
    required this.receivedSize,
    required this.switchEvents,
    required this.senderSnapshot,
    required this.receiverSnapshot,
    required this.durationMs,
    required this.logs,
  });

  final bool success;
  final bool dataMatch;
  final int originalSize;
  final int receivedSize;
  final int switchEvents;
  final DashboardSnapshot senderSnapshot;
  final DashboardSnapshot receiverSnapshot;
  final int durationMs;
  final List<String> logs;
}

class SimulationOrchestrator {
  SimulationOrchestrator(this.pair);

  final SimulationPair pair;
  void Function(DashboardSnapshot sender, DashboardSnapshot receiver)? onUpdate;

  Future<SimulationResult> runTransfer(Uint8List data) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final sender = pair.endpointA;
    final receiver = pair.endpointB;

    await sender.channelManager.initializeAll();
    await receiver.channelManager.initializeAll();
    await sender.channelManager.startAll();
    await receiver.channelManager.startAll();

    sender.sessionId = createSessionId();
    sender.transferId = createTransferId();
    receiver.sessionId = sender.sessionId;
    receiver.transferId = sender.transferId;

    sender.stateMachine.reset();
    receiver.stateMachine.reset();
    sender.dataToSend = data;

    // Discovery
    sender.stateMachine.transition(TransferState.discovering);
    receiver.stateMachine.transition(TransferState.discovering);
    _emit(sender, receiver);

    final discoveredSender = await sender.channelManager.discoverAll(300);
    final discoveredReceiver = await receiver.channelManager.discoverAll(300);
    if (discoveredSender.isEmpty || discoveredReceiver.isEmpty) {
      return _failResult(data, startTime, 'Discovery failed');
    }

    // Testing
    sender.stateMachine.transition(TransferState.testingChannels);
    receiver.stateMachine.transition(TransferState.testingChannels);
    _emit(sender, receiver);

    final testResults = await sender.channelManager.testAll(20);
    for (final result in testResults) {
      final score = sender.decisionEngine.scorer.scoreTestResult(result);
      sender.channelScores[result.channel] = score;
      receiver.channelScores[result.channel] = score;
    }

    // Decision
    sender.stateMachine.transition(TransferState.negotiating);
    receiver.stateMachine.transition(TransferState.negotiating);
    final decision = sender.decisionEngine.selectBestChannel(testResults);
    sender.currentDecision = decision;
    receiver.currentDecision = decision;
    sender.channelManager.setActiveChannel(decision.selectedChannel);
    receiver.channelManager.setActiveChannel(decision.selectedChannel);
    sender.logger.decision(
      'Selected ${channelIdToName(decision.selectedChannel)}',
      {'score': decision.score, 'reason': decision.reason},
    );

    // Transport setup
    sender.transport = ReliableTransport(
      sessionId: sender.sessionId,
      transferId: sender.transferId,
      channelId: decision.selectedChannel,
      channelManager: sender.channelManager,
      logger: sender.logger,
    );
    receiver.transport = ReliableTransport(
      sessionId: receiver.sessionId,
      transferId: receiver.transferId,
      channelId: decision.selectedChannel,
      channelManager: receiver.channelManager,
      logger: receiver.logger,
    );

    sender.allPackets = sender.transport!.createDataPackets(data);
    receiver.transport!.setExpectedTotalPackets(sender.allPackets.length);

    sender.stateMachine.transition(TransferState.transferring);
    receiver.stateMachine.transition(TransferState.transferring);
    _emit(sender, receiver);

    // Transfer loop
    const maxIterations = 1500;
    var lastMonitor = 0;

    for (var i = 0; i < maxIterations; i++) {
      final senderTransport = sender.transport!;
      final receiverTransport = receiver.transport!;

      if (senderTransport.lastAckedSequence < sender.allPackets.length) {
        await senderTransport.sendNextWindow(sender.allPackets);
      }

      await Future<void>.delayed(const Duration(milliseconds: 5));

      final senderInc = await sender.channelManager.receiveActive();
      final receiverInc = await receiver.channelManager.receiveActive();
      for (final p in await senderTransport.handleReceivedPackets(senderInc)) {
        await sender.channelManager.transmit(p);
      }
      for (final p in await receiverTransport.handleReceivedPackets(receiverInc)) {
        await receiver.channelManager.transmit(p);
      }

      await _handleSwitchNegotiation(sender, receiver);

      for (final p in senderTransport.checkTimeouts()) {
        await sender.channelManager.transmit(p);
      }

      final senderInc2 = await sender.channelManager.receiveActive();
      final receiverInc2 = await receiver.channelManager.receiveActive();
      for (final p in await senderTransport.handleReceivedPackets(senderInc2)) {
        await sender.channelManager.transmit(p);
      }
      for (final p in await receiverTransport.handleReceivedPackets(receiverInc2)) {
        await receiver.channelManager.transmit(p);
      }

      if (receiverTransport.isTransferComplete()) {
        receiver.receivedData = receiverTransport.reassembleData();
        break;
      }

      if (senderTransport.lastAckedSequence >= sender.allPackets.length &&
          receiverTransport.isTransferComplete()) {
        receiver.receivedData = receiverTransport.reassembleData();
        break;
      }

      if (i - lastMonitor >= 20) {
        lastMonitor = i;
        await _evaluateAndSwitch(sender, receiver);
      }

      if (i % 5 == 0) _emit(sender, receiver);
    }

    final received = receiver.receivedData;
    final dataMatch = received != null &&
        received.length >= data.length &&
        _buffersEqual(data, received.sublist(0, data.length));

    if (dataMatch) {
      sender.stateMachine.transition(TransferState.completed);
      receiver.stateMachine.transition(TransferState.completed);
      sender.logger.transfer('Transfer complete');
    } else {
      sender.stateMachine.forceState(TransferState.failed);
      receiver.stateMachine.forceState(TransferState.failed);
      sender.logger.error('Transfer failed');
    }

    await sender.channelManager.stopAll();
    await receiver.channelManager.stopAll();
    _emit(sender, receiver);

    final logs = [
      ...sender.logger.entries,
      ...receiver.logger.entries,
    ].map((e) => '[${e.category}] ${e.message}').toList();

    return SimulationResult(
      success: dataMatch,
      dataMatch: dataMatch,
      originalSize: data.length,
      receivedSize: received?.length ?? 0,
      switchEvents: sender.switchEvents.length,
      senderSnapshot: sender.getSnapshot(),
      receiverSnapshot: receiver.getSnapshot(),
      durationMs: DateTime.now().millisecondsSinceEpoch - startTime,
      logs: logs,
    );
  }

  void _emit(VirtualEndpoint sender, VirtualEndpoint receiver) {
    onUpdate?.call(sender.getSnapshot(), receiver.getSnapshot());
  }

  Future<void> _handleSwitchNegotiation(
    VirtualEndpoint sender,
    VirtualEndpoint receiver,
  ) async {
    final senderInc = await sender.channelManager.receiveActive();
    final receiverInc = await receiver.channelManager.receiveActive();

    for (final packet in senderInc) {
      if (packet.packetType == PacketType.channelSwitchRequest) {
        final req = sender.transport!.parseSwitchRequest(packet);
        if (req != null) {
          sender.channelManager.setActiveChannel(req.newChannelId);
          sender.transport!.setChannelId(req.newChannelId);
          await sender.channelManager.transmit(
            sender.transport!.createSwitchAck(req.newChannelId, req.lastConfirmed),
          );
        }
      }
    }

    for (final packet in receiverInc) {
      if (packet.packetType == PacketType.channelSwitchRequest) {
        final req = receiver.transport!.parseSwitchRequest(packet);
        if (req != null) {
          receiver.channelManager.setActiveChannel(req.newChannelId);
          receiver.transport!.setChannelId(req.newChannelId);
          await receiver.channelManager.transmit(
            receiver.transport!.createSwitchAck(req.newChannelId, req.lastConfirmed),
          );
          receiver.logger.switchChannel(
            'Switch acknowledged, resuming from packet ${req.lastConfirmed + 1}',
          );
        }
      } else if (packet.packetType == PacketType.channelSwitchAck) {
        final ack = receiver.transport!.parseSwitchAck(packet);
        if (ack != null) {
          receiver.channelManager.setActiveChannel(ack.newChannelId);
          receiver.transport!.setChannelId(ack.newChannelId);
          receiver.transport!.resumeFromSequence(ack.lastConfirmed);
        }
      }
    }
  }

  Future<void> _evaluateAndSwitch(
    VirtualEndpoint sender,
    VirtualEndpoint receiver,
  ) async {
    final activeId = sender.channelManager.activeChannelId;
    if (activeId == null) return;

    final activeChannel = sender.channelManager.activeChannel;
    if (activeChannel == null) return;

    final currentMetrics = activeChannel.getMetrics();
    final currentScore = sender.decisionEngine.scorer.scoreMetrics(currentMetrics);
    sender.channelScores[activeId] = currentScore;

    if (!sender.decisionEngine.isDegraded(currentScore)) return;

    sender.logger.warning(
      '${channelIdToName(activeId)} quality degraded (score=${currentScore.toStringAsFixed(2)})',
    );

    if (sender.stateMachine.state == TransferState.transferring) {
      sender.stateMachine.transition(TransferState.degraded);
    }

    for (final altId in sender.channelManager.availableChannelIds) {
      if (altId == activeId) continue;
      sender.logger.adapt('Testing ${channelIdToName(altId)} channel');
      final altResult = await sender.channelManager.testChannel(altId, 20);
      final evaluation = sender.decisionEngine.evaluateSwitch(
        activeId,
        currentMetrics,
        altResult,
      );
      sender.channelScores[altId] = evaluation.alternativeScore;

      if (evaluation.shouldSwitch) {
        await _performSwitch(sender, receiver, activeId, altId, evaluation.reason);
        return;
      }
    }

    if (sender.stateMachine.state == TransferState.degraded) {
      sender.stateMachine.transition(TransferState.transferring);
    }
  }

  Future<void> _performSwitch(
    VirtualEndpoint sender,
    VirtualEndpoint receiver,
    CommChannelId fromChannel,
    CommChannelId toChannel,
    String reason,
  ) async {
    sender.stateMachine.transition(TransferState.switchingChannel);
    final lastConfirmed = sender.transport!.lastAckedSequence;

    sender.logger.decision(
      'Switching ${channelIdToName(fromChannel)} → ${channelIdToName(toChannel)}',
    );
    sender.logger.switchChannel('Last confirmed packet = $lastConfirmed');

    sender.channelManager.setActiveChannel(toChannel);
    receiver.channelManager.setActiveChannel(toChannel);
    sender.transport!.setChannelId(toChannel);
    receiver.transport!.setChannelId(toChannel);
    sender.transport!.resumeFromSequence(lastConfirmed);
    receiver.transport!.resumeFromSequence(lastConfirmed);

    await sender.channelManager.transmit(
      sender.transport!.createSwitchRequest(toChannel, lastConfirmed),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await _handleSwitchNegotiation(sender, receiver);

    sender.switchEvents.add(SwitchEvent(
      fromChannel: fromChannel,
      toChannel: toChannel,
      lastConfirmedPacket: lastConfirmed,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      reason: reason,
    ));

    sender.logger.transfer('Resuming packet ${lastConfirmed + 1}');
    sender.stateMachine.transition(TransferState.recovering);
    sender.stateMachine.transition(TransferState.transferring);
  }

  SimulationResult _failResult(Uint8List data, int startTime, String reason) {
    return SimulationResult(
      success: false,
      dataMatch: false,
      originalSize: data.length,
      receivedSize: 0,
      switchEvents: 0,
      senderSnapshot: pair.endpointA.getSnapshot(),
      receiverSnapshot: pair.endpointB.getSnapshot(),
      durationMs: DateTime.now().millisecondsSinceEpoch - startTime,
      logs: [reason],
    );
  }
}

bool _buffersEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List generateTestData(int size) {
  return Uint8List.fromList(List.generate(size, (i) => i % 256));
}
