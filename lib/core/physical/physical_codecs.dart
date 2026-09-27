import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';

/// Goertzel algorithm for single-frequency energy detection in audio samples.
class Goertzel {
  Goertzel({
    required this.sampleRate,
    required this.targetFrequency,
  }) {
    final normalized = 2 * pi * targetFrequency / sampleRate;
    _coeff = 2 * cos(normalized);
  }

  final double sampleRate;
  final double targetFrequency;
  late final double _coeff;

  double detect(List<double> samples) {
    var s0 = 0.0;
    var s1 = 0.0;
    var s2 = 0.0;
    for (final sample in samples) {
      s0 = sample + _coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final power = s1 * s1 + s2 * s2 - _coeff * s1 * s2;
    return power / samples.length;
  }
}

/// FSK physical-layer codec: F0 = bit 0, F1 = bit 1.
class FskCodec {
  FskCodec({
    this.sampleRate = 44100,
    this.f0 = 1800,
    this.f1 = 3200,
    this.symbolDurationMs = 80,
    this.preambleBits = const [1, 0, 1, 0, 1, 0, 1, 0],
  });

  final int sampleRate;
  final double f0;
  final double f1;
  final int symbolDurationMs;
  final List<int> preambleBits;

  int get samplesPerSymbol => (sampleRate * symbolDurationMs / 1000).round();

