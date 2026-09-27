import 'dart:async';
import 'dart:math' as math;

import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_bitmap.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/qr_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/optical_modem.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/qr_decode_isolate_pool.dart';
import 'package:adaptive_physical_communication/core/physical/qr_decode_worker.dart';
import 'package:adaptive_physical_communication/core/physical/qr_gray_frame.dart';
import 'package:adaptive_physical_communication/core/platform/optical_display_control.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:qr/qr.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Why the last fountain stream ended.
enum FountainTxEnd { none, stopped, safetyCap }

/// Fountain-coded animated QR modem (DECIMEN-style, pure Dart LT).
///
/// The stream is rateless in both directions: the sender mints an endless
/// series of brand-new symbols and never repeats one, and the receiver
/// finishes as soon as it has gathered roughly K of them. A slow or
/// intermittent camera therefore costs time, never correctness.
///
/// There is no back-channel, so the sender streams until the user stops it.
/// The session id is derived from the content: sending the same file again
/// resumes the same session with fresh symbols, and a receiver that already
/// holds part of it simply carries on.
class FountainQrModem implements OpticalModem {
  FountainQrModem({
    StructuredLogger? logger,
    OpticalMetricsNotifier? metricsNotifier,
    OpticalTxProfile? profile,
    QrDecodeIsolatePool? decodePool,
    QrDecodeWorker? decodeWorker,
  })  : _logger = logger ?? StructuredLogger(),
        metricsNotifier = metricsNotifier ?? OpticalMetricsNotifier(),
        profile = profile ?? OpticalTxProfile.auto,
        _pool = decodePool ?? QrDecodeIsolatePool(),
        _worker = decodeWorker ?? QrDecodeWorker();

  final StructuredLogger _logger;
  final OpticalMetricsNotifier metricsNotifier;
  final QrDecodeIsolatePool _pool;
  final QrDecodeWorker _worker;

  OpticalTxProfile profile;

  /// Fixed mask keeps per-frame encoding at a few milliseconds. Searching all
  /// eight costs ~40 ms on a dense code, which would stutter the display, and
  /// fountain payloads are random enough that the masks score alike.
  static const _txMaskPattern = 0;

  /// Upper bound on one stream, so a forgotten phone does not glow all day.
  static const maxStreamDuration = Duration(minutes: 10);

  /// Partial sessions kept on the receiver, so a stray frame from another
  /// sender (or a re-send at a different density) does not wipe progress.
  static const _maxRxSessions = 3;

  bool _receiverActive = false;
  bool _txActive = false;
  final _decoders = <int, LtDecoder>{};
  int? _sessionId;
  int? _lastDeliveredCrc;
  final _envelopeBuffer = <Uint8List>[];
  final _completedSessions = <int>{};
  final _txResumeIndex = <int, int>{};

  FountainTxEnd lastTxEnd = FountainTxEnd.none;
  int lastTxFrames = 0;
  Duration lastTxDuration = Duration.zero;

  LtDecoder? get _decoder => _sessionId == null ? null : _decoders[_sessionId];

  DateTime? _sessionStartedAt;
  int _captureWindow = 0;
  int _decodeWindow = 0;
  DateTime? _windowStartedAt;
  double _captureFps = 0;
  double _decodeFps = 0;
  int _payloadBytesAccum = 0;
  int _staleSeconds = 0;
  bool _lastComplete = false;
  Timer? _metricsTimer;

  static const maxEnvelopeBytes = 8 * 1024 * 1024; // 8 MB soft

  @override
  String get id => 'fountain_qr';

  @override
  String get label => 'Fountain QR';

  @override
  int get maxPayloadBytes => maxEnvelopeBytes;

  @override
  OpticalTransferMetrics get metrics => metricsNotifier.metrics;

