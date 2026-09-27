import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/manager/channel_manager.dart';
import 'package:adaptive_physical_communication/core/manager/transfer_manager.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/transport/reliable_transport.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

void main() {
  group('TransferMode', () {
    test('broadcast is default in hardware TransferManagerConfig', () {
      const config = TransferManagerConfig(mode: OperationMode.hardware);
      expect(config.transferMode, TransferMode.broadcast);
    });
  });

  group('ReliableTransport broadcast', () {
    late StructuredLogger logger;
    late ChannelManager channelManager;

    setUp(() {
      logger = StructuredLogger();
      channelManager = ChannelManager(logger);
    });

    test('sender completes without ACK in broadcast mode', () async {
      final transmitted = <Uint8List>[];
      channelManager.registerChannel(_StubChannel(
        onTransmit: (p) => transmitted.add(p),
      ));
      await channelManager.initializeAll();
      await channelManager.startAll();
      channelManager.setActiveChannel(CommChannelId.optical);

      final transport = ReliableTransport(
        sessionId: 1,
        transferId: 42,
        channelId: CommChannelId.optical,
        channelManager: channelManager,
        logger: logger,
        broadcastMode: true,
        config: const TransportConfig(windowSize: 2),
      );

      final data = Uint8List.fromList('hello broadcast'.codeUnits);
      final packets = transport.createDataPackets(data);
      expect(packets.length, greaterThan(0));

      while (!transport.allPacketsTransmitted) {
        await transport.sendNextWindow(packets);
      }

      expect(transport.allPacketsTransmitted, isTrue);
      expect(transport.lastAckedSequence, 0);
      expect(transmitted.length, packets.length);
    });

    test('receiver deduplicates sequence numbers', () async {
      channelManager.registerChannel(_StubChannel());
      await channelManager.initializeAll();
      await channelManager.startAll();
      channelManager.setActiveChannel(CommChannelId.optical);

      final transport = ReliableTransport(
        sessionId: 1,
        transferId: 99,
        channelId: CommChannelId.optical,
        channelManager: channelManager,
        logger: logger,
      );

      final payload = Uint8List.fromList('x'.codeUnits);
      final raw = packetCodec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: 1,
          transferId: 99,
          packetType: PacketType.data,
          channelId: CommChannelId.optical,
          sequenceNumber: 1,
          payloadLength: payload.length,
        ),
        payload,
      );
      final decoded = packetCodec.decode(raw)!;

      final first = await transport.handleReceivedPackets([decoded]);
      final second = await transport.handleReceivedPackets([decoded]);

      expect(first.length, 1);
      expect(second.length, 1);
      expect(transport.duplicateCount, 1);
    });
  });
}

class _StubChannel implements CommChannel {
  _StubChannel({void Function(Uint8List)? onTransmit})
      : _onTransmit = onTransmit;

  final void Function(Uint8List)? _onTransmit;

  @override
  CommChannelId get id => CommChannelId.optical;

  @override
  ChannelCapabilities get capabilities => const ChannelCapabilities(
        channelId: CommChannelId.optical,
        name: 'Stub Optical',
        maxThroughput: 1000,
        minLatency: 10,
        supportsBinary: true,
        hardwareImplemented: false,
      );

  @override
  Future<bool> discover(int timeoutMs) async => true;

  @override
  Future<void> initialize({bool setupCamera = true}) async {}

  @override
  bool isAvailable() => true;

  @override
  Future<List<DecodedPacket>> receive() async => [];

  @override
  Future<void> start({bool enableReceiver = true}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<ChannelTestResult> test(int testPacketCount) async => ChannelTestResult(
        channel: id,
        packetsSent: testPacketCount,
        packetsReceived: testPacketCount,
        packetLossRate: 0,
        throughput: 1000,
        latency: 10,
        confidence: 1,
        stability: 1,
      );

  @override
  Future<void> transmit(Uint8List packet) async => _onTransmit?.call(packet);

  @override
  ChannelMetrics getMetrics() => ChannelMetrics(
        throughput: 1000,
        packetLoss: 0,
        latency: 10,
        reliability: 1,
        errorRate: 0,
        confidence: 1,
        stability: 1,
        timestamp: 0,
      );

  @override
  void setTransmissionConfig(TransmissionConfig config) {}
}
