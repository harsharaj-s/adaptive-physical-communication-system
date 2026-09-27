import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/manager/channel_manager.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

class TransportConfig {
  const TransportConfig({
    this.ackTimeoutMs = 500,
    this.maxRetries = 5,
    this.windowSize = 8,
  });

  final int ackTimeoutMs;
  final int maxRetries;
  final int windowSize;
}

const defaultTransportConfig = TransportConfig();

class _PendingPacket {
  _PendingPacket({
    required this.sequenceNumber,
    required this.raw,
    required this.sentAt,
  });

  final int sequenceNumber;
  final Uint8List raw;
  int sentAt;
  int retries = 0;
}

class ReliableTransport {
  ReliableTransport({
    required this.sessionId,
    required this.transferId,
    required CommChannelId channelId,
    required this.channelManager,
    required this.logger,
    this.transmissionConfig = defaultTransmissionConfig,
    this.config = defaultTransportConfig,
    this.broadcastMode = false,
  }) : _channelId = channelId;

  final int sessionId;
  final int transferId;
  final ChannelManager channelManager;
  final StructuredLogger logger;
  final TransmissionConfig transmissionConfig;
  final TransportConfig config;
  final bool broadcastMode;

  CommChannelId _channelId;
  int _nextSequence = 1;
  int _lastAckedSequence = 0;
  int _lastSentSequence = 0;
  final Map<int, _PendingPacket> _pendingPackets = {};
  int _retryCount = 0;
  final Set<int> _receivedSequences = {};
  int _expectedTotalPackets = 0;
  final Map<int, Uint8List> _reassemblyBuffer = {};
  int _duplicateCount = 0;

  CommChannelId get channelId => _channelId;

  void setChannelId(CommChannelId id) => _channelId = id;

  int get lastAckedSequence => _lastAckedSequence;
  int get lastSentSequence => _lastSentSequence;
  int get retryCount => _retryCount;
  int get duplicateCount => _duplicateCount;

  bool get allPacketsTransmitted =>
      broadcastMode &&
      _expectedTotalPackets > 0 &&
      _lastSentSequence >= _expectedTotalPackets;

  /// True when every in-flight packet hit [TransportConfig.maxRetries].
  bool get hasPendingRetriesExhausted {
    if (_pendingPackets.isEmpty) return false;
    return _pendingPackets.values.every((p) => p.retries >= config.maxRetries);
  }

  TransferProgress getProgress(int totalPackets, int totalBytes) {
    final receivedCount = _reassemblyBuffer.length;
    return TransferProgress(
      transferId: transferId.toString(),
      totalPackets: totalPackets,
      sentPackets: _nextSequence - 1,
      acknowledgedPackets: _lastAckedSequence,
      receivedPackets: receivedCount,
      lastConfirmedSequence: _lastAckedSequence,
      retryCount: _retryCount,
      bytesTransferred: receivedCount * transmissionConfig.packetSize,
      totalBytes: totalBytes,
      progressPercent:
          totalPackets > 0 ? (receivedCount / totalPackets) * 100 : 0,
    );
  }

  List<Uint8List> createDataPackets(Uint8List data) {
    final packetSize = transmissionConfig.packetSize;
    final chunks = <Uint8List>[];
    var offset = 0;
    while (offset < data.length) {
      final end = (offset + packetSize).clamp(0, data.length);
      chunks.add(data.sublist(offset, end));
      offset += packetSize;
    }
    if (chunks.isEmpty) {
      chunks.add(Uint8List(0));
    }

    final total = chunks.length;
    final packets = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      packets.add(packetCodec.encode(
        PacketHeader(
          protocolVersion: protocolVersion,
          sessionId: sessionId,
          transferId: transferId,
          packetType: PacketType.data,
          channelId: _channelId,
          sequenceNumber: i + 1,
          payloadLength: chunk.length,
          totalPackets: total,
        ),
        chunk,
      ));
    }

