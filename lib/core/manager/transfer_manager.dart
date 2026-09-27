import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/channels/hardware_channels.dart';
import 'package:adaptive_physical_communication/core/engine/adaptive_decision_engine.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/manager/channel_manager.dart';
import 'package:adaptive_physical_communication/core/manager/transfer_state_machine.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/physical/hardware_phy_config.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/simulation/simulation_orchestrator.dart';
import 'package:adaptive_physical_communication/core/transport/reliable_transport.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

enum OperationMode { simulation, hardware, hybrid }

class TransferManagerConfig {
  const TransferManagerConfig({
    this.testPacketCount = 20,
    this.discoveryTimeoutMs = 500,
    this.peerDiscoveryTimeoutMs = 20000,
    this.peerInactivityTimeoutMs = 45000,
    this.monitorIntervalMs = 100,
    this.enableAdaptiveSwitching = true,
    this.mode = OperationMode.simulation,
    this.transferMode = TransferMode.broadcast,
    this.forcedChannel,
    this.isCancelled,
  });

  final int testPacketCount;
  final int discoveryTimeoutMs;
  final int peerDiscoveryTimeoutMs;
  final int peerInactivityTimeoutMs;
  final int monitorIntervalMs;
  final bool enableAdaptiveSwitching;
  final OperationMode mode;
  final TransferMode transferMode;

  /// When set, skip channel discovery/selection and use this channel only.
  final CommChannelId? forcedChannel;

  /// Optional callback checked during transfer loops for user cancel.
  final bool Function()? isCancelled;
}

/// Creates channel manager for the given operation mode.
Future<ChannelManager> createChannelManagerForMode(
  OperationMode mode,
  StructuredLogger logger, {
  SimulationPair? simulationPair,
  HardwareOpticalChannel? optical,
  HardwareAcousticChannel? acoustic,
  HardwareVibrationChannel? vibration,
  EndpointRole? hardwareRole,
}) async {
  final cm = ChannelManager(logger);

  switch (mode) {
    case OperationMode.simulation:
      if (simulationPair != null) {
        for (final ch in simulationPair.endpointA.channelManager.allChannels) {
          cm.registerChannel(ch);
        }
      } else {
        final pair = createSimulationPair();
        for (final ch in pair.endpointA.channelManager.allChannels) {
          cm.registerChannel(ch);
        }
      }
    case OperationMode.hardware:
      if (optical != null && acoustic != null) {
        cm.registerChannel(optical);
        cm.registerChannel(acoustic);
        if (vibration != null) cm.registerChannel(vibration);
      } else {
        cm.registerChannel(HardwareOpticalChannel(logger: logger));
        cm.registerChannel(HardwareAcousticChannel(logger: logger));
        if (isVibrationSupported) {
          cm.registerChannel(vibration ?? HardwareVibrationChannel(logger: logger));
        }
      }
    case OperationMode.hybrid:
      final pair = createSimulationPair();
      for (final ch in pair.endpointA.channelManager.allChannels) {
        cm.registerChannel(ch);
      }
      cm.registerChannel(optical ?? HardwareOpticalChannel(logger: logger));
      cm.registerChannel(acoustic ?? HardwareAcousticChannel(logger: logger));
      cm.registerChannel(vibration ?? HardwareVibrationChannel(logger: logger));
  }

  await cm.initializeAll(
    setupOpticalCamera: hardwareRole == EndpointRole.receiver,
  );
  return cm;
}

/// Full transfer lifecycle manager — works with simulation or hardware channels.
class TransferManager {
  TransferManager({
    required this.role,
    required this.logger,
    required this.channelManager,
    this.config = const TransferManagerConfig(),
  })  : stateMachine = TransferStateMachine(),
        decisionEngine = AdaptiveDecisionEngine();

  final EndpointRole role;
  final StructuredLogger logger;
  final ChannelManager channelManager;
  final TransferManagerConfig config;
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

