import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

class ChannelSimulationProfile {
  const ChannelSimulationProfile({
    this.baseThroughput = 18000,
    this.packetLossRate = 0.01,
    this.baseLatencyMs = 80,
    this.confidence = 0.92,
    this.stability = 0.88,
    this.corruptionRate = 0.005,
    this.discoverable = true,
  });

  final double baseThroughput;
  final double packetLossRate;
  final double baseLatencyMs;
  final double confidence;
  final double stability;
  final double corruptionRate;
  final bool discoverable;

  ChannelSimulationProfile merge(ChannelSimulationProfile other) =>
      ChannelSimulationProfile(
        baseThroughput: other.baseThroughput,
        packetLossRate: other.packetLossRate,
        baseLatencyMs: other.baseLatencyMs,
        confidence: other.confidence,
        stability: other.stability,
        corruptionRate: other.corruptionRate,
        discoverable: other.discoverable,
      );

  ChannelSimulationProfile copyWith({
    double? baseThroughput,
    double? packetLossRate,
    double? baseLatencyMs,
    double? confidence,
    double? stability,
    double? corruptionRate,
    bool? discoverable,
  }) =>
      ChannelSimulationProfile(
        baseThroughput: baseThroughput ?? this.baseThroughput,
        packetLossRate: packetLossRate ?? this.packetLossRate,
        baseLatencyMs: baseLatencyMs ?? this.baseLatencyMs,
        confidence: confidence ?? this.confidence,
        stability: stability ?? this.stability,
        corruptionRate: corruptionRate ?? this.corruptionRate,
        discoverable: discoverable ?? this.discoverable,
      );
}

class DegradationSchedule {
  const DegradationSchedule({
    required this.afterPacket,
    required this.profile,
  });

  final int afterPacket;
  final ChannelSimulationProfile profile;
}

class SimulatedChannelConfig {
  const SimulatedChannelConfig({
    required this.profile,
    this.degradation,
    this.recovery,
  });

  final ChannelSimulationProfile profile;
  final DegradationSchedule? degradation;
  final DegradationSchedule? recovery;
}

const defaultOpticalProfile = ChannelSimulationProfile(
  baseLatencyMs: 2,
);
const defaultAcousticProfile = ChannelSimulationProfile(
  baseThroughput: 9000,
  packetLossRate: 0.04,
  baseLatencyMs: 3,
  confidence: 0.78,
  stability: 0.72,
  corruptionRate: 0.01,
);
const defaultVibrationProfile = ChannelSimulationProfile(
  baseThroughput: 800,
  packetLossRate: 0.06,
  baseLatencyMs: 120,
  confidence: 0.72,
  stability: 0.68,
  corruptionRate: 0.015,
);

