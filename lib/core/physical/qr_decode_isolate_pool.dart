import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'package:adaptive_physical_communication/core/channels/optical_web_qr_decoder.dart';
import 'package:adaptive_physical_communication/core/physical/qr_frame_decoder.dart';

/// Shared QR decode pool — drops frames when busy (fountain absorbs loss).
class QrDecodeIsolatePool {
  QrDecodeIsolatePool({this.maxInFlight = 2});

  final int maxInFlight;
  int _inFlight = 0;
  int dropped = 0;
  int decoded = 0;
  int captureTicks = 0;

  bool get isBusy => _inFlight >= maxInFlight;

  /// Copy pixels sync, then decode. Returns QR text (FQR1:… ASCII).
  Future<String?> submitCameraImage(CameraImage image) async {
    captureTicks++;
    if (isBusy) {
      dropped++;
      return null;
    }

    // CRITICAL: copy before yielding — camera recycles the buffer.
    final pixels = extractQrFramePixels(image);
    if (pixels == null) {
      dropped++;
      return null;
    }

    _inFlight++;
    try {
      await Future<void>.delayed(Duration.zero);
      final text = decodeQrTextFromPixels(pixels);
      if (text != null && text.isNotEmpty) {
        decoded++;
        return text;
      }
      // Binary fallback via raw bytes → UTF-8 string if ASCII FQR1
      final bytes = decodeQrBytesFromPixels(pixels);
      if (bytes != null && bytes.isNotEmpty) {
        decoded++;
        return String.fromCharCodes(bytes);
      }
      return null;
    } catch (_) {
      dropped++;
      return null;
    } finally {
      _inFlight--;
    }
  }

  /// Also expose bytes path for the modem.
  Future<Uint8List?> submitCameraImageBytes(CameraImage image) async {
    captureTicks++;
    if (isBusy) {
      dropped++;
      return null;
    }
    final pixels = extractQrFramePixels(image);
    if (pixels == null) {
      dropped++;
      return null;
    }
    _inFlight++;
    try {
      await Future<void>.delayed(Duration.zero);
      final bytes = decodeQrBytesFromPixels(pixels);
      if (bytes != null) {
        decoded++;
        return bytes;
      }
      final text = decodeQrTextFromPixels(pixels);
      if (text != null && text.isNotEmpty) {
        decoded++;
        return Uint8List.fromList(text.codeUnits);
      }
      return null;
    } catch (_) {
      dropped++;
      return null;
    } finally {
      _inFlight--;
    }
  }

  Future<String?> submitWebPreview() async {
    captureTicks++;
    if (isBusy) {
      dropped++;
      return null;
    }
    _inFlight++;
    try {
      await Future<void>.delayed(Duration.zero);
      final text = sampleOpticalQrFromPreview();
      if (text != null) decoded++;
      return text;
    } catch (_) {
      dropped++;
      return null;
    } finally {
      _inFlight--;
    }
  }

  void resetStats() {
    dropped = 0;
    decoded = 0;
    captureTicks = 0;
  }
}