  void Function(DashboardSnapshot)? onSnapshot;

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
      progress: transport?.getProgress(allPackets.length, dataToSend?.length ?? 0),
      channelScores: {
        for (final e in channelScores.entries) channelIdToName(e.key): e.value,
      },
      switchEvents: List.from(switchEvents),
      logs: logger.entries,
      availableChannels: channelManager.availableChannelIds,
    );
  }

  void _emit() => onSnapshot?.call(getSnapshot());

  Future<Uint8List?> runTransfer(Uint8List data) async {
    dataToSend = data;
    receivedData = null;
    switchEvents.clear();
    stateMachine.reset();

    sessionId = createSessionId();
    transferId = createTransferId();

    await channelManager.startAll(
      enableOpticalReceiver: role == EndpointRole.receiver,
      enableVibrationReceiver: role == EndpointRole.receiver,
      enableAcousticReceiver: true,
    );

    stateMachine.transition(TransferState.discovering);
    _emit();

    final bool isBroadcast =
        config.transferMode == TransferMode.broadcast &&
        config.mode == OperationMode.hardware;

    final List<CommChannelId> discovered;
    final forced = config.forcedChannel;
    if (forced != null) {
      if (!channelManager.availableChannelIds.contains(forced)) {
        stateMachine.transition(TransferState.failed);
        logger.error('${channelIdToName(forced)} channel not available');
        _emit();
        return null;
      }
      discovered = [forced];
      logger.discovery('Using ${channelIdToName(forced)} channel (user selected)');
    } else if (isBroadcast) {
      discovered = channelManager.availableChannelIds
          .where((id) => id != CommChannelId.vibration)
          .toList();
      if (discovered.isEmpty) {
        stateMachine.transition(TransferState.failed);
        logger.error('No broadcast-capable channels available');
        _emit();
        return null;
      }
      logger.discovery(
        'Broadcast mode — transmitting to all listeners (${discovered.map(channelIdToName).join(', ')})',
      );
    } else if (config.mode == OperationMode.hardware) {
      final peerFound = await _discoverPeer(config.peerDiscoveryTimeoutMs);
      if (!peerFound) {
        stateMachine.transition(TransferState.failed);
        logger.error(
          'No paired device found — set the other device to Receive and tap Start',
        );
        _emit();
        return null;
      }
      discovered = channelManager.availableChannelIds;
    } else {
      discovered = await channelManager.discoverAll(config.discoveryTimeoutMs);
      if (discovered.isEmpty) {
        stateMachine.transition(TransferState.failed);
        logger.error('Discovery failed — no channels available');
        _emit();
        return null;
      }
    }

    if (forced != null) {
      stateMachine.transition(TransferState.testingChannels);
      _emit();
      stateMachine.transition(TransferState.negotiating);
      _emit();
      currentDecision = ChannelDecision(
        selectedChannel: forced,
        score: 1.0,
        confidence: 1.0,
        reason: 'User-selected ${channelIdToName(forced)} mode',
      );
    } else if (isBroadcast) {
      stateMachine.transition(TransferState.testingChannels);
      _emit();
      stateMachine.transition(TransferState.negotiating);
      _emit();
      currentDecision = _selectBroadcastChannel(discovered);
    } else {
      stateMachine.transition(TransferState.testingChannels);
      _emit();
      final testResults = await channelManager.testAll(config.testPacketCount);
      for (final r in testResults) {
        channelScores[r.channel] = decisionEngine.scorer.scoreTestResult(r);
      }

      stateMachine.transition(TransferState.negotiating);
      _emit();
      if (config.mode == OperationMode.hardware &&
          channelManager.availableChannelIds.contains(CommChannelId.acoustic)) {
        currentDecision = const ChannelDecision(
          selectedChannel: CommChannelId.acoustic,
          score: 0.9,
          confidence: 0.85,
          reason: 'Acoustic is bidirectional — best for phone-to-phone',
        );
      } else {
        currentDecision = decisionEngine.selectBestChannel(testResults);
      }
    }
    channelManager.setActiveChannel(currentDecision!.selectedChannel);
    logger.decision(
      'Selected ${channelIdToName(currentDecision!.selectedChannel)}',
      {'score': currentDecision!.score, 'reason': currentDecision!.reason},
    );

    transport = ReliableTransport(
      sessionId: sessionId,
      transferId: transferId,
      channelId: currentDecision!.selectedChannel,
      channelManager: channelManager,
      logger: logger,
      config: config.mode == OperationMode.hardware
          ? hardwareTransportConfig
          : defaultTransportConfig,
      transmissionConfig: config.mode == OperationMode.hardware
          ? hardwareTransmissionConfigFor(currentDecision!.selectedChannel)
          : defaultTransmissionConfig,
      broadcastMode: isBroadcast && role == EndpointRole.sender,
    );

    if (role == EndpointRole.sender) {
      allPackets = transport!.createDataPackets(data);
    } else {
      transport!.setExpectedTotalPackets(0);
    }

    stateMachine.transition(TransferState.transferring);
    _emit();

    await _transferLoop();
    return receivedData;
  }

  ChannelDecision _selectBroadcastChannel(List<CommChannelId> available) {
    if (available.contains(CommChannelId.optical)) {
      return const ChannelDecision(
        selectedChannel: CommChannelId.optical,
        score: 0.95,
        confidence: 0.9,
        reason: 'Optical QR — one screen, many cameras',
      );
    }
    if (available.contains(CommChannelId.acoustic)) {
      return const ChannelDecision(
        selectedChannel: CommChannelId.acoustic,
        score: 0.85,
        confidence: 0.8,
        reason: 'Acoustic speaker — audible to nearby receivers',
      );
    }
    return ChannelDecision(
      selectedChannel: available.first,
      score: 0.5,
      confidence: 0.5,
      reason: 'Fallback broadcast channel',
    );
  }

  Future<bool> _discoverPeer(int timeoutMs) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      if (role == EndpointRole.sender) {
        final beaconOrder = [
          CommChannelId.acoustic,
          CommChannelId.optical,
          if (isVibrationSupported) CommChannelId.vibration,
        ].where(channelManager.availableChannelIds.contains).toList();

        for (final channelId in beaconOrder) {
          channelManager.setActiveChannel(channelId);
          try {
            await channelManager.transmit(_createDiscoveryPacket(channelId));
          } catch (_) {}

          final incoming = await channelManager.receive();
          for (final packet in incoming) {
            if (packet.packetType == PacketType.discoveryResponse &&
                packet.sessionId == sessionId) {
              channelManager.setActiveChannel(packet.channelId);
              logger.discovery(
                'Paired device found on ${channelIdToName(packet.channelId)}',
              );
              return true;
            }
          }
        }
      } else {
        final incoming = await channelManager.receive();
        for (final packet in incoming) {
          if (packet.packetType == PacketType.discovery &&
              packet.sessionId == sessionId) {
            channelManager.setActiveChannel(packet.channelId);
            await channelManager.transmit(_createDiscoveryResponse(packet));
            return true;
          }
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    return false;
  }

  Uint8List _createDiscoveryResponse(DecodedPacket request) =>
      packetCodec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: request.sessionId,
          transferId: request.transferId,
          packetType: PacketType.discoveryResponse,
          channelId: request.channelId,
          sequenceNumber: 0,
          payloadLength: hardwareDiscoveryPayload.length,
        ),
        hardwareDiscoveryPayload,
      );

  Uint8List _createDiscoveryPacket(CommChannelId channelId) =>
      packetCodec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: sessionId,
          transferId: transferId,
          packetType: PacketType.discovery,
          channelId: channelId,
          sequenceNumber: 0,
          payloadLength: hardwareDiscoveryPayload.length,
        ),
        hardwareDiscoveryPayload,
      );

  Future<List<DecodedPacket>> _receiveIncoming() =>
      config.mode == OperationMode.hardware
          ? channelManager.receive()
          : channelManager.receiveActive();

  Future<void> _transferLoop() async {
    final t = transport!;
    final isBroadcastSender = config.transferMode == TransferMode.broadcast &&
        config.mode == OperationMode.hardware &&
        role == EndpointRole.sender;
    final maxIter = config.mode == OperationMode.hardware ? 2000 : 1500;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    var lastProgressAt = startedAt;

    for (var i = 0; i < maxIter; i++) {
      if (config.isCancelled?.call() ?? false) {
        logger.info('Transfer cancelled by user');
        break;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      if (role == EndpointRole.sender &&
          (isBroadcastSender
              ? !t.allPacketsTransmitted
              : t.lastAckedSequence < allPackets.length)) {
        await t.sendNextWindow(allPackets);
      }

      await Future<void>.delayed(
        Duration(milliseconds: config.mode == OperationMode.hardware ? 50 : 5),
      );

      final incoming = await _receiveIncoming();
      if (!isBroadcastSender) {
        final outgoing = await t.handleReceivedPackets(incoming);
        for (final p in outgoing) {
          await channelManager.transmit(p);
        }
      }

      if (role == EndpointRole.sender && !isBroadcastSender) {
        for (final p in t.checkTimeouts()) {
          await channelManager.transmit(p);
        }
      }

      if (!isBroadcastSender) {
        final incoming2 = await _receiveIncoming();
        final outgoing2 = await t.handleReceivedPackets(incoming2);
        for (final p in outgoing2) {
          await channelManager.transmit(p);
        }
      }

      if (role == EndpointRole.receiver && t.isTransferComplete()) {
        receivedData = t.reassembleData();
        lastProgressAt = now;
        break;
      }

      if (isBroadcastSender && t.allPacketsTransmitted) {
        lastProgressAt = now;
        break;
      }

      if (role == EndpointRole.sender &&
          !isBroadcastSender &&
          t.lastAckedSequence >= allPackets.length) {
        lastProgressAt = now;
        break;
      }

      if (role == EndpointRole.sender && t.lastAckedSequence > 0) {
        lastProgressAt = now;
      }

      if (config.mode == OperationMode.hardware && !isBroadcastSender) {
        if (role == EndpointRole.sender &&
            t.hasPendingRetriesExhausted &&
            t.lastAckedSequence == 0) {
          logger.error('No acknowledgement from paired device — stopping');
          break;
        }
        if (now - lastProgressAt > config.peerInactivityTimeoutMs) {
          logger.error('Timed out waiting for paired device — stopping');
          break;
        }
      }

      if (config.enableAdaptiveSwitching && i % 20 == 0) {
        await _evaluateSwitch();
      }

      if (i % 5 == 0) _emit();
    }

    final success = receivedData != null ||
        (role == EndpointRole.sender &&
            (isBroadcastSender
                ? t.allPacketsTransmitted
                : t.lastAckedSequence >= allPackets.length));

    if (success) {
      stateMachine.transition(TransferState.completed);
      logger.transfer('Transfer complete');
    } else {
      stateMachine.forceState(TransferState.failed);
      logger.error('Transfer failed');
    }
    _emit();
  }

  Future<void> _evaluateSwitch() async {
    final activeId = channelManager.activeChannelId;
    if (activeId == null || transport == null) return;

    final channel = channelManager.activeChannel;
    if (channel == null) return;

    final metrics = channel.getMetrics();
    final score = decisionEngine.scorer.scoreMetrics(metrics);
    channelScores[activeId] = score;

    if (!decisionEngine.isDegraded(score)) return;

    logger.warning('${channelIdToName(activeId)} quality degraded');
    if (stateMachine.state == TransferState.transferring) {
      stateMachine.transition(TransferState.degraded);
    }

    for (final altId in channelManager.availableChannelIds) {
      if (altId == activeId) continue;
      logger.adapt('Testing ${channelIdToName(altId)}');
      final altResult = await channelManager.testChannel(altId, config.testPacketCount);
      final eval = decisionEngine.evaluateSwitch(activeId, metrics, altResult);
      channelScores[altId] = eval.alternativeScore;

      if (eval.shouldSwitch) {
        await _performSwitch(activeId, altId, eval.reason);
        return;
      }
    }

    if (stateMachine.state == TransferState.degraded) {
      stateMachine.transition(TransferState.transferring);
    }
  }

  Future<void> _performSwitch(
    CommChannelId from,
    CommChannelId to,
    String reason,
  ) async {
    stateMachine.transition(TransferState.switchingChannel);
    final lastConfirmed = transport!.lastAckedSequence;
    logger.decision('Switching ${channelIdToName(from)} → ${channelIdToName(to)}');
    logger.switchChannel('Last confirmed packet = $lastConfirmed');

    channelManager.setActiveChannel(to);
    transport!.setChannelId(to);
    transport!.resumeFromSequence(lastConfirmed);

    await channelManager.transmit(
      transport!.createSwitchRequest(to, lastConfirmed),
    );

    switchEvents.add(SwitchEvent(
      fromChannel: from,
      toChannel: to,
      lastConfirmedPacket: lastConfirmed,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      reason: reason,
    ));

    logger.transfer('Resuming packet ${lastConfirmed + 1}');
    stateMachine.transition(TransferState.recovering);
    stateMachine.transition(TransferState.transferring);
  }

  Future<void> shutdown() async {
    await channelManager.stopAll();
  }
}