ChannelMetrics profileToMetrics(ChannelSimulationProfile profile) {
  final reliability =
      max(0.0, 1 - profile.packetLossRate - profile.corruptionRate);
  return ChannelMetrics(
    throughput: profile.baseThroughput,
    packetLoss: profile.packetLossRate,
    latency: profile.baseLatencyMs,
    reliability: reliability,
    errorRate: profile.corruptionRate,
    confidence: profile.confidence,
    stability: profile.stability,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

ChannelTestResult profileToTestResult(
  CommChannelId channelId,
  ChannelSimulationProfile profile,
  int packetsSent,
  int packetsReceived,
) {
  final packetLossRate = packetsSent > 0
      ? (packetsSent - packetsReceived) / packetsSent
      : profile.packetLossRate;
  return ChannelTestResult(
    channel: channelId,
    packetsSent: packetsSent,
    packetsReceived: packetsReceived,
    packetLossRate: packetLossRate,
    throughput: profile.baseThroughput * (1 - packetLossRate),
    latency: profile.baseLatencyMs,
    confidence: profile.confidence * (1 - packetLossRate * 0.5),
    stability: profile.stability,
  );
}

typedef PacketDeliveryHandler = void Function(Uint8List raw);

class _QueuedPacket {
  _QueuedPacket({required this.data, required this.deliverAt});
  final Uint8List data;
  final int deliverAt;
}

class SimulatedMedium {
  SimulatedMedium(this.peerId, this.config)
      : _activeProfile = config.profile;

  final String peerId;
  SimulatedChannelConfig config;
  ChannelSimulationProfile _activeProfile;
  PacketDeliveryHandler? _outboundHandler;
  final List<_QueuedPacket> _inboundQueue = [];
  int _packetsProcessed = 0;
  int _testSent = 0;
  int _testReceived = 0;
  final _random = Random();

  void setOutboundHandler(PacketDeliveryHandler handler) =>
      _outboundHandler = handler;

  ChannelSimulationProfile get activeProfile => _activeProfile;

  void _checkDegradation() {
    final d = config.degradation;
    if (d != null && _packetsProcessed >= d.afterPacket) {
      _activeProfile = _activeProfile.merge(d.profile);
    }
  }

  void _checkRecovery() {
    final r = config.recovery;
    if (r != null && _packetsProcessed >= r.afterPacket) {
      _activeProfile = r.profile;
    }
  }

  Future<void> send(Uint8List raw) async {
    final handler = _outboundHandler;
    if (handler == null) {
      throw StateError('SimulatedMedium $peerId: no outbound handler');
    }

    _packetsProcessed++;
    _checkDegradation();
    _checkRecovery();

    final profile = _activeProfile;
    if (_random.nextDouble() < profile.packetLossRate) return;

    var data = Uint8List.fromList(raw);
    if (_random.nextDouble() < profile.corruptionRate && data.length > headerSize) {
      final idx = headerSize +
          _random.nextInt(max(1, data.length - headerSize - crcSize));
      data[idx] = (data[idx] ^ 0xFF) & 0xFF;
    }

    final latency = profile.baseLatencyMs + (_random.nextDouble() * 2 - 1) * 15;
    final throughputDelay = (raw.length * 8) / profile.baseThroughput * 1000;
    final delayMs = max(1, (latency + throughputDelay).round());
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    handler(data);
  }

  void receiveFromPeer(Uint8List raw) {
    _inboundQueue.add(_QueuedPacket(
      data: raw,
      deliverAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  List<Uint8List> pollReceived() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ready = <Uint8List>[];
    final remaining = <_QueuedPacket>[];
    for (final item in _inboundQueue) {
      if (item.deliverAt <= now) {
        ready.add(item.data);
      } else {
        remaining.add(item);
      }
    }
    _inboundQueue
      ..clear()
      ..addAll(remaining);
    return ready;
  }

  Future<bool> runDiscoveryTest(int timeoutMs) async {
    if (!_activeProfile.discoverable) return false;
    await Future<void>.delayed(
      Duration(milliseconds: min(timeoutMs, (50 + _random.nextDouble() * 100).round())),
    );
    return _activeProfile.discoverable &&
        _random.nextDouble() > _activeProfile.packetLossRate * 2;
  }

  Future<({int sent, int received})> runChannelTest(int testPacketCount) async {
    _testSent = testPacketCount;
    var received = 0;
    for (var i = 0; i < testPacketCount; i++) {
      if (_random.nextDouble() >= _activeProfile.packetLossRate) received++;
      await Future<void>.delayed(
        Duration(milliseconds: (_activeProfile.baseLatencyMs / testPacketCount).round()),
      );
    }
    _testReceived = received;
    return (sent: testPacketCount, received: received);
  }

  ChannelMetrics getMetrics() => profileToMetrics(_activeProfile);

  ChannelTestResult getTestResult(CommChannelId channelId) =>
      profileToTestResult(channelId, _activeProfile, _testSent, _testReceived);

  List<DecodedPacket> decodeRawPackets(List<Uint8List> rawPackets) {
    return rawPackets.map(packetCodec.decode).whereType<DecodedPacket>().toList();
  }
}

class VirtualLink {
  VirtualLink(SimulatedMedium mediaA, SimulatedMedium mediaB) {
    mediaA.setOutboundHandler(mediaB.receiveFromPeer);
    mediaB.setOutboundHandler(mediaA.receiveFromPeer);
  }
}
