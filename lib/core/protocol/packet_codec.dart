import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/types/types.dart';

const headerSize = 24;
const crcSize = 4;

class PacketHeader {
  const PacketHeader({
    required this.protocolVersion,
    required this.sessionId,
    required this.transferId,
    required this.packetType,
    required this.channelId,
    required this.sequenceNumber,
    required this.payloadLength,
    this.totalPackets = 0,
  });

  final int protocolVersion;
  final int sessionId;
  final int transferId;
  final PacketType packetType;
  final CommChannelId channelId;
  final int sequenceNumber;
  final int payloadLength;

  /// Total data packets in this transfer (0 = unknown / legacy).
  final int totalPackets;
}

class DecodedPacket extends PacketHeader {
  DecodedPacket({
    required super.protocolVersion,
    required super.sessionId,
    required super.transferId,
    required super.packetType,
    required super.channelId,
    required super.sequenceNumber,
    required super.payloadLength,
    super.totalPackets = 0,
    required this.payload,
    required this.crc,
    required this.raw,
  });

  final Uint8List payload;
  final int crc;
  final Uint8List raw;
}

int createSessionId() => Random().nextInt(0xFFFFFFFF);
int createTransferId() => Random().nextInt(0xFFFFFFFF);

final _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var crc = i;
    for (var j = 0; j < 8; j++) {
      crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >>> 1) : crc >>> 1;
    }
    table[i] = crc;
  }
  return table;
}

int computeCrc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

bool verifyCrc32(Uint8List data, int expectedCrc) =>
    computeCrc32(data) == expectedCrc;

class PacketCodec {
  Uint8List encode(PacketHeader header, [Uint8List? payload]) {
    final data = payload ?? Uint8List(0);
    final totalSize = headerSize + data.length + crcSize;
    final buffer = ByteData(totalSize);

    buffer.setUint8(0, header.protocolVersion);
    buffer.setUint32(1, header.sessionId, Endian.little);
    buffer.setUint32(5, header.transferId, Endian.little);
    buffer.setUint8(9, header.packetType.value);
    buffer.setUint8(10, header.channelId.value);
    buffer.setUint32(11, header.sequenceNumber, Endian.little);
    buffer.setUint16(15, header.payloadLength, Endian.little);
    buffer.setUint16(17, header.totalPackets.clamp(0, 0xFFFF), Endian.little);

    final result = buffer.buffer.asUint8List(0, totalSize);
    if (data.isNotEmpty) {
      result.setRange(headerSize, headerSize + data.length, data);
    }

    final crcData = result.sublist(0, headerSize + data.length);
    final crc = computeCrc32(crcData);
    buffer.setUint32(headerSize + data.length, crc, Endian.little);

    return result;
  }

  DecodedPacket? decode(Uint8List raw) {
    if (raw.length < headerSize + crcSize) return null;

    final view = ByteData.sublistView(raw);
    if (view.getUint8(0) != protocolVersion) return null;

    final payloadLength = view.getUint16(15, Endian.little);
    final expectedSize = headerSize + payloadLength + crcSize;
    if (raw.length < expectedSize) return null;

    final crcOffset = headerSize + payloadLength;
    final expectedCrc = view.getUint32(crcOffset, Endian.little);
    final crcData = raw.sublist(0, crcOffset);
    if (computeCrc32(crcData) != expectedCrc) return null;

    return DecodedPacket(
      protocolVersion: view.getUint8(0),
      sessionId: view.getUint32(1, Endian.little),
      transferId: view.getUint32(5, Endian.little),
      packetType: PacketType.fromValue(view.getUint8(9)),
      channelId: CommChannelId.fromValue(view.getUint8(10)),
      sequenceNumber: view.getUint32(11, Endian.little),
      payloadLength: payloadLength,
      totalPackets: view.getUint16(17, Endian.little),
      payload: Uint8List.fromList(raw.sublist(headerSize, headerSize + payloadLength)),
      crc: expectedCrc,
      raw: Uint8List.fromList(raw.sublist(0, expectedSize)),
    );
  }
}

final packetCodec = PacketCodec();
