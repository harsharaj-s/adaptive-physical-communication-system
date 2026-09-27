import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/acoustic/reed_solomon.dart';

/// Header laid down in front of every acoustic fountain symbol.
///
/// Kept to nine bytes because the channel carries only tens of bytes per
/// second, yet it still repeats the session parameters in every frame so a
/// receiver can join a transmission that is already under way.
const acousticHeaderSize = 9;

/// CRC-16 trailing the header and payload, inside the Reed-Solomon codeword.
const acousticCrcSize = 2;

/// Overhead around the fountain payload, excluding Reed-Solomon parity.
const acousticFrameOverhead = acousticHeaderSize + acousticCrcSize;

/// One fountain symbol as carried over sound.
class AcousticFrame {
  const AcousticFrame({
    required this.sessionId,
    required this.symbolIndex,
    required this.k,
    required this.blockLen,
    required this.fileLen,
    required this.payload,
  });

  /// Single byte: enough to tell two overlapping transmissions apart.
  final int sessionId;
  final int symbolIndex;
  final int k;
  final int blockLen;
  final int fileLen;
  final Uint8List payload;
}

/// Pack and unpack acoustic fountain frames with Reed-Solomon protection.
///
/// Sound delivers a few percent of bytes wrong even in a quiet room, so a
/// bare checksum would throw away almost every frame. Parity repairs the
/// damaged bytes; the CRC then confirms the repair, since a Reed-Solomon
/// decoder can occasionally "correct" badly mangled input into the wrong
/// codeword.
class AcousticFrameCodec {
  AcousticFrameCodec({required this.parityBytes})
      : _rs = ReedSolomon(parityBytes);

  final int parityBytes;
  final ReedSolomon _rs;

  int get correctableBytes => _rs.correctableBytes;

  /// Total bytes on the wire for a payload of [blockLen].
  int codewordLength(int blockLen) =>
      acousticFrameOverhead + blockLen + parityBytes;

  Uint8List encode(AcousticFrame frame) {
    if (frame.payload.length != frame.blockLen) {
      throw ArgumentError('payload length must equal blockLen');
    }
    final body = Uint8List(acousticFrameOverhead + frame.blockLen);
    body[0] = (frame.symbolIndex >> 8) & 0xFF;
    body[1] = frame.symbolIndex & 0xFF;
    body[2] = (frame.k >> 8) & 0xFF;
    body[3] = frame.k & 0xFF;
    body[4] = frame.blockLen & 0xFF;
    body[5] = (frame.fileLen >> 16) & 0xFF;
    body[6] = (frame.fileLen >> 8) & 0xFF;
    body[7] = frame.fileLen & 0xFF;
    body[8] = frame.sessionId & 0xFF;
    body.setRange(acousticHeaderSize, acousticHeaderSize + frame.blockLen,
        frame.payload);

    final crc = crc16(
      Uint8List.sublistView(body, 0, acousticHeaderSize + frame.blockLen),
    );
    body[body.length - 2] = (crc >> 8) & 0xFF;
    body[body.length - 1] = crc & 0xFF;

    return _rs.encode(body);
  }

  /// Repair and parse a received codeword, or null if it is beyond saving.
  ///
  /// With [reliability] (one score per byte, higher is surer) a failed plain
  /// decode is retried with the least reliable bytes declared as erasures —
  /// generalised minimum-distance decoding. An erasure costs one parity byte
  /// against an error's two, so when the demodulator's doubts line up with
  /// its mistakes, noticeably more damage becomes repairable. Every retry
  /// leaves some parity unspent so the decoder can still refuse garbage, and
  /// the CRC vets whatever it accepts.
  AcousticFrame? decode(
    Uint8List codeword, {
    required int blockLen,
    Float64List? reliability,
  }) {
    final expected = codewordLength(blockLen);
    if (codeword.length < expected) return null;
    final word = Uint8List.sublistView(codeword, 0, expected);
    final dataLength = acousticFrameOverhead + blockLen;

    final plain = _parse(_rs.decode(word, dataLength: dataLength), blockLen);
    if (plain != null || reliability == null) return plain;
    if (reliability.length < expected) return null;

    final order = List<int>.generate(expected, (i) => i)
      ..sort((a, b) => reliability[a].compareTo(reliability[b]));
    for (var erased = gmdStep;
        erased <= parityBytes - gmdReserve;
        erased += gmdStep) {
      final frame = _parse(
        _rs.decode(
          word,
          dataLength: dataLength,
          erasures: order.sublist(0, erased),
        ),
        blockLen,
      );
      if (frame != null) return frame;
    }
    return null;
  }

  /// Erasures added per retry.
  static const gmdStep = 4;

  /// Parity never spent on erasures, so each retry keeps the power to detect
  /// that the word is beyond repair.
  static const gmdReserve = 4;

  AcousticFrame? _parse(Uint8List? body, int blockLen) {
    if (body == null) return null;

    final payloadEnd = acousticHeaderSize + blockLen;
    final stated = (body[body.length - 2] << 8) | body[body.length - 1];
    if (crc16(Uint8List.sublistView(body, 0, payloadEnd)) != stated) return null;

    final declaredBlockLen = body[4];
    if (declaredBlockLen != blockLen) return null;

    final k = (body[2] << 8) | body[3];
    if (k < 1) return null;

    return AcousticFrame(
      symbolIndex: (body[0] << 8) | body[1],
      k: k,
      blockLen: declaredBlockLen,
      fileLen: (body[5] << 16) | (body[6] << 8) | body[7],
      sessionId: body[8],
      payload: Uint8List.fromList(
        Uint8List.sublistView(body, acousticHeaderSize, payloadEnd),
      ),
    );
  }
}

/// CRC-16/CCITT-FALSE.
int crc16(Uint8List data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= byte << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}
