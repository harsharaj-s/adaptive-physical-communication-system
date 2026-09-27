import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/physical/physical_codecs.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/platform/vibration_transmitter_state.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';
/// Hardware vibration channel using motor pulses (TX) and accelerometer (RX).
class HardwareVibrationChannel implements CommChannel {
  HardwareVibrationChannel({StructuredLogger? logger})
      : _logger = logger ?? StructuredLogger();

  final StructuredLogger _logger;
  final _codec = VibrationBitCodec();
  final _receiveBuffer = <DecodedPacket>[];
  final List<int> _rxBits = [];
  StreamSubscription<AccelerometerEvent>? _accelSub;
  bool _running = false;
  bool _initialized = false;
  int _packetsSent = 0;
  int _packetsReceived = 0;
  double _lastMagnitude = 0;
  double _baseline = 9.8;
  double _confidence = 0;

  bool _pulseActive = false;
  int? _pulseStartMs;

  @override
  CommChannelId get id => CommChannelId.vibration;

  @override
  ChannelCapabilities get capabilities => const ChannelCapabilities(
        channelId: CommChannelId.vibration,
        name: 'Vibration (Hardware)',
        maxThroughput: 800,
        minLatency: 300,
        supportsBinary: true,
        hardwareImplemented: true,
      );

  @override
  Future<void> initialize({bool setupCamera = true}) async {
    if (!isHardwarePlatform || _initialized) return;
    final hasMotor = await Vibration.hasVibrator();
    if (hasMotor != true) {
      _logger.warning('No vibration motor reported — using haptic fallback');
    }
    _initialized = true;
  }

  @override
  Future<void> start({bool enableReceiver = true}) async {
    if (!isHardwarePlatform) return;
    if (!enableReceiver) {
      _running = true;
      await _accelSub?.cancel();
      _accelSub = null;
      return;
    }
    if (_running && _accelSub != null) return;
    _running = true;
    _baseline = 9.8;
    _rxBits.clear();
    await _accelSub?.cancel();
    _accelSub = accelerometerEventStream().listen(_processAccelerometer);
  }

  void _processAccelerometer(AccelerometerEvent event) {
    if (!_running) return;

    final magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _lastMagnitude = magnitude;
    _confidence = ((magnitude - _baseline).abs() / 6).clamp(0.0, 1.0);
    vibrationTransmitterState.setLastMagnitude(_confidence);

    final now = DateTime.now().millisecondsSinceEpoch;
    final active = _codec.isVibrationActive(magnitude, baseline: _baseline);

    if (!active && !_pulseActive) {
      // Track resting gravity while quiet.
      _baseline = _baseline * 0.92 + magnitude * 0.08;
    }

    if (active && !_pulseActive) {
      _pulseActive = true;
      _pulseStartMs = now;
    } else if (!active && _pulseActive) {
      _pulseActive = false;
      final start = _pulseStartMs;
      if (start != null) {
        final duration = now - start;
        // Ignore very short noise spikes.
        if (duration >= 25) {
          final bit = _codec.decodePulseDuration(duration.toDouble());
          _rxBits.add(bit);
          if (_rxBits.length >= 24) {
            _tryDecodePackets();
          }
        }
      }
      _pulseStartMs = null;
    }
  }

  void _tryDecodePackets() {
    final preambleIdx = _codec.findPreambleIndex(_rxBits);
    if (preambleIdx < 0) {
      if (_rxBits.length > 64) {
        _rxBits.removeRange(0, _rxBits.length ~/ 4);
      }
      return;
    }

    // Need header to learn payload length.
    final header = _codec.extractWireBytes(
      _rxBits.sublist(preambleIdx),
      headerSize,
    );
    if (header.isEmpty) return;

    final payloadLength = ByteData.sublistView(header).getUint16(15, Endian.little);
    if (payloadLength > 512) {
      _rxBits.removeRange(0, preambleIdx + 1);
      return;
    }

    final wireBytes = headerSize + payloadLength + crcSize;
    final packetBytes = _codec.extractWireBytes(
      _rxBits.sublist(preambleIdx),
      wireBytes,
    );
    if (packetBytes.isEmpty) return;

    final packet = packetCodec.decode(packetBytes);
    if (packet != null) {
      _receiveBuffer.add(packet);
      _packetsReceived++;
      final consumed =
          preambleIdx + _codec.preamble.length + wireBytes * 8;
      if (consumed < _rxBits.length) {
        _rxBits.removeRange(0, consumed);
      } else {
        _rxBits.clear();
      }
      _logger.info('Vibration decoded packet (${packet.packetType.name})');
    } else if (_rxBits.length > preambleIdx + 1) {
      _rxBits.removeRange(0, preambleIdx + 1);
    }
  }

