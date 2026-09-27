import 'dart:convert';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';

/// Magic prefix for optical QR payloads (Adaptive Physical Communication System).
const qrOpticalMagic = 'APCS1';

/// Max raw bytes per QR chunk — sized for fast phone scanning (QR version ~15-20).
const qrMaxChunkBytes = 1400;

/// How long each QR frame stays on screen during TX (ms).
const qrFrameDurationMs = 220;

/// Repeat each chunk once for reliability (2 total shows).
const qrFrameRepeatCount = 2;

/// Minimum interval between QR decode attempts on RX camera frames.
const qrScanIntervalMs = 40;

/// Parsed chunk from a scanned QR code.
class QrOpticalChunk {
  const QrOpticalChunk({
    required this.messageId,
    required this.index,
    required this.total,
    required this.data,
  });

  final String messageId;
  final int index;
  final int total;
  final Uint8List data;
}

/// Encodes packet bytes into scannable QR strings and reassembles scanned chunks.
class QrOpticalCodec {
  String _messageIdFor(Uint8List data) {
    final crc = computeCrc32(data);
    return (crc & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }

  /// Split [data] into one or more QR-ready strings.
  List<String> encodeToQrStrings(Uint8List data) {
    if (data.isEmpty) return const [];

    final messageId = _messageIdFor(data);
    if (data.length <= qrMaxChunkBytes) {
      return [_formatChunk(messageId, 1, 1, data)];
    }

    final chunks = <String>[];
    final total = (data.length / qrMaxChunkBytes).ceil();
    for (var i = 0; i < total; i++) {
      final start = i * qrMaxChunkBytes;
      final end = (start + qrMaxChunkBytes).clamp(0, data.length);
      chunks.add(_formatChunk(messageId, i + 1, total, data.sublist(start, end)));
    }
    return chunks;
  }

  String _formatChunk(String messageId, int index, int total, Uint8List chunk) {
    final encoded = base64Url.encode(chunk);
    return '$qrOpticalMagic:$messageId:$index/$total:$encoded';
  }

  /// Parse a scanned QR string; returns null if not an APCS optical chunk.
  QrOpticalChunk? decodeQrString(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('$qrOpticalMagic:')) return null;

    final parts = trimmed.split(':');
    if (parts.length != 4) return null;

    final indexTotal = parts[2].split('/');
    if (indexTotal.length != 2) return null;

    final index = int.tryParse(indexTotal[0]);
    final total = int.tryParse(indexTotal[1]);
    if (index == null || total == null || index < 1 || total < 1 || index > total) {
      return null;
    }

    try {
      final data = base64Url.decode(parts[3]);
      if (data.isEmpty) return null;
      return QrOpticalChunk(
        messageId: parts[1],
        index: index,
        total: total,
        data: Uint8List.fromList(data),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Collects scanned chunks until a full byte stream is ready.
class QrOpticalReassembler {
  final Map<String, _PendingMessage> _pending = {};

  /// Returns complete reassembled bytes when all chunks arrive; otherwise null.
  Uint8List? addChunk(QrOpticalChunk chunk) {
    final pending = _pending.putIfAbsent(
      chunk.messageId,
      () => _PendingMessage(total: chunk.total),
    );

    if (pending.total != chunk.total) {
      pending.total = chunk.total;
      pending.parts.clear();
    }

    pending.parts[chunk.index] = chunk.data;
    pending.lastSeenMs = DateTime.now().millisecondsSinceEpoch;

    if (pending.parts.length < pending.total) return null;

    for (var i = 1; i <= pending.total; i++) {
      if (!pending.parts.containsKey(i)) return null;
    }

    final buffer = BytesBuilder(copy: false);
    for (var i = 1; i <= pending.total; i++) {
      buffer.add(pending.parts[i]!);
    }
    _pending.remove(chunk.messageId);
    return buffer.takeBytes();
  }

  void pruneStale({int maxAgeMs = 15000}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _pending.removeWhere((_, pending) => now - pending.lastSeenMs > maxAgeMs);
  }

  void reset() => _pending.clear();

  /// Best in-progress chunk collection (received count, total chunks).
  (int received, int total)? get progress {
    if (_pending.isEmpty) return null;
    _PendingMessage? best;
    for (final p in _pending.values) {
      if (best == null || p.parts.length > best.parts.length) {
        best = p;
      }
    }
    if (best == null) return null;
    return (best.parts.length, best.total);
  }
}

class _PendingMessage {
  _PendingMessage({required this.total});

  int total;
  final Map<int, Uint8List> parts = {};
  int lastSeenMs = DateTime.now().millisecondsSinceEpoch;
}

final qrOpticalCodec = QrOpticalCodec();
