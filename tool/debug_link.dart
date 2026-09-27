import 'package:flutter/foundation.dart';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/manager/channel_manager.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/simulation/simulated_medium.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

Future<void> main() async {
  final loggerA = StructuredLogger();
  final loggerB = StructuredLogger();
  final cmA = ChannelManager(loggerA);
  final cmB = ChannelManager(loggerB);

  final config = SimulatedChannelConfig(profile: defaultOpticalProfile);
  final mediumA = SimulatedMedium('A', config);
  final mediumB = SimulatedMedium('B', config);
  VirtualLink(mediumA, mediumB);

  cmA.registerChannel(createOpticalChannel(mediumA, config));
  cmB.registerChannel(createOpticalChannel(mediumB, config));
  await cmA.startAll();
  await cmB.startAll();
  cmA.setActiveChannel(CommChannelId.optical);
  cmB.setActiveChannel(CommChannelId.optical);

  final payload = Uint8List.fromList([1, 2, 3, 4]);
  final packet = packetCodec.encode(PacketHeader(
    protocolVersion: protocolVersion,
    sessionId: 1,
    transferId: 2,
    packetType: PacketType.data,
    channelId: CommChannelId.optical,
    sequenceNumber: 1,
    payloadLength: payload.length,
  ), payload);

  debugPrint('Sending packet...');
  await cmA.transmit(packet);
  debugPrint('Polling B...');
  final received = await cmB.receiveActive();
  debugPrint('B received ${received.length} packets');
  if (received.isNotEmpty) {
    debugPrint('Payload: ${received.first.payload}');
  }
}