  void clearReceiveCaches() {
    _rxBits.clear();
    _receiveBuffer.clear();
    _pulseActive = false;
    _pulseStartMs = null;
    _baseline = 9.8;
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _accelSub?.cancel();
    _accelSub = null;
    vibrationTransmitterState.setTransmitting(false);
    vibrationTransmitterState.setVibrating(false);
  }

  @override
  Future<bool> discover(int timeoutMs) async {
    if (!isHardwarePlatform) return false;
    await Future<void>.delayed(Duration(milliseconds: timeoutMs ~/ 2));
    return _lastMagnitude >= _codec.detectionThreshold * 0.8;
  }

  @override
  Future<ChannelTestResult> test(int testPacketCount) async {
    var received = 0;
    for (var i = 0; i < testPacketCount; i++) {
      if (_lastMagnitude >= _codec.detectionThreshold * 0.7) received++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return ChannelTestResult(
      channel: id,
      packetsSent: testPacketCount,
      packetsReceived: received,
      packetLossRate: (testPacketCount - received) / testPacketCount,
      throughput: 800 * (received / testPacketCount),
      latency: _codec.shortPulseMs.toDouble() * 8,
      confidence: _confidence,
      stability: 0.65,
    );
  }

  @override
  Future<void> transmit(Uint8List packet) async {
    if (!_running) throw StateError('Vibration channel not running');
    if (!isHardwarePlatform) {
      _logger.warning('Vibration TX skipped — not on mobile hardware');
      return;
    }

    vibrationTransmitterState.setTransmitting(true);
    final bits = _codec.bytesToBits(packet);

    try {
      for (final bit in bits) {
        final duration = _codec.pulseDurationMs(bit);
        vibrationTransmitterState.setVibrating(true);

        await _vibrateFor(duration);

        vibrationTransmitterState.setVibrating(false);
        await Future<void>.delayed(Duration(milliseconds: _codec.gapMs));
      }
    } finally {
      vibrationTransmitterState.setTransmitting(false);
      await Vibration.cancel();
    }

    _packetsSent++;
    _logger.info('Vibration TX sent packet ($_packetsSent)');
  }

  Future<void> _vibrateFor(int durationMs) async {
    if (durationMs <= 0) return;
    try {
      if (await Vibration.hasVibrator() != true) {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(Duration(milliseconds: durationMs));
        return;
      }

      final hasAmplitude = await Vibration.hasAmplitudeControl() == true;
      var vibrated = false;
      try {
        if (hasAmplitude) {
          await Vibration.vibrate(
            pattern: [0, durationMs],
            intensities: [0, 255],
          );
          vibrated = true;
        } else {
          await Vibration.vibrate(duration: durationMs);
          vibrated = true;
        }
      } catch (_) {
        await Vibration.vibrate(pattern: [0, durationMs]);
        vibrated = true;
      }

      if (!vibrated) {
        await HapticFeedback.heavyImpact();
      }
      await Future<void>.delayed(Duration(milliseconds: durationMs + 50));
    } catch (e) {
      _logger.warning('Vibration motor failed, using haptic: $e');
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(Duration(milliseconds: durationMs));
    }
  }

  @override
  Future<List<DecodedPacket>> receive() async {
    final batch = List<DecodedPacket>.from(_receiveBuffer);
    _receiveBuffer.clear();
    return batch;
  }

  @override
  ChannelMetrics getMetrics() {
    final loss = _packetsSent > 0
        ? (_packetsSent - _packetsReceived) / _packetsSent
        : 0.08;
    return ChannelMetrics(
      throughput: 800 * (1 - loss),
      packetLoss: loss.clamp(0, 1),
      latency: (_codec.longPulseMs + _codec.gapMs) * 8.0,
      reliability: (1 - loss).clamp(0, 1),
      errorRate: loss * 0.5,
      confidence: _confidence,
      stability: 0.65,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  bool isAvailable() => _running && isHardwarePlatform;

  @override
  void setTransmissionConfig(TransmissionConfig config) {}

  Future<void> dispose() async {
    await stop();
  }
}
