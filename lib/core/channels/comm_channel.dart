import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/simulation/simulated_medium.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

abstract class CommChannel {
  CommChannelId get id;
  ChannelCapabilities get capabilities;

  Future<void> initialize({bool setupCamera = true});
  Future<void> start({bool enableReceiver = true});
  Future<void> stop();
  Future<bool> discover(int timeoutMs);
  Future<ChannelTestResult> test(int testPacketCount);
  Future<void> transmit(Uint8List packet);
  Future<List<DecodedPacket>> receive();
  ChannelMetrics getMetrics();
  bool isAvailable();
  void setTransmissionConfig(TransmissionConfig config);
}

class SimulatedCommChannel implements CommChannel {
  SimulatedCommChannel({
    required this.id,
    required this.medium,
    required this.config,
    required this.capabilities,
  });

  @override
  final CommChannelId id;
  final SimulatedMedium medium;
  final SimulatedChannelConfig config;

  @override
  final ChannelCapabilities capabilities;

  bool _running = false;
  final List<DecodedPacket> _receiveBuffer = [];

  SimulatedMedium get simulatedMedium => medium;

  @override
  Future<void> initialize({bool setupCamera = true}) async {}

  @override
  Future<void> start({bool enableReceiver = true}) async => _running = true;

  @override
  Future<void> stop() async => _running = false;

  @override
  Future<bool> discover(int timeoutMs) => medium.runDiscoveryTest(timeoutMs);

  @override
  Future<ChannelTestResult> test(int testPacketCount) async {
    final result = await medium.runChannelTest(testPacketCount);
    return profileToTestResult(id, medium.activeProfile, result.sent, result.received);
  }

  @override
  Future<void> transmit(Uint8List packet) async {
    if (!_running) throw StateError('Channel $id is not running');
    await medium.send(packet);
  }

  @override
  Future<List<DecodedPacket>> receive() async {
    final raw = medium.pollReceived();
    final decoded = medium.decodeRawPackets(raw);
    _receiveBuffer.addAll(decoded);
    final batch = List<DecodedPacket>.from(_receiveBuffer);
    _receiveBuffer.clear();
    return batch;
  }

  @override
  ChannelMetrics getMetrics() => medium.getMetrics();

  @override
  bool isAvailable() => _running;

  @override
  void setTransmissionConfig(TransmissionConfig config) {}
}

SimulatedCommChannel createOpticalChannel(
  SimulatedMedium medium,
  SimulatedChannelConfig config,
) =>
    SimulatedCommChannel(
      id: CommChannelId.optical,
      medium: medium,
      config: config,
      capabilities: ChannelCapabilities(
        channelId: CommChannelId.optical,
        name: 'Optical (Simulated)',
        maxThroughput: config.profile.baseThroughput,
        minLatency: config.profile.baseLatencyMs,
        supportsBinary: true,
        hardwareImplemented: false,
      ),
    );

SimulatedCommChannel createAcousticChannel(
  SimulatedMedium medium,
  SimulatedChannelConfig config,
) =>
    SimulatedCommChannel(
      id: CommChannelId.acoustic,
      medium: medium,
      config: config,
      capabilities: ChannelCapabilities(
        channelId: CommChannelId.acoustic,
        name: 'Acoustic (Simulated)',
        maxThroughput: config.profile.baseThroughput,
        minLatency: config.profile.baseLatencyMs,
        supportsBinary: true,
        hardwareImplemented: false,
      ),
    );

SimulatedCommChannel createVibrationChannel(
  SimulatedMedium medium,
  SimulatedChannelConfig config,
) =>
    SimulatedCommChannel(
      id: CommChannelId.vibration,
      medium: medium,
      config: config,
      capabilities: ChannelCapabilities(
        channelId: CommChannelId.vibration,
        name: 'Vibration (Simulated)',
        maxThroughput: config.profile.baseThroughput,
        minLatency: config.profile.baseLatencyMs,
        supportsBinary: true,
        hardwareImplemented: false,
      ),
    );
