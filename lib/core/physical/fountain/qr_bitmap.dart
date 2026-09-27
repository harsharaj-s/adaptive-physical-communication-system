import 'dart:typed_data';

import 'package:qr/qr.dart';

/// Immutable QR module grid — UI-free so it can be built off the paint path.
class QrBitmap {
  QrBitmap({
    required this.size,
    required this.modules,
    required this.typeNumber,
  });

  /// Module count per side (excludes quiet zone).
  final int size;

  /// Row-major `size * size`, 1 = dark.
  final Uint8List modules;

  /// QR version 1..40.
  final int typeNumber;

  bool isDark(int row, int col) => modules[row * size + col] == 1;
}

/// Build a QR in true 8-bit **byte mode** from raw binary.
///
/// Byte mode carries the bytes verbatim, so no base64 armouring is needed.
/// [maskPattern] skips the 8-candidate mask search when supplied; fountain
/// payloads are effectively random, so any mask scores about the same.
QrBitmap buildQrBitmap(
  Uint8List data, {
  int errorCorrectLevel = QrErrorCorrectLevel.L,
  int? maskPattern,
}) {
  final code = QrCode.fromUint8List(
    data: data,
    errorCorrectLevel: errorCorrectLevel,
  );
  final image = maskPattern == null
      ? QrImage(code)
      : QrImage.withMaskPattern(code, maskPattern);

  final size = image.moduleCount;
  final modules = Uint8List(size * size);
  for (var row = 0; row < size; row++) {
    final base = row * size;
    for (var col = 0; col < size; col++) {
      if (image.isDark(row, col)) modules[base + col] = 1;
    }
  }
  return QrBitmap(size: size, modules: modules, typeNumber: image.typeNumber);
}

/// Rasterise to an 8-bit luminance buffer (255 = white) the way a camera
/// would see it: white quiet zone, integer module scaling, no anti-aliasing.
///
/// Used by the headless round-trip tests to exercise the real decoder.
({int width, int height, Int8List lum}) rasterizeQrBitmap(
  QrBitmap bitmap, {
  int moduleScale = 4,
  int quietModules = 4,
}) {
  final side = (bitmap.size + quietModules * 2) * moduleScale;
  // zxing reads luminance as `byte & 0xFF`, so -1 is white.
  final lum = Int8List(side * side)..fillRange(0, side * side, -1);
  final origin = quietModules * moduleScale;

  for (var row = 0; row < bitmap.size; row++) {
    for (var col = 0; col < bitmap.size; col++) {
      if (!bitmap.isDark(row, col)) continue;
      final y0 = origin + row * moduleScale;
      final x0 = origin + col * moduleScale;
      for (var dy = 0; dy < moduleScale; dy++) {
        final rowBase = (y0 + dy) * side + x0;
        for (var dx = 0; dx < moduleScale; dx++) {
          lum[rowBase + dx] = 0;
        }
      }
    }
  }
  return (width: side, height: side, lum: lum);
}