    _expectedTotalPackets = total;
    _nextSequence = 1;
    return packets;
  }

  Future<void> sendNextWindow(List<Uint8List> allPackets) async {
    if (broadcastMode) {
      final windowEnd =
          (_lastSentSequence + config.windowSize).clamp(0, allPackets.length);
      for (var seq = _lastSentSequence + 1; seq <= windowEnd; seq++) {
        if (seq > allPackets.length) break;
        await channelManager.transmit(allPackets[seq - 1]);
        _lastSentSequence = seq;
        logger.transfer('Broadcast packet $seq/${allPackets.length}');
      }
      return;
    }

    final windowEnd = (_lastAckedSequence + config.windowSize)
        .clamp(0, allPackets.length);

    for (var seq = _lastAckedSequence + 1; seq <= windowEnd; seq++) {
      if (seq > allPackets.length) break;
      final packet = allPackets[seq - 1];
      _pendingPackets.putIfAbsent(
        seq,
        () => _PendingPacket(
          sequenceNumber: seq,
          raw: packet,
          sentAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await channelManager.transmit(_pendingPackets[seq]!.raw);
    }
  }

  Future<List<Uint8List>> handleReceivedPackets(List<DecodedPacket> packets) async {
    final outgoing = <Uint8List>[];

    for (final packet in packets) {
      if (packet.transferId != transferId) continue;

      switch (packet.packetType) {
        case PacketType.data:
          outgoing.addAll(_handleDataPacket(packet));
        case PacketType.ack:
          _handleAck(packet);
        case PacketType.nack:
          outgoing.addAll(_createRetransmissions([packet.sequenceNumber]));
        case PacketType.retransmissionRequest:
          outgoing.addAll(_handleRetransmissionRequest(packet));
        default:
          break;
      }
    }

    return outgoing;
  }

  List<Uint8List> _handleDataPacket(DecodedPacket packet) {
    final seq = packet.sequenceNumber;
    final outgoing = <Uint8List>[];

    if (_receivedSequences.contains(seq)) {
      _duplicateCount++;
      outgoing.add(_createAck(seq));
      return outgoing;
    }

    _receivedSequences.add(seq);
    _reassemblyBuffer[seq] = packet.payload;
    logger.transfer('Packet $seq received');
    outgoing.add(_createAck(seq));

    for (final missing in findMissingSequences()) {
      outgoing.add(_createNack(missing));
      logger.transfer('Missing packet $missing detected, requesting retransmission');
    }

    return outgoing;
  }

  void _handleAck(DecodedPacket packet) {
    final ackedSeq = packet.sequenceNumber;
    if (ackedSeq > _lastAckedSequence) {
      _lastAckedSequence = ackedSeq;
      _pendingPackets.removeWhere((seq, _) => seq <= ackedSeq);
      logger.transfer('Packet $ackedSeq acknowledged');
    }
  }

  List<Uint8List> _handleRetransmissionRequest(DecodedPacket packet) {
    final view = ByteData.sublistView(packet.payload);
    final sequences = <int>[];
    for (var i = 0; i < packet.payload.length ~/ 4; i++) {
      sequences.add(view.getUint32(i * 4, Endian.little));
    }
    logger.transfer('Retransmission requested for packets: ${sequences.join(', ')}');
    return _createRetransmissions(sequences);
  }

  List<Uint8List> _createRetransmissions(List<int> sequences) {
    final result = <Uint8List>[];
    for (final seq in sequences) {
      final pending = _pendingPackets[seq];
      if (pending == null) continue;
      if (pending.retries >= config.maxRetries) {
        logger.error('Max retries exceeded for packet $seq');
        continue;
      }
      pending.retries++;
      pending.sentAt = DateTime.now().millisecondsSinceEpoch;
      _retryCount++;
      result.add(pending.raw);
      logger.transfer('Retransmitting packet $seq (retry ${pending.retries})');
    }
    return result;
  }

  List<Uint8List> checkTimeouts() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final toRetransmit = <int>[];
    for (final entry in _pendingPackets.entries) {
      if (now - entry.value.sentAt > config.ackTimeoutMs) {
        if (entry.value.retries >= config.maxRetries) {
          logger.error('Timeout: max retries for packet ${entry.key}');
          continue;
        }
        toRetransmit.add(entry.key);
      }
    }
    return _createRetransmissions(toRetransmit);
  }

  List<int> findMissingSequences() {
    if (_reassemblyBuffer.isEmpty) return [];
    final maxReceived = _reassemblyBuffer.keys.reduce((a, b) => a > b ? a : b);
    final missing = <int>[];
    for (var i = 1; i <= maxReceived; i++) {
      if (!_reassemblyBuffer.containsKey(i)) missing.add(i);
    }
    return missing;
  }

  bool isTransferComplete() {
    if (_expectedTotalPackets == 0) return false;
    for (var i = 1; i <= _expectedTotalPackets; i++) {
      if (!_reassemblyBuffer.containsKey(i)) return false;
    }
    return true;
  }

  Uint8List? reassembleData() {
    if (!isTransferComplete()) return null;
    final parts = <Uint8List>[];
    for (var i = 1; i <= _expectedTotalPackets; i++) {
      final payload = _reassemblyBuffer[i];
      if (payload == null) return null;
      parts.add(payload);
    }
    final totalLength = parts.fold<int>(0, (sum, p) => sum + p.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  void setExpectedTotalPackets(int count) => _expectedTotalPackets = count;

  void resumeFromSequence(int lastConfirmed) {
    _lastAckedSequence = lastConfirmed;
    _pendingPackets.removeWhere((seq, _) => seq <= lastConfirmed);
  }

  Uint8List _createAck(int sequenceNumber) => packetCodec.encode(PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: sessionId,
        transferId: transferId,
        packetType: PacketType.ack,
        channelId: _channelId,
        sequenceNumber: sequenceNumber,
        payloadLength: 0,
      ));

  Uint8List _createNack(int sequenceNumber) => packetCodec.encode(PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: sessionId,
        transferId: transferId,
        packetType: PacketType.nack,
        channelId: _channelId,
        sequenceNumber: sequenceNumber,
        payloadLength: 0,
      ));

  Uint8List createSwitchRequest(CommChannelId newChannelId, int lastConfirmed) {
    final payload = ByteData(8)
      ..setUint32(0, newChannelId.value, Endian.little)
      ..setUint32(4, lastConfirmed, Endian.little);
    return packetCodec.encode(
      PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: sessionId,
        transferId: transferId,
        packetType: PacketType.channelSwitchRequest,
        channelId: _channelId,
        sequenceNumber: lastConfirmed,
        payloadLength: 8,
      ),
      payload.buffer.asUint8List(),
    );
  }

  Uint8List createSwitchAck(CommChannelId newChannelId, int lastConfirmed) {
    final payload = ByteData(8)
      ..setUint32(0, newChannelId.value, Endian.little)
      ..setUint32(4, lastConfirmed, Endian.little);
    return packetCodec.encode(
      PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: sessionId,
        transferId: transferId,
        packetType: PacketType.channelSwitchAck,
        channelId: newChannelId,
        sequenceNumber: lastConfirmed,
        payloadLength: 8,
      ),
      payload.buffer.asUint8List(),
    );
  }

  ({CommChannelId newChannelId, int lastConfirmed})? parseSwitchRequest(
    DecodedPacket packet,
  ) {
    if (packet.packetType != PacketType.channelSwitchRequest) return null;
    final view = ByteData.sublistView(packet.payload);
    return (
      newChannelId: CommChannelId.fromValue(view.getUint32(0, Endian.little)),
      lastConfirmed: view.getUint32(4, Endian.little),
    );
  }

  ({CommChannelId newChannelId, int lastConfirmed})? parseSwitchAck(
    DecodedPacket packet,
  ) {
    if (packet.packetType != PacketType.channelSwitchAck) return null;
    final view = ByteData.sublistView(packet.payload);
    return (
      newChannelId: CommChannelId.fromValue(view.getUint32(0, Endian.little)),
      lastConfirmed: view.getUint32(4, Endian.little),
    );
  }
}