  @override
  Future<void> startReceiver() async {
    // Partial decoders survive a restart (screen re-entered, camera
    // re-initialised): re-aiming at a sender that is still streaming picks up
    // where the last attempt stopped. Only an explicit clear drops them.
    _receiverActive = true;
    _pool.resetStats();
    _worker.resetStats();
    if (_decoder == null) _sessionStartedAt = null;
    _captureWindow = 0;
    _decodeWindow = 0;
    _staleSeconds = 0;
    _lastComplete = false;
    _windowStartedAt = DateTime.now();
    metricsNotifier.reset();
    if (_decoder != null) _publishMetrics();
    await _worker.start();
    // A long capture must not be cut short by the screen dimming.
    if (!kIsWeb) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    _metricsTimer?.cancel();
    // Keeps the HUD alive even while nothing decodes, so the user gets the
    // "no lock" hint instead of a frozen readout.
    _metricsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refreshFpsWindow(force: true),
    );
  }

  @override
  Future<void> stopReceiver() async {
    _receiverActive = false;
    _metricsTimer?.cancel();
    _metricsTimer = null;
    if (!kIsWeb && !_txActive) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  @override
  void onCameraFrame(Object image) {
    if (!_receiverActive || image is! CameraImage) return;
    _noteCapture();
    // Skip the copy entirely when the decoder is still chewing on the last
    // frame — the next symbol is just as useful as this one.
    if (_worker.isBusy) return;
    final frame = extractQrGrayFrame(image, targetPx: profile.decodeTargetPx);
    if (frame == null) return;
    unawaited(_handleGrayFrame(frame));
  }

  @override
  void onWebSampleTick() {
    if (!_receiverActive) return;
    _noteCapture();
    unawaited(_handleDecodeFuture(_pool.submitWebPreview()));
  }

  Future<void> _handleGrayFrame(QrGrayFrame frame) async {
    final bytes = await _worker.decode(frame);
    if (bytes == null || !_receiverActive) return;
    _decodeWindow++;
    final parsed = qrFountainFrameCodec.decodeFromQrBytes(bytes);
    if (parsed != null) _ingestFrame(parsed);
  }

  Future<void> _handleDecodeFuture(Future<String?> future) async {
    final text = await future;
    if (text == null || !_receiverActive) return;
    _decodeWindow++;
    _ingestQrText(text);
  }

  void _noteCapture() {
    _captureWindow++;
    _refreshFpsWindow();
  }

  void _refreshFpsWindow({bool force = false}) {
    final now = DateTime.now();
    _windowStartedAt ??= now;
    final elapsed = now.difference(_windowStartedAt!).inMilliseconds;
    if (elapsed < 1000 && !force) return;
    if (elapsed < 400) return;
    _captureFps = _captureWindow * 1000 / elapsed;
    _decodeFps = _decodeWindow * 1000 / elapsed;
    if (_decodeWindow == 0 && _captureWindow > 0) {
      _staleSeconds++;
    } else {
      _staleSeconds = 0;
    }
    _captureWindow = 0;
    _decodeWindow = 0;
    _windowStartedAt = now;
    _publishMetrics(complete: _lastComplete);
  }

  void _ingestQrText(String text) {
    final frame = qrFountainFrameCodec.decodeFromQrString(text);
    if (frame == null) return;
    _ingestFrame(frame);
  }

  void _ingestFrame(QrFountainFrame frame) {
    // The sender keeps streaming after we finish; ignore its tail.
    if (_completedSessions.contains(frame.sessionId)) return;

    var dec = _decoders[frame.sessionId];
    if (dec == null ||
        dec.K != frame.k ||
        dec.blockLen != frame.blockLen ||
        dec.fileLen != frame.fileLen) {
      dec = LtDecoder(
        K: frame.k,
        blockLen: frame.blockLen,
        fileLen: frame.fileLen,
        sessionId: frame.sessionId,
      );
      _decoders.remove(frame.sessionId);
      _decoders[frame.sessionId] = dec;
      while (_decoders.length > _maxRxSessions) {
        _decoders.remove(_decoders.keys.first);
      }
      _sessionStartedAt = DateTime.now();
      _payloadBytesAccum = 0;
      _logger.info(
        'Fountain QR lock session=${frame.sessionId.toRadixString(16)} '
        'K=${frame.k} block=${frame.blockLen} file=${frame.fileLen}',
      );
    }
    if (_sessionId != frame.sessionId) {
      _sessionId = frame.sessionId;
      _lastComplete = false;
      _sessionStartedAt ??= DateTime.now();
    }

    final useful = dec.addSymbol(frame.symbolIndex, frame.payload);
    if (useful) {
      _payloadBytesAccum += frame.blockLen;
      _publishMetrics();
    }

    if (!dec.isComplete) return;
    final recovered = dec.takeBytes();
    if (recovered == null) return;

    if (!ChatPayloadCodec.isApcmEnvelope(recovered)) {
      _logger.warning('Fountain recovered ${recovered.length} B but not APCM');
      return;
    }
    final crc = computeCrc32(recovered);
    _completedSessions.add(frame.sessionId);
    final duplicate = _lastDeliveredCrc == crc;
    if (!duplicate) {
      _lastDeliveredCrc = crc;
      _envelopeBuffer.add(recovered);
    }
    opticalTransmitterState.setConfidence(1.0);
    _lastComplete = true;
    _publishMetrics(complete: true, payloadBytes: recovered.length);
    _logger.info(
      'Fountain QR complete ${recovered.length} B in '
      '${metrics.elapsedSec.toStringAsFixed(1)}s '
      '(${metrics.goodputKBps.toStringAsFixed(1)} KB/s)'
      '${duplicate ? ' — already delivered' : ''}',
    );
    _decoders.remove(frame.sessionId);
    _sessionId = null;
  }

  void _publishMetrics({bool complete = false, int? payloadBytes}) {
    final dec = _decoder;
    final elapsed = _sessionStartedAt == null
        ? 0.0
        : DateTime.now().difference(_sessionStartedAt!).inMilliseconds / 1000.0;
    final goodput =
        elapsed > 0.05 ? (_payloadBytesAccum / 1000.0) / elapsed : 0.0;
    final sid = _sessionId;
    metricsNotifier.update(
      OpticalTransferMetrics(
        captureFps: _captureFps,
        decodeFps: _decodeFps,
        dropped: _worker.dropped + _pool.dropped,
        goodputKBps: complete
            ? (payloadBytes != null && elapsed > 0
                ? (payloadBytes / 1000.0) / elapsed
                : goodput)
            : goodput,
        elapsedSec: elapsed,
        framesNew: dec?.newSymbols ?? 0,
        framesDup: dec?.duplicateSymbols ?? 0,
        framesRed: dec?.redundantSymbols ?? 0,
        sessionId: sid?.toRadixString(16).padLeft(4, '0'),
        blockLen: dec?.blockLen ?? profile.blockLen,
        payloadBytes: payloadBytes ?? (dec?.fileLen ?? 0),
        symbolsCollected: dec?.rank ?? 0,
        symbolsNeeded: dec?.K ?? 0,
        locked: sid != null,
        complete: complete,
        stalled: !complete && _captureFps > 2 && _staleSeconds >= 4,
        profileLabel: dec != null ? 'K=${dec.K}' : profile.label,
      ),
    );
    if (dec != null && dec.K > 0) {
      opticalTransmitterState.setConfidence(dec.progress);
    }
  }

  @override
  Future<void> transmit(Uint8List envelope) async {
    if (envelope.length > maxEnvelopeBytes) {
      throw ArgumentError(
        'Payload too large for fountain QR (${envelope.length} B)',
      );
    }

    final tx = profile.resolveFor(envelope.length);
    final sessionId = sessionIdFor(envelope, tx.blockLen);
    final enc = LtEncoder(
      data: envelope,
      blockLen: tx.blockLen,
      sessionId: sessionId,
    );

    final frameMs = math.max(40, (1000 / tx.txFps).round());
    final maxMs = maxStreamDuration.inMilliseconds;

    _txActive = true;
    lastTxEnd = FountainTxEnd.none;
    opticalTransmitterState.setTransmitting(true);
    opticalTransmitterState.setFountainSession(
      sessionId: sessionId.toRadixString(16),
      k: enc.K,
      blockLen: enc.blockLen,
      fileLen: enc.fileLen,
      profileLabel: tx.label,
    );

    QrBitmap buildSymbol(int symbolIndex) => buildQrBitmap(
          qrFountainFrameCodec.encode(
            QrFountainFrame(
              sessionId: sessionId,
              symbolIndex: symbolIndex,
              k: enc.K,
              blockLen: enc.blockLen,
              fileLen: enc.fileLen,
              payload: enc.symbolAt(symbolIndex),
            ),
          ),
          errorCorrectLevel: QrErrorCorrectLevel.L,
          maskPattern: _txMaskPattern,
        );

    if (!kIsWeb) await WakelockPlus.enable();
    await OpticalDisplayControl.setMaxBrightness();
    // A re-send of the same content continues after the last symbol shown,
    // so a receiver holding part of the session only ever sees new symbols.
    final firstIndex = _txResumeIndex[sessionId] ?? 0;
    var symbolIndex = firstIndex;
    final elapsed = Stopwatch()..start();
    try {
      var next = buildSymbol(symbolIndex);
      while (_txActive &&
          opticalTransmitterState.transmitting &&
          elapsed.elapsedMilliseconds < maxMs) {
        final shownAt = elapsed.elapsedMilliseconds;
        opticalTransmitterState.setFountainQrBitmap(
          bitmap: next,
          index: symbolIndex + 1,
          total: enc.K,
        );

        // Encode the following symbol while this one is on screen, so the
        // display cadence stays even.
        symbolIndex++;
        next = buildSymbol(symbolIndex);

        // Linger on the very first frame to let the receiver autofocus.
        final hold = symbolIndex == firstIndex + 1 ? frameMs + 250 : frameMs;
        final remaining = hold - (elapsed.elapsedMilliseconds - shownAt);
        if (remaining > 0) {
          await Future<void>.delayed(Duration(milliseconds: remaining));
        }
      }
    } finally {
      elapsed.stop();
      lastTxEnd = elapsed.elapsedMilliseconds >= maxMs
          ? FountainTxEnd.safetyCap
          : FountainTxEnd.stopped;
      lastTxFrames = symbolIndex - firstIndex;
      lastTxDuration = elapsed.elapsed;
      _txResumeIndex.remove(sessionId);
      _txResumeIndex[sessionId] = symbolIndex;
      while (_txResumeIndex.length > 16) {
        _txResumeIndex.remove(_txResumeIndex.keys.first);
      }
      _txActive = false;
      opticalTransmitterState.setTransmitting(false);
      opticalTransmitterState.clearFountain();
      await OpticalDisplayControl.restoreBrightness();
      if (!kIsWeb && !_receiverActive) {
        try {
          await WakelockPlus.disable();
        } catch (_) {}
      }
    }

    _logger.info(
      'Fountain QR TX ${lastTxEnd.name} session=${sessionId.toRadixString(16)} '
      '${envelope.length} B K=${enc.K} block=${enc.blockLen} '
      'frames=$lastTxFrames in ${lastTxDuration.inSeconds}s @ ${tx.label}',
    );
  }

  /// Session id derived from the content and density, so re-sending the same
  /// file resumes the session a receiver may already be halfway through.
  static int sessionIdFor(Uint8List envelope, int blockLen) {
    final id = (computeCrc32(envelope) ^ (blockLen * 0x9E3779B1)) & 0xFFFFFFFF;
    return id == 0 ? 1 : id;
  }

  @override
  void cancelTransmit() {
    _txActive = false;
    opticalTransmitterState.setTransmitting(false);
  }

  @override
  void clearReceiveCaches({bool resetDedup = false}) {
    // Called after every delivered envelope too; partial sessions stay.
    _envelopeBuffer.clear();
    if (resetDedup) {
      _decoders.clear();
      _sessionId = null;
      _sessionStartedAt = null;
      _payloadBytesAccum = 0;
      _lastDeliveredCrc = null;
      _completedSessions.clear();
      _lastComplete = false;
      _pool.resetStats();
      _worker.resetStats();
      opticalTransmitterState.resetScanFeedback();
      metricsNotifier.reset();
    }
  }

  @override
  List<Uint8List> takeEnvelopes() {
    final batch = List<Uint8List>.from(_envelopeBuffer);
    _envelopeBuffer.clear();
    return batch;
  }

  /// Progress for legacy UI: independent symbols held / K.
  (int received, int total)? get chunkProgress {
    final dec = _decoder;
    if (dec == null) return null;
    return (dec.rank, dec.K);
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _worker.dispose();
    metricsNotifier.dispose();
  }
}
