import 'dart:convert';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';

/// Magic for Adaptive Physical Communication Fountain frames ("APCF").
const qrFountainMagic = [0x41, 0x50, 0x43, 0x46];

/// Wire format version. v2 carries frames as raw QR byte-mode data (no base64)
/// and adds a flags byte for session-level compression. v3 keeps the layout
/// but changes the LT neighbour mapping, so v2 frames must be rejected rather
/// than decoded into garbage.
const qrFountainVersion = 3;

/// ASCII prefix used only by the web preview sampler, which can read text but
/// not raw byte segments.
const qrFountainQrPrefix = 'FQR3:';

/// Fixed header size before payload (magic+ver+flags+fields), excluding CRC.
const qrFountainHeaderSize = 22;

/// CRC size trailing each frame.
const qrFountainCrcSize = 4;

/// Total overhead bytes around the fountain payload.
const qrFountainOverhead = qrFountainHeaderSize + qrFountainCrcSize;

/// Flag: the reassembled file is gzip-compressed and must be inflated.
const qrFountainFlagGzip = 0x01;

/// Parsed APCF fountain QR frame.
class QrFountainFrame {
  const QrFountainFrame({
    required this.sessionId,
    required this.symbolIndex,
    required this.k,
    required this.blockLen,
    required this.fileLen,
    required this.payload,
    this.flags = 0,
  });

  final int sessionId;
  final int symbolIndex;
  final int k;
  final int blockLen;
  final int fileLen;
  final Uint8List payload;
  final int flags;

  bool get isGzip => (flags & qrFountainFlagGzip) != 0;

  int get encodedLength => qrFountainOverhead + payload.length;
}

/// Pack / parse APCF fountain frames for QR transport.
class QrFountainFrameCodec {
  const QrFountainFrameCodec();

  /// Encode one symbol into a binary frame, ready for QR byte mode.
  Uint8List encode(QrFountainFrame frame) {
    if (frame.payload.length != frame.blockLen) {
      throw ArgumentError('payload length must equal blockLen');
    }
    final out = Uint8List(qrFountainOverhead + frame.blockLen);
    var o = 0;
    out[o++] = qrFountainMagic[0];
    out[o++] = qrFountainMagic[1];
    out[o++] = qrFountainMagic[2];
    out[o++] = qrFountainMagic[3];
    out[o++] = qrFountainVersion;
    out[o++] = frame.flags & 0xFF;
    o = _writeU32(out, o, frame.sessionId);
    o = _writeU32(out, o, frame.symbolIndex);
    o = _writeU16(out, o, frame.k);
    o = _writeU16(out, o, frame.blockLen);
    o = _writeU32(out, o, frame.fileLen);
    out.setRange(o, o + frame.blockLen, frame.payload);
    o += frame.blockLen;
    final crc = computeCrc32(Uint8List.sublistView(out, 0, o));
    _writeU32(out, o, crc);
    return out;
  }

  /// Parse a binary frame; returns null if magic/CRC/structure invalid.
  QrFountainFrame? decode(Uint8List raw) {
    if (raw.length < qrFountainOverhead) return null;
    if (raw[0] != qrFountainMagic[0] ||
        raw[1] != qrFountainMagic[1] ||
        raw[2] != qrFountainMagic[2] ||
        raw[3] != qrFountainMagic[3]) {
      return null;
    }
    if (raw[4] != qrFountainVersion) return null;

    final flags = raw[5];
    var o = 6;
    final sessionId = _readU32(raw, o);
    o += 4;
    final symbolIndex = _readU32(raw, o);
    o += 4;
    final k = _readU16(raw, o);
    o += 2;
    final blockLen = _readU16(raw, o);
    o += 2;
    final fileLen = _readU32(raw, o);
    o += 4;

    if (k < 1 || blockLen < 1) return null;
    // QR byte mode pads to the codeword boundary, so trailing bytes are normal.
    final expected = qrFountainOverhead + blockLen;
    if (raw.length < expected) return null;

    final payload = Uint8List.sublistView(raw, o, o + blockLen);
    o += blockLen;
    final expectedCrc = _readU32(raw, o);
    final body = Uint8List.sublistView(raw, 0, o);
    if (computeCrc32(body) != expectedCrc) return null;

    return QrFountainFrame(
      sessionId: sessionId,
      symbolIndex: symbolIndex,
      k: k,
      blockLen: blockLen,
      fileLen: fileLen,
      payload: Uint8List.fromList(payload),
      flags: flags,
    );
  }

  /// ASCII-safe QR payload for text-only decoders (web preview sampler).
  String encodeToQrString(QrFountainFrame frame) =>
      '$qrFountainQrPrefix${base64Url.encode(encode(frame))}';

  /// Decode QR text (FQR3 base64) or raw binary / latin1 fallbacks.
  QrFountainFrame? decodeFromQrString(String text) {
    if (text.isEmpty) return null;
    final trimmed = text.trim();

    if (trimmed.startsWith(qrFountainQrPrefix)) {
      try {
        final b64 = trimmed.substring(qrFountainQrPrefix.length);
        return decode(Uint8List.fromList(base64Url.decode(b64)));
      } catch (_) {
        return null;
      }
    }

    final fromUnits = decode(Uint8List.fromList(trimmed.codeUnits));
    if (fromUnits != null) return fromUnits;

    try {
      return decode(Uint8List.fromList(utf8.encode(trimmed)));
    } catch (_) {
      return null;
    }
  }

  /// Decode from the raw QR byte segment — the primary receive path.
  QrFountainFrame? decodeFromQrBytes(Uint8List bytes) {
    final direct = decode(bytes);
    if (direct != null) return direct;

    try {
      final asText = utf8.decode(bytes, allowMalformed: true);
      return decodeFromQrString(asText);
    } catch (_) {
      return null;
    }
  }
}

const qrFountainFrameCodec = QrFountainFrameCodec();

int _writeU16(Uint8List out, int offset, int value) {
  out[offset] = (value >> 8) & 0xFF;
  out[offset + 1] = value & 0xFF;
  return offset + 2;
}

int _writeU32(Uint8List out, int offset, int value) {
  out[offset] = (value >> 24) & 0xFF;
  out[offset + 1] = (value >> 16) & 0xFF;
  out[offset + 2] = (value >> 8) & 0xFF;
  out[offset + 3] = value & 0xFF;
  return offset + 4;
}

int _readU16(Uint8List data, int offset) =>
    ((data[offset] << 8) | data[offset + 1]) & 0xFFFF;

int _readU32(Uint8List data, int offset) =>
    ((data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3]) &
    0xFFFFFFFF;
