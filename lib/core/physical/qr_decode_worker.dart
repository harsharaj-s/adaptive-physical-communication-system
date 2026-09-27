import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:adaptive_physical_communication/core/physical/qr_frame_decoder.dart';
import 'package:adaptive_physical_communication/core/physical/qr_gray_frame.dart';

/// Long-lived background isolate that turns luminance frames into QR bytes.
///
/// One decode is in flight at a time; newer frames arriving while busy are
/// dropped. That is the right trade for a fountain stream — the next symbol is
/// just as useful as this one, so latency matters more than completeness.
class QrDecodeWorker {
  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  Completer<Uint8List?>? _pending;
  bool _starting = false;
  bool _disposed = false;

  int submitted = 0;
  int decoded = 0;
  int dropped = 0;

  bool get isBusy => _pending != null;
  bool get isReady => _toIsolate != null;

  Future<void> start() async {
    if (_disposed || _starting || _toIsolate != null) return;
    if (kIsWeb) return; // No isolates on web; callers fall back inline.
    _starting = true;
    try {
      final handshake = ReceivePort();
      _isolate = await Isolate.spawn(
        _decodeIsolateEntry,
        handshake.sendPort,
        debugName: 'qr-decode',
      );
      final ready = ReceivePort();
      _fromIsolate = ready;
      _toIsolate = await handshake.first as SendPort;
      handshake.close();
      _toIsolate!.send(ready.sendPort);
      ready.listen(_onIsolateMessage);
    } catch (e) {
      debugPrint('QR decode isolate unavailable, decoding inline: $e');
      _toIsolate = null;
    } finally {
      _starting = false;
    }
  }

  void _onIsolateMessage(dynamic message) {
    final pending = _pending;
    _pending = null;
    if (pending == null || pending.isCompleted) return;
    pending.complete(message is Uint8List ? message : null);
  }

  /// Decode [frame], or return null immediately if a decode is already running.
  Future<Uint8List?> decode(QrGrayFrame frame) async {
    if (_disposed) return null;
    submitted++;
    if (_pending != null) {
      dropped++;
      return null;
    }

    final port = _toIsolate;
    if (port == null) {
      // Inline fallback (web, or isolate spawn failed). Yield first so the
      // camera callback is never blocked by a decode.
      _pending = Completer<Uint8List?>();
      try {
        await Future<void>.delayed(Duration.zero);
        final bytes = decodeQrBytesFromLuminance(
          frame.width,
          frame.height,
          frame.lum,
        );
        if (bytes != null) decoded++;
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _pending = null;
      }
    }

    final completer = Completer<Uint8List?>();
    _pending = completer;
    try {
      port.send([
        frame.width,
        frame.height,
        TransferableTypedData.fromList([frame.lum]),
      ]);
    } catch (_) {
      _pending = null;
      return null;
    }

    // A reply that never arrives would wedge the receiver permanently, since
    // every later frame is dropped while one is in flight.
    final bytes = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        if (_pending == completer) _pending = null;
        return null;
      },
    );
    if (bytes != null) decoded++;
    return bytes;
  }

  void resetStats() {
    submitted = 0;
    decoded = 0;
    dropped = 0;
  }

  void dispose() {
    _disposed = true;
    _pending?.complete(null);
    _pending = null;
    _fromIsolate?.close();
    _fromIsolate = null;
    _toIsolate = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

void _decodeIsolateEntry(SendPort handshake) {
  final commands = ReceivePort();
  handshake.send(commands.sendPort);

  SendPort? replyTo;
  commands.listen((dynamic message) {
    if (message is SendPort) {
      replyTo = message;
      return;
    }
    if (message is! List || message.length != 3) return;
    final reply = replyTo;
    if (reply == null) return;

    // Always answer, whatever happens — the caller drops every frame until it
    // hears back.
    Uint8List? bytes;
    try {
      final width = message[0] as int;
      final height = message[1] as int;
      final lum =
          (message[2] as TransferableTypedData).materialize().asInt8List();
      bytes = decodeQrBytesFromLuminance(width, height, lum);
    } catch (_) {
      bytes = null;
    }
    reply.send(bytes);
  });
}
