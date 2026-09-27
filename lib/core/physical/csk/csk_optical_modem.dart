import 'dart:async';

import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/physical/optical_csk_codec.dart';
import 'package:adaptive_physical_communication/core/physical/optical_csk_sampler.dart';
import 'package:adaptive_physical_communication/core/physical/optical_modem.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:adaptive_physical_communication/core/channels/optical_web_sampler.dart';

/// Existing Color Shift Keying modem — extracted, behavior preserved.
class CskOpticalModem implements OpticalModem {
  CskOpticalModem({
    StructuredLogger? logger,
    OpticalMetricsNotifier? metricsNotifier,
  })  : _logger = logger ?? StructuredLogger(),
        metricsNotifier = metricsNotifier ?? OpticalMetricsNotifier();

  final StructuredLogger _logger;
  final OpticalMetricsNotifier metricsNotifier;
  final _cskDecoder = OpticalCskDecoder();
  final _envelopeBuffer = <Uint8List>[];
  int? _lastDeliveredEnvelopeCrc;
  int? _lastCskSampleMs;
  int _cskBytesSeen = 0;
  bool _receiverActive = false;
  DateTime? _rxStartedAt;

  @override
  String get id => 'csk';

  @override
  String get label => 'Color Shift Keying';

  @override
  int get maxPayloadBytes => hardwareOpticalCskMaxBytes;

  @override
  OpticalTransferMetrics get metrics => metricsNotifier.metrics;

  @override
  Future<void> startReceiver() async {
    _receiverActive = true;
    _rxStartedAt = DateTime.now();
    _cskDecoder.reset();
    metricsNotifier.reset();
  }

  @override
  Future<void> stopReceiver() async {
    _receiverActive = false;
    _cskDecoder.reset();
  }

  @override
  void onCameraFrame(Object image) {
    if (!_receiverActive || image is! CameraImage) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastCskSampleMs != null && now - _lastCskSampleMs! < 45) return;
    _lastCskSampleMs = now;
    final cells = sampleCskCellsFromCamera(image);
    if (cells != null) _processCskCells(cells);
  }

  @override
  void onWebSampleTick() {
    if (!_receiverActive) return;
    final cells = sampleCskCellsFromPreview();
    if (cells != null) _processCskCells(cells);
  }

  void _processCskCells(List<(double, double, double)> cells) {
    final packed = opticalCskCodec.packFrame(cells);
    if (packed == null) return;
    if (packed < 0) {
      _cskDecoder.noteGuard();
      return;
    }

    _cskDecoder.addSampledByte(packed);
    _cskBytesSeen++;
    final progress = _cskDecoder.progress;
    if (progress != null && progress.$2 > 0) {
      opticalTransmitterState.setConfidence(progress.$1 / progress.$2);
      _publishProgress(progress.$1, progress.$2);
    }

    final bytes = _cskDecoder.pollEnvelope();
    if (bytes == null) return;

    _cskDecoder.reset();
    opticalTransmitterState.resetScanFeedback();

    if (ChatPayloadCodec.isApcmEnvelope(bytes)) {
      final crc = computeCrc32(bytes);
      if (_lastDeliveredEnvelopeCrc == crc) return;
      _lastDeliveredEnvelopeCrc = crc;
      _envelopeBuffer.add(bytes);
      opticalTransmitterState.setConfidence(1.0);
      metricsNotifier.update(
        metrics.copyWith(
          complete: true,
          payloadBytes: bytes.length,
          symbolsCollected: bytes.length,
          symbolsNeeded: bytes.length,
        ),
      );
      _logger.info('Optical CSK decoded envelope (${bytes.length} B)');
    } else {
      _logger.warning(
        'CSK decoded ${bytes.length} B but not a valid APCM envelope',
      );
    }
  }

  void _publishProgress(int received, int total) {
    final elapsed = _rxStartedAt == null
        ? 0.0
        : DateTime.now().difference(_rxStartedAt!).inMilliseconds / 1000.0;
    metricsNotifier.update(
      OpticalTransferMetrics(
        elapsedSec: elapsed,
        symbolsCollected: received,
        symbolsNeeded: total,
        payloadBytes: received,
        locked: received > 0,
        profileLabel: 'CSK',
        framesNew: _cskBytesSeen,
      ),
    );
  }

  @override
  Future<void> transmit(Uint8List envelope) async {
    if (envelope.length > hardwareOpticalCskMaxBytes) {
      throw ArgumentError(
        'Message too large for CSK light (${envelope.length} B). Use short text.',
      );
    }
    if (!kIsWeb) await WakelockPlus.enable();
    try {
      await _transmitCskBytes(opticalCskCodec.frameEnvelope(envelope));
    } finally {
      opticalTransmitterState.setTransmitting(false);
      if (!kIsWeb) await WakelockPlus.disable();
    }
    _logger.info('Optical CSK TX envelope (${envelope.length} bytes)');
  }

  Future<void> _transmitCskBytes(Uint8List data) async {
    opticalTransmitterState.setTransmitting(true);
    opticalTransmitterState.setCskGuard(index: 0, total: data.length);
    await Future<void>.delayed(
      const Duration(milliseconds: hardwareOpticalCskLeadMs),
    );

    for (var round = 0; round < hardwareOpticalCskRepeatCount; round++) {
      for (var i = 0; i < data.length; i++) {
        if (!opticalTransmitterState.transmitting) return;
        opticalTransmitterState.setCskSymbol(
          cells: opticalCskCodec.cellsForByte(data[i]),
          index: i + 1,
          total: data.length,
        );
        await Future<void>.delayed(
          const Duration(milliseconds: hardwareOpticalCskSymbolMs),
        );
        if (!opticalTransmitterState.transmitting) return;
        opticalTransmitterState.setCskGuard(
          index: i + 1,
          total: data.length,
        );
        await Future<void>.delayed(
          const Duration(milliseconds: hardwareOpticalCskGuardMs),
        );
      }
      if (round + 1 < hardwareOpticalCskRepeatCount) {
        await Future<void>.delayed(
          const Duration(milliseconds: hardwareOpticalCskRepeatGapMs),
        );
      }
    }
  }

  @override
  void cancelTransmit() {
    opticalTransmitterState.setTransmitting(false);
  }

  @override
  void clearReceiveCaches({bool resetDedup = false}) {
    _cskDecoder.reset();
    _lastCskSampleMs = null;
    _envelopeBuffer.clear();
    if (resetDedup) _lastDeliveredEnvelopeCrc = null;
    opticalTransmitterState.resetScanFeedback();
    metricsNotifier.reset();
  }

  @override
  List<Uint8List> takeEnvelopes() {
    final batch = List<Uint8List>.from(_envelopeBuffer);
    _envelopeBuffer.clear();
    return batch;
  }

  /// Legacy progress for UI that still reads (received, total) bytes.
  (int received, int total)? get chunkProgress => _cskDecoder.progress;

  int get bytesSeen => _cskBytesSeen;

  @override
  void dispose() {
    metricsNotifier.dispose();
  }
}
