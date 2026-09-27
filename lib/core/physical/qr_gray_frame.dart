import 'dart:typed_data';

import 'package:camera/camera.dart';

/// 8-bit luminance frame copied out of a camera buffer.
///
/// zxing reads luminance as `byte & 0xFF`, which is exactly what [Int8List]
/// gives us, so the Y plane can be handed over with no per-pixel maths.
class QrGrayFrame {
  const QrGrayFrame({
    required this.width,
    required this.height,
    required this.lum,
  });

  final int width;
  final int height;
  final Int8List lum;

  int get pixelCount => width * height;
}

/// Copy the centre square of a camera frame as luminance.
///
/// Must run synchronously inside the camera callback — the plugin recycles the
/// plane buffers as soon as it returns.
///
/// On Android (`yuv420`) plane 0 *is* the luminance channel, so this is a
/// strided memcpy. BGRA sources (iOS/web) fall back to a green-weighted
/// average. A square crop is used because the QR is square and centred, which
/// discards ~40% of a 16:9 frame for free.
QrGrayFrame? extractQrGrayFrame(
  CameraImage image, {
  double cropFraction = 0.98,
  int targetPx = 720,
}) {
  final srcW = image.width;
  final srcH = image.height;
  if (srcW < 16 || srcH < 16) return null;
  if (image.planes.isEmpty) return null;

  final shortSide = srcW < srcH ? srcW : srcH;
  final cropSide = (shortSide * cropFraction).round().clamp(16, shortSide);
  final left = (srcW - cropSide) ~/ 2;
  final top = (srcH - cropSide) ~/ 2;

  final step = (cropSide / targetPx).round().clamp(1, 8);
  final outSide = cropSide ~/ step;
  if (outSide < 16) return null;

  final plane = image.planes.first;
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;
  final pixelStride = plane.bytesPerPixel ?? 1;
  final lum = Int8List(outSide * outSide);

  if (pixelStride >= 3) {
    // BGRA / RGBA: green-favouring average, matching zxing's own weighting.
    for (var y = 0; y < outSide; y++) {
      final srcRow = (top + y * step) * rowStride;
      final outRow = y * outSide;
      for (var x = 0; x < outSide; x++) {
        final i = srcRow + (left + x * step) * pixelStride;
        if (i + 2 >= bytes.length) continue;
        final b = bytes[i];
        final g2 = bytes[i + 1] << 1;
        final r = bytes[i + 2];
        lum[outRow + x] = (r + g2 + b) >> 2;
      }
    }
    return QrGrayFrame(width: outSide, height: outSide, lum: lum);
  }

  for (var y = 0; y < outSide; y++) {
    final srcRow = (top + y * step) * rowStride + left * pixelStride;
    final outRow = y * outSide;
    if (step == 1 && pixelStride == 1) {
      if (srcRow + outSide > bytes.length) break;
      // Same element size, so this is a memmove that preserves the raw bits.
      lum.setRange(outRow, outRow + outSide, bytes, srcRow);
      continue;
    }
    for (var x = 0; x < outSide; x++) {
      final i = srcRow + x * step * pixelStride;
      if (i >= bytes.length) break;
      lum[outRow + x] = bytes[i];
    }
  }

  return QrGrayFrame(width: outSide, height: outSide, lum: lum);
}
