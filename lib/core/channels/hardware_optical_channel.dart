import 'dart:async';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/physical/csk/csk_optical_modem.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/fountain_qr_modem.dart';
import 'package:adaptive_physical_communication/core/physical/optical_modem.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

/// Which optical modem the Light channel uses.
enum OpticalModemKind { fountainQr, csk }

/// Hardware optical channel — thin shell over pluggable [OpticalModem]s.
class HardwareOpticalChannel implements CommChannel {
  HardwareOpticalChannel({
    StructuredLogger? logger,
    OpticalModemKind defaultModem = OpticalModemKind.fountainQr,
    OpticalTxProfile? profile,
  })  : _logger = logger ?? StructuredLogger(),
        _kind = defaultModem {
    _fountain = FountainQrModem(
      logger: _logger,
      profile: profile ?? OpticalTxProfile.auto,
    );
    _csk = CskOpticalModem(logger: _logger);
    _active = _kind == OpticalModemKind.fountainQr ? _fountain : _csk;
    opticalTransmitterState.setModemId(_active.id);
  }

  final StructuredLogger _logger;
  late final FountainQrModem _fountain;
  late final CskOpticalModem _csk;
  late OpticalModem _active;
  OpticalModemKind _kind;

  final _receiveBuffer = <DecodedPacket>[];
  CameraController? _camera;
  Timer? _webSampleTimer;
  bool _webSampling = false;
  bool _running = false;
  bool _receiverActive = false;
  bool _cameraInitialized = false;
  int _packetsSent = 0;
  int _packetsReceived = 0;

  OpticalModem get activeModem => _active;
  FountainQrModem get fountainModem => _fountain;
  CskOpticalModem get cskModem => _csk;
  OpticalModemKind get modemKind => _kind;

  OpticalMetricsNotifier get metricsNotifier =>
      _kind == OpticalModemKind.fountainQr
          ? _fountain.metricsNotifier
          : _csk.metricsNotifier;

  void selectModem(OpticalModemKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    _active = kind == OpticalModemKind.fountainQr ? _fountain : _csk;
    opticalTransmitterState.setModemId(_active.id);
  }

  void setTxProfile(OpticalTxProfile profile) {
    _fountain.profile = profile;
  }

  (int received, int total)? get chunkProgress =>
      _kind == OpticalModemKind.fountainQr
          ? _fountain.chunkProgress
          : _csk.chunkProgress;

  @override
  CommChannelId get id => CommChannelId.optical;

  @override
  ChannelCapabilities get capabilities => const ChannelCapabilities(
        channelId: CommChannelId.optical,
        name: 'Optical (Hardware)',
        maxThroughput: 200000,
        minLatency: 50,
        supportsBinary: true,
        hardwareImplemented: true,
      );

  @override
  Future<void> initialize({bool setupCamera = true}) async {
    if (!isPhysicalChannelSupported) return;
    if (setupCamera && !_cameraInitialized) {
      if (!kIsWeb) {
        final camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) {
          _logger.warning('Camera permission denied');
          return;
        }
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _logger.warning('No camera found');
        return;
      }
      final cameraDesc = kIsWeb
          ? cameras.first
          : cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            );
      _camera = CameraController(
        cameraDesc,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            kIsWeb ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await _camera!.initialize();
      try {
        await _camera!.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await _camera!.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      if (!kIsWeb) await _tuneCameraForScreens();
      _cameraInitialized = true;
      _logger.info(
        'Optical camera ready (${cameraDesc.lensDirection.name}, '
        'zoom ${_zoom.toStringAsFixed(1)}x of '
        '${_minZoom.toStringAsFixed(1)}-${_maxZoom.toStringAsFixed(1)})',
      );
    }
  }

  /// Default receive zoom. Camera zoom crops the full sensor, so the QR gets
  /// real extra pixels, and it lets the receiver stand back to 15-25 cm, where
  /// every phone can focus (many cannot focus at 8-10 cm).
  static const defaultReceiveZoom = 1.5;

  /// A bright screen makes auto-exposure pick long exposures that blur the
  /// swap between QR frames and bloom the white modules; a slight negative
  /// offset keeps edges crisp. Sharpness dominated the simulated decode rate.
  static const receiveExposureOffsetEv = -0.7;

  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;

  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get zoom => _zoom;

