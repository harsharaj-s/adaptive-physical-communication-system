/// Core types for the adaptive physical communication system.
library;

const int protocolVersion = 1;

enum PacketType {
  discovery(0),
  discoveryResponse(1),
  channelTest(2),
  channelTestResponse(3),
  negotiation(4),
  data(5),
  ack(6),
  nack(7),
  retransmissionRequest(8),
  channelSwitchRequest(9),
  channelSwitchAck(10),
  heartbeat(11),
  transferStatus(12),
  transferComplete(13),
  error(14);

  const PacketType(this.value);
  final int value;

  static PacketType fromValue(int v) =>
      PacketType.values.firstWhere((e) => e.value == v);
}

enum CommChannelId {
  optical(1),
  acoustic(2),
  vibration(3);

  const CommChannelId(this.value);
  final int value;

  static CommChannelId fromValue(int v) =>
      CommChannelId.values.firstWhere((e) => e.value == v);
}

enum TransferState {
  idle,
  discovering,
  testingChannels,
  negotiating,
  transferring,
  degraded,
  switchingChannel,
  recovering,
  completed,
  failed,
}

enum EndpointRole { sender, receiver }

/// Unicast pairs one sender with one receiver; broadcast lets many receivers
/// decode the same transmission (optical QR, acoustic speaker).
enum TransferMode { unicast, broadcast }

class ChannelMetrics {
  const ChannelMetrics({
    required this.throughput,
    required this.packetLoss,
    required this.latency,
    required this.reliability,
    required this.errorRate,
    required this.confidence,
    required this.stability,
    required this.timestamp,
  });

  final double throughput;
  final double packetLoss;
  final double latency;
  final double reliability;
  final double errorRate;
  final double confidence;
  final double stability;
  final int timestamp;

  ChannelMetrics copyWith({int? timestamp}) => ChannelMetrics(
        throughput: throughput,
        packetLoss: packetLoss,
        latency: latency,
        reliability: reliability,
        errorRate: errorRate,
        confidence: confidence,
        stability: stability,
        timestamp: timestamp ?? this.timestamp,
      );
}

class ChannelTestResult {
  const ChannelTestResult({
    required this.channel,
    required this.packetsSent,
    required this.packetsReceived,
    required this.packetLossRate,
    required this.throughput,
    required this.latency,
    required this.confidence,
    required this.stability,
  });

  final CommChannelId channel;
  final int packetsSent;
  final int packetsReceived;
  final double packetLossRate;
  final double throughput;
  final double latency;
  final double confidence;
  final double stability;
}

class TransmissionConfig {
  const TransmissionConfig({
    this.packetSize = 256,
    this.dataRate = 18000,
    this.redundancy = 0,
    this.retryLimit = 5,
    this.modulation = 'default',
  });

  final int packetSize;
  final double dataRate;
  final int redundancy;
  final int retryLimit;
  final String modulation;
}

class ChannelCapabilities {
  const ChannelCapabilities({
    required this.channelId,
    required this.name,
    required this.maxThroughput,
    required this.minLatency,
    required this.supportsBinary,
    required this.hardwareImplemented,
  });

  final CommChannelId channelId;
  final String name;
  final double maxThroughput;
  final double minLatency;
  final bool supportsBinary;
  final bool hardwareImplemented;
}

class ChannelDecision {
  const ChannelDecision({
    required this.selectedChannel,
    required this.score,
    required this.confidence,
    required this.reason,
  });

  final CommChannelId selectedChannel;
  final double score;
  final double confidence;
  final String reason;
}

class ScoringWeights {
  const ScoringWeights({
    this.throughput = 0.35,
    this.reliability = 0.25,
    this.latency = 0.15,
    this.confidence = 0.15,
    this.stability = 0.10,
  });

  final double throughput;
  final double reliability;
  final double latency;
  final double confidence;
  final double stability;
}

class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.totalPackets,
    required this.sentPackets,
    required this.acknowledgedPackets,
    required this.receivedPackets,
    required this.lastConfirmedSequence,
    required this.retryCount,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.progressPercent,
  });

  final String transferId;
  final int totalPackets;
  final int sentPackets;
  final int acknowledgedPackets;
  final int receivedPackets;
  final int lastConfirmedSequence;
  final int retryCount;
  final int bytesTransferred;
  final int totalBytes;
  final double progressPercent;
}

class SwitchEvent {
  const SwitchEvent({
    required this.fromChannel,
    required this.toChannel,
    required this.lastConfirmedPacket,
    required this.timestamp,
    required this.reason,
  });

  final CommChannelId fromChannel;
  final CommChannelId toChannel;
  final int lastConfirmedPacket;
  final int timestamp;
  final String reason;
}

class LogEntry {
  const LogEntry({
    required this.category,
    required this.message,
    required this.timestamp,
    this.data,
  });

  final String category;
  final String message;
  final int timestamp;
  final Map<String, dynamic>? data;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.state,
    required this.role,
    required this.currentChannel,
    required this.channelScore,
    required this.channelConfidence,
    required this.metrics,
    required this.progress,
    required this.channelScores,
    required this.switchEvents,
    required this.logs,
    required this.availableChannels,
  });

  final TransferState state;
  final EndpointRole role;
  final CommChannelId? currentChannel;
  final double channelScore;
  final double channelConfidence;
  final ChannelMetrics? metrics;
  final TransferProgress? progress;
  final Map<String, double> channelScores;
  final List<SwitchEvent> switchEvents;
  final List<LogEntry> logs;
  final List<CommChannelId> availableChannels;
}

const defaultTransmissionConfig = TransmissionConfig();
const defaultScoringWeights = ScoringWeights();
const switchHysteresisThreshold = 0.15;
const degradationThreshold = 0.65;

String channelIdToName(CommChannelId id) {
  switch (id) {
    case CommChannelId.optical:
      return 'OPTICAL';
    case CommChannelId.acoustic:
      return 'ACOUSTIC';
    case CommChannelId.vibration:
      return 'VIBRATION';
  }
}

String transferStateLabel(TransferState s) {
  switch (s) {
    case TransferState.idle:
      return 'IDLE';
    case TransferState.discovering:
      return 'DISCOVERING';
    case TransferState.testingChannels:
      return 'TESTING_CHANNELS';
    case TransferState.negotiating:
      return 'NEGOTIATING';
    case TransferState.transferring:
      return 'TRANSFERRING';
    case TransferState.degraded:
      return 'DEGRADED';
    case TransferState.switchingChannel:
      return 'SWITCHING_CHANNEL';
    case TransferState.recovering:
      return 'RECOVERING';
    case TransferState.completed:
      return 'COMPLETED';
    case TransferState.failed:
      return 'FAILED';
  }
}