  List<int> bytesToBits(Uint8List data) {
    final bits = <int>[...preambleBits];
    for (final byte in data) {
      for (var i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    return bits;
  }

  Uint8List bitsToBytes(List<int> bits, {int? expectedByteCount}) {
    final start = _findPreamble(bits);
    if (start < 0) return Uint8List(0);
    final payload = bits.sublist(start + preambleBits.length);
    final byteCount = expectedByteCount ?? payload.length ~/ 8;
    if (byteCount <= 0) return Uint8List(0);
    final result = Uint8List(byteCount);
    for (var b = 0; b < byteCount; b++) {
      var value = 0;
      for (var i = 0; i < 8; i++) {
        final idx = b * 8 + i;
        if (idx < payload.length) {
          value = (value << 1) | payload[idx];
        }
      }
      result[b] = value;
    }
    return result;
  }

  int findPreambleIndex(List<int> bits) => _findPreamble(bits);

  int _findPreamble(List<int> bits) {
    for (var i = 0; i <= bits.length - preambleBits.length; i++) {
      var match = true;
      for (var j = 0; j < preambleBits.length; j++) {
        if (bits[i + j] != preambleBits[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  Float32List generateToneSamples(int bit) {
    final freq = bit == 1 ? f1 : f0;
    final count = samplesPerSymbol;
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      samples[i] = sin(2 * pi * freq * i / sampleRate);
    }
    return samples;
  }

  Float32List encodeBytes(Uint8List data) {
    final bits = bytesToBits(data);
    final total = bits.length * samplesPerSymbol;
    final buffer = Float32List(total);
    var offset = 0;
    for (final bit in bits) {
      final tone = generateToneSamples(bit);
      buffer.setRange(offset, offset + tone.length, tone);
      offset += tone.length;
    }
    return buffer;
  }

  int decodeSymbol(List<double> samples) {
    final g0 = Goertzel(sampleRate: sampleRate.toDouble(), targetFrequency: f0);
    final g1 = Goertzel(sampleRate: sampleRate.toDouble(), targetFrequency: f1);
    final e0 = g0.detect(samples);
    final e1 = g1.detect(samples);
    return e1 > e0 ? 1 : 0;
  }

  /// Returns (f0 energy, f1 energy) normalized roughly to 0–1 for UI meters.
  (double, double) measureToneStrength(List<double> samples) {
    if (samples.isEmpty) return (0, 0);
    final g0 = Goertzel(sampleRate: sampleRate.toDouble(), targetFrequency: f0);
    final g1 = Goertzel(sampleRate: sampleRate.toDouble(), targetFrequency: f1);
    final e0 = (g0.detect(samples) * 800).clamp(0.0, 1.0);
    final e1 = (g1.detect(samples) * 800).clamp(0.0, 1.0);
    return (e0, e1);
  }

  double combinedToneStrength(List<double> samples) {
    final (e0, e1) = measureToneStrength(samples);
    return max(e0, e1);
  }

  List<int> decodeSamples(List<double> samples) {
    final bits = <int>[];
    final n = samplesPerSymbol;
    for (var i = 0; i + n <= samples.length; i += n) {
      bits.add(decodeSymbol(samples.sublist(i, i + n)));
    }
    return bits;
  }
}

/// Continuous FSK decoder — keeps sample buffer across mic chunks.
/// Length-framed: waits for full wire packet (header + payload + CRC) before
/// consuming samples, and only advances past a failed preamble by one symbol.
class FskStreamDecoder {
  FskStreamDecoder({FskCodec? codec}) : _codec = codec ?? FskCodec();

  final FskCodec _codec;
  final List<double> _sampleBuffer = [];

  void addSamples(List<double> samples) => _sampleBuffer.addAll(samples);

  /// Returns decoded wire-packet bytes when a full CRC-valid packet is found.
  Uint8List? pollPacket({int? expectedByteCount}) {
    final n = _codec.samplesPerSymbol;
    if (_sampleBuffer.length < n * 16) return null;

    final bits = <int>[];
    for (var i = 0; i + n <= _sampleBuffer.length; i += n) {
      bits.add(_codec.decodeSymbol(_sampleBuffer.sublist(i, i + n)));
    }

    final preambleIdx = _codec.findPreambleIndex(bits);
    if (preambleIdx < 0) {
      if (_sampleBuffer.length > n * 8) {
        _sampleBuffer.removeRange(0, n);
      }
      _trimBuffer();
      return null;
    }

    final dataStart = preambleIdx + _codec.preambleBits.length;
    final availableBits = bits.length - dataStart;

    // Prefer explicit expected length; otherwise peek header for payloadLength.
    int? wireBytes = expectedByteCount;
    if (wireBytes == null) {
      if (availableBits < headerSize * 8) return null;
      final header = _extractBytes(bits, dataStart, headerSize);
      if (header == null) return null;
      final payloadLength = ByteData.sublistView(header).getUint16(15, Endian.little);
      if (payloadLength > 8192) {
        _consumeSymbols(preambleIdx + 1);
        return null;
      }
      wireBytes = headerSize + payloadLength + crcSize;
    }

    if (availableBits < wireBytes * 8) return null;

    final packetBytes = _extractBytes(bits, dataStart, wireBytes);
    if (packetBytes == null) return null;

    if (packetCodec.decode(packetBytes) != null) {
      _consumeSymbols(dataStart + wireBytes * 8);
      return packetBytes;
    }

    // Bad CRC / framing — skip past this preamble start and retry.
    _consumeSymbols(preambleIdx + 1);
    return null;
  }

  /// Decode a length-prefixed direct envelope (2-byte LE length + payload).
  Uint8List? pollDirectEnvelope({int maxPayloadBytes = 900}) {
    final n = _codec.samplesPerSymbol;
    if (_sampleBuffer.length < n * 16) return null;

    final bits = <int>[];
    for (var i = 0; i + n <= _sampleBuffer.length; i += n) {
      bits.add(_codec.decodeSymbol(_sampleBuffer.sublist(i, i + n)));
    }

    final preambleIdx = _codec.findPreambleIndex(bits);
    if (preambleIdx < 0) {
      if (_sampleBuffer.length > n * 8) {
        _sampleBuffer.removeRange(0, n);
      }
      return null;
    }

    final dataStart = preambleIdx + _codec.preambleBits.length;
    final availableBits = bits.length - dataStart;
    if (availableBits < 16) return null;

    final lenBytes = _extractBytes(bits, dataStart, 2);
    if (lenBytes == null) return null;
    final payloadLen = lenBytes[0] | (lenBytes[1] << 8);
    if (payloadLen <= 0 || payloadLen > maxPayloadBytes) {
      _consumeSymbols(preambleIdx + 1);
      return null;
    }

    final totalBytes = 2 + payloadLen;
    if (availableBits < totalBytes * 8) return null;

    final framed = _extractBytes(bits, dataStart, totalBytes);
    if (framed == null) return null;

    final envelope = Uint8List.sublistView(framed, 2);
    if (!ChatPayloadCodec.isApcmEnvelope(envelope)) {
      _consumeSymbols(preambleIdx + 1);
      return null;
    }

    _consumeSymbols(dataStart + totalBytes * 8);
    return envelope;
  }

  Uint8List? _extractBytes(List<int> bits, int startBit, int byteCount) {
    final need = startBit + byteCount * 8;
    if (bits.length < need) return null;
    final out = Uint8List(byteCount);
    for (var b = 0; b < byteCount; b++) {
      var value = 0;
      for (var i = 0; i < 8; i++) {
        value = (value << 1) | bits[startBit + b * 8 + i];
      }
      out[b] = value;
    }
    return out;
  }

  void _consumeSymbols(int bitCount) {
    final n = _codec.samplesPerSymbol;
    final samples = min(bitCount * n, _sampleBuffer.length);
    if (samples > 0) {
      _sampleBuffer.removeRange(0, samples);
    }
  }

  void _trimBuffer() {
    const maxSamples = 44100 * 8;
    if (_sampleBuffer.length > maxSamples) {
      _sampleBuffer.removeRange(0, _sampleBuffer.length ~/ 2);
    }
  }

  void reset() => _sampleBuffer.clear();

  /// Energy in the FSK tone bands on the latest symbol window (0–1).
  double peekToneStrength() {
    final n = _codec.samplesPerSymbol;
    if (_sampleBuffer.length < n) return 0;
    final window = _sampleBuffer.sublist(_sampleBuffer.length - n);
    return _codec.combinedToneStrength(window);
  }
}

/// Frame a chat envelope for direct acoustic FSK (2-byte LE length prefix).
Uint8List frameDirectEnvelope(Uint8List envelope) {
  final out = Uint8List(2 + envelope.length);
  out[0] = envelope.length & 0xFF;
  out[1] = (envelope.length >> 8) & 0xFF;
  out.setRange(2, out.length, envelope);
  return out;
}

/// Convert float samples to 16-bit PCM WAV bytes for audio playback.
Uint8List pcmToWav(Float32List samples, {int sampleRate = 44100}) {
  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
  }
  final dataSize = pcm.length * 2;
  final buffer = ByteData(44 + dataSize);
  void writeStr(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeStr(0, 'RIFF');
  buffer.setUint32(4, 36 + dataSize, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little);
  buffer.setUint16(22, 1, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little);
  buffer.setUint16(32, 2, Endian.little);
  buffer.setUint16(34, 16, Endian.little);
  writeStr(36, 'data');
  buffer.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    buffer.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return buffer.buffer.asUint8List();
}

/// Optical physical-layer: bright=1, dark=0 with preamble synchronization.
class OpticalBitCodec {
  OpticalBitCodec({
    this.bitDurationMs = 100,
    this.preamble = const [1, 0, 1, 0, 1, 0, 1, 1],
  });

  final int bitDurationMs;
  final List<int> preamble;

  List<int> bytesToBits(Uint8List data) {
    final bits = <int>[...preamble];
    for (final byte in data) {
      for (var i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    return bits;
  }

  Uint8List bitsToBytes(List<int> bits, {int? expectedLength}) {
    final start = _findPreamble(bits);
    if (start < 0) return Uint8List(0);
    final payload = bits.sublist(start + preamble.length);
    final len = expectedLength ?? payload.length ~/ 8;
    final result = Uint8List(len);
    for (var b = 0; b < len; b++) {
      var value = 0;
      for (var i = 0; i < 8; i++) {
        final idx = b * 8 + i;
        if (idx < payload.length) value = (value << 1) | payload[idx];
      }
      result[b] = value;
    }
    return result;
  }

  int _findPreamble(List<int> bits) {
    for (var i = 0; i <= bits.length - preamble.length; i++) {
      var match = true;
      for (var j = 0; j < preamble.length; j++) {
        if (bits[i + j] != preamble[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  bool luminanceToBit(double luminance) => luminance > 0.5;
}

/// Vibration physical-layer: short pulse = 0, long pulse = 1 with preamble sync.
class VibrationBitCodec {
  VibrationBitCodec({
    this.shortPulseMs = 80,
    this.longPulseMs = 180,
    this.gapMs = 60,
    this.preamble = const [0, 1, 0, 1, 0, 1, 1, 0],
    this.detectionThreshold = 12.0,
    this.relativeThreshold = 1.4,
  });

  final int shortPulseMs;
  final int longPulseMs;
  final int gapMs;
  final List<int> preamble;
  final double detectionThreshold;
  final double relativeThreshold;

  int pulseDurationMs(int bit) => bit == 1 ? longPulseMs : shortPulseMs;

  int symbolPeriodMs(int bit) => pulseDurationMs(bit) + gapMs;

  int decodePulseDuration(double durationMs) =>
      durationMs >= (shortPulseMs + longPulseMs) / 2 ? 1 : 0;

  List<int> bytesToBits(Uint8List data) {
    final bits = <int>[...preamble];
    for (final byte in data) {
      for (var i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    return bits;
  }

  Uint8List bitsToBytes(List<int> bits, {int? expectedLength}) {
    final start = _findPreamble(bits);
    if (start < 0) return Uint8List(0);
    final payload = bits.sublist(start + preamble.length);
    final len = expectedLength ?? payload.length ~/ 8;
    if (len <= 0) return Uint8List(0);
    final result = Uint8List(len);
    for (var b = 0; b < len; b++) {
      var value = 0;
      for (var i = 0; i < 8; i++) {
        final idx = b * 8 + i;
        if (idx < payload.length) value = (value << 1) | payload[idx];
      }
      result[b] = value;
    }
    return result;
  }

  /// Extract exact [byteCount] bytes after preamble, or empty if not enough bits.
  Uint8List extractWireBytes(List<int> bits, int byteCount) {
    final start = _findPreamble(bits);
    if (start < 0) return Uint8List(0);
    final dataStart = start + preamble.length;
    if (bits.length < dataStart + byteCount * 8) return Uint8List(0);
    final result = Uint8List(byteCount);
    for (var b = 0; b < byteCount; b++) {
      var value = 0;
      for (var i = 0; i < 8; i++) {
        value = (value << 1) | bits[dataStart + b * 8 + i];
      }
      result[b] = value;
    }
    return result;
  }

  int findPreambleIndex(List<int> bits) => _findPreamble(bits);

  int _findPreamble(List<int> bits) {
    for (var i = 0; i <= bits.length - preamble.length; i++) {
      var match = true;
      for (var j = 0; j < preamble.length; j++) {
        if (bits[i + j] != preamble[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  bool isVibrationActive(double magnitude, {double? baseline}) {
    if (baseline != null) {
      return (magnitude - baseline).abs() >= relativeThreshold;
    }
    return magnitude >= detectionThreshold;
  }
}