  Future<void> _tuneCameraForScreens() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      _minZoom = await camera.getMinZoomLevel();
      _maxZoom = await camera.getMaxZoomLevel();
    } catch (_) {
      _minZoom = 1;
      _maxZoom = 1;
    }
    await setZoom(defaultReceiveZoom);
    await focusAt(const Offset(0.5, 0.5));
    try {
      final lo = await camera.getMinExposureOffset();
      final hi = await camera.getMaxExposureOffset();
      if (lo < 0 && hi > lo) {
        await camera.setExposureOffset(
          receiveExposureOffsetEv.clamp(lo, hi).toDouble(),
        );
      }
    } catch (_) {}
  }

  /// Set the receive zoom, clamped to what the camera supports.
  Future<double> setZoom(double level) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return _zoom;
    final z = level.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await camera.setZoomLevel(z);
      _zoom = z;
    } catch (_) {}
    return _zoom;
  }

  /// Re-run autofocus and metering at [point] (0..1 in preview coordinates).
  Future<void> focusAt(Offset point) async {
    final camera = _camera;
    if (camera == null) return;
    try {
      if (camera.value.focusPointSupported) await camera.setFocusPoint(point);
    } catch (_) {}
    try {
      if (camera.value.exposurePointSupported) {
        await camera.setExposurePoint(point);
      }
    } catch (_) {}
  }

  bool get receiverReady =>
      _receiverActive && (_cameraInitialized || _webSampling);

  bool get isCameraStreaming =>
      (_camera?.value.isStreamingImages ?? false) || _webSampling;

  @override
  Future<void> start({bool enableReceiver = true}) async {
    if (!isPhysicalChannelSupported) return;
    if (_running && _receiverActive == enableReceiver) return;
    _running = true;
    if (!enableReceiver) {
      _receiverActive = false;
      await _active.stopReceiver();
      await _stopOpticalReceiverSampling();
      return;
    }
    _receiverActive = true;
    await _active.startReceiver();

    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      _logger.warning('Optical RX unavailable — camera not initialized');
      return;
    }

    await _stopOpticalReceiverSampling();

    if (camera.supportsImageStreaming()) {
      if (!camera.value.isStreamingImages) {
        await camera.startImageStream(_processCameraFrame);
      }
      return;
    }

    if (kIsWeb) {
      _webSampling = true;
      _webSampleTimer = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) {
          if (!_running || !_receiverActive) return;
          _active.onWebSampleTick();
        },
      );
      _logger.info('Optical web sampling started (${_active.id})');
      return;
    }

    _logger.warning('Optical RX unavailable — image streaming not supported');
  }

  void _processCameraFrame(CameraImage image) {
    if (!_running || !_receiverActive) return;
    _active.onCameraFrame(image);
  }

  Future<void> transmitEnvelope(Uint8List envelope) async {
    if (!_running) throw StateError('Optical channel not running');
    if (!isPhysicalChannelSupported) {
      _logger.warning('Optical TX skipped — platform unsupported');
      return;
    }
    if (envelope.length > _active.maxPayloadBytes) {
      throw ArgumentError(
        'Message too large for ${_active.label} (${envelope.length} B, '
        'max ${_active.maxPayloadBytes} B).',
      );
    }

    await _active.transmit(envelope);
    _packetsSent++;
    _logger.info(
      'Optical ${_active.id} TX envelope ($_packetsSent, ${envelope.length} bytes)',
    );
  }

  Future<List<Uint8List>> receiveEnvelopes() async {
    final batch = _active.takeEnvelopes();
    if (batch.isNotEmpty) _packetsReceived += batch.length;
    return batch;
  }

  void clearReceiveCaches({bool resetDedup = false}) {
    _active.clearReceiveCaches(resetDedup: resetDedup);
    _receiveBuffer.clear();
  }

  Future<void> ensureReceiverStreaming() async {
    if (!_running || !_receiverActive) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (!camera.supportsImageStreaming()) return;
    if (camera.value.isStreamingImages) return;
    try {
      await camera.startImageStream(_processCameraFrame);
      _logger.info('Optical image stream restarted');
    } catch (e) {
      _logger.warning('Failed to restart optical stream: $e');
    }
  }

  Future<void> _stopOpticalReceiverSampling() async {
    _webSampleTimer?.cancel();
    _webSampleTimer = null;
    _webSampling = false;

    final camera = _camera;
    if (camera != null &&
        camera.supportsImageStreaming() &&
        camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _receiverActive = false;
    await _active.stopReceiver();
    await _stopOpticalReceiverSampling();
    _active.cancelTransmit();
    opticalTransmitterState.setTransmitting(false);
  }

  @override
  Future<bool> discover(int timeoutMs) async {
    if (!isPhysicalChannelSupported || !_receiverActive) return false;
    final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      if (_receiveBuffer.isNotEmpty || _active.metrics.locked) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  @override
  Future<ChannelTestResult> test(int testPacketCount) async {
    final m = _active.metrics;
    final received = m.locked ? testPacketCount : 0;
    return ChannelTestResult(
      channel: id,
      packetsSent: testPacketCount,
      packetsReceived: received,
      packetLossRate: (testPacketCount - received) / testPacketCount,
      throughput: m.goodputKBps * 1000,
      latency: 50,
      confidence: opticalTransmitterState.confidence,
      stability: 0.75,
    );
  }

  @override
  Future<void> transmit(Uint8List packet) async {
    if (!_running) throw StateError('Optical channel not running');
    if (!isPhysicalChannelSupported) {
      _logger.warning('Optical TX skipped — platform unsupported');
      return;
    }
    await _active.transmit(packet);
    _packetsSent++;
  }

  @override
  Future<List<DecodedPacket>> receive() async {
    final batch = List<DecodedPacket>.from(_receiveBuffer);
    _receiveBuffer.clear();
    return batch;
  }

  @override
  ChannelMetrics getMetrics() {
    final m = _active.metrics;
    final loss = _packetsSent > 0
        ? (_packetsSent - _packetsReceived) / _packetsSent
        : 0.05;
    return ChannelMetrics(
      throughput: m.goodputKBps > 0 ? m.goodputKBps * 1000 : 50000 * (1 - loss),
      packetLoss: loss.clamp(0, 1),
      latency: 50,
      reliability: (1 - loss).clamp(0, 1),
      errorRate: loss * 0.5,
      confidence: opticalTransmitterState.confidence,
      stability: 0.8,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  bool isAvailable() => _running && isPhysicalChannelSupported;

  @override
  void setTransmissionConfig(TransmissionConfig config) {}

  CameraController? get cameraController => _camera;

  Future<void> dispose() async {
    await stop();
    _fountain.dispose();
    _csk.dispose();
    await _camera?.dispose();
    _camera = null;
  }
}
