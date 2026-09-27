import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

class ChannelManager {
  ChannelManager(this.logger);

  final StructuredLogger logger;
  final Map<CommChannelId, CommChannel> _channels = {};
  CommChannelId? _activeChannelId;
  final Map<CommChannelId, ChannelTestResult> _testResults = {};

  void registerChannel(CommChannel channel) => _channels[channel.id] = channel;

  CommChannel? getChannel(CommChannelId id) => _channels[id];

  List<CommChannel> get allChannels => _channels.values.toList();

  List<CommChannelId> get availableChannelIds => _channels.keys.toList();

  CommChannel? get activeChannel =>
      _activeChannelId != null ? _channels[_activeChannelId] : null;

  CommChannelId? get activeChannelId => _activeChannelId;

  void setActiveChannel(CommChannelId id) {
    if (!_channels.containsKey(id)) {
      throw StateError('Channel ${channelIdToName(id)} not registered');
    }
    _activeChannelId = id;
  }

  Future<void> initializeAll({bool setupOpticalCamera = true}) async {
    for (final entry in _channels.entries) {
      if (entry.key == CommChannelId.optical) {
        await entry.value.initialize(setupCamera: setupOpticalCamera);
      } else {
        await entry.value.initialize();
      }
    }
  }

  Future<void> startAll({
    bool enableOpticalReceiver = true,
    bool enableVibrationReceiver = true,
    bool enableAcousticReceiver = true,
  }) async {
    for (final entry in _channels.entries) {
      switch (entry.key) {
        case CommChannelId.optical:
          await entry.value.start(enableReceiver: enableOpticalReceiver);
        case CommChannelId.vibration:
          await entry.value.start(enableReceiver: enableVibrationReceiver);
        case CommChannelId.acoustic:
          await entry.value.start(enableReceiver: enableAcousticReceiver);
      }
    }
  }

  Future<void> stopAll() async {
    for (final c in _channels.values) {
      await c.stop();
    }
  }

  Future<List<CommChannelId>> discoverAll(int timeoutMs) async {
    final discovered = <CommChannelId>[];
    for (final entry in _channels.entries) {
      if (await entry.value.discover(timeoutMs)) {
        discovered.add(entry.key);
        logger.discovery(
          'Device discovered on ${channelIdToName(entry.key)} channel',
        );
      }
    }
    return discovered;
  }

  Future<List<ChannelTestResult>> testAll(int testPacketCount) async {
    final results = <ChannelTestResult>[];
    for (final entry in _channels.entries) {
      final result = await entry.value.test(testPacketCount);
      _testResults[entry.key] = result;
      logger.test(
        '${channelIdToName(entry.key)} throughput = ${(result.throughput / 1000).toStringAsFixed(1)} kbps',
      );
      logger.test(
        '${channelIdToName(entry.key)} packet loss = ${(result.packetLossRate * 100).toStringAsFixed(1)}%',
      );
      results.add(result);
    }
    return results;
  }

  Future<ChannelTestResult> testChannel(
    CommChannelId id,
    int testPacketCount,
  ) async {
    final channel = _channels[id];
    if (channel == null) {
      throw StateError('Channel ${channelIdToName(id)} not found');
    }
    final result = await channel.test(testPacketCount);
    _testResults[id] = result;
    logger.test(
      '${channelIdToName(id)} throughput = ${(result.throughput / 1000).toStringAsFixed(1)} kbps',
    );
    logger.test(
      '${channelIdToName(id)} packet loss = ${(result.packetLossRate * 100).toStringAsFixed(1)}%',
    );
    return result;
  }

  ChannelTestResult? getTestResult(CommChannelId id) => _testResults[id];

  Map<CommChannelId, ChannelMetrics> getMetricsForAll() {
    return {for (final e in _channels.entries) e.key: e.value.getMetrics()};
  }

  Future<void> transmit(Uint8List packet) async {
    final channel = activeChannel;
    if (channel == null) throw StateError('No active channel selected');
    await channel.transmit(packet);
  }

  Future<List<DecodedPacket>> receive() async {
    final all = <DecodedPacket>[];
    for (final c in _channels.values) {
      all.addAll(await c.receive());
    }
    return all;
  }

  Future<List<DecodedPacket>> receiveActive() async {
    final channel = activeChannel;
    if (channel == null) return [];
    return channel.receive();
  }
}