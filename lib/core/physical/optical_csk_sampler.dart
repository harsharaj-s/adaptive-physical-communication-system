import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Average RGB of four quadrants from a camera frame (2×2 CSK mosaic).
List<(double, double, double)>? sampleCskCellsFromCamera(CameraImage image) {
  final w = image.width;
  final h = image.height;
  if (w < 16 || h < 16) return null;

  final insetX = (w * 0.18).round();
  final insetY = (h * 0.18).round();
  final innerW = w - insetX * 2;
  final innerH = h - insetY * 2;
  final cellW = innerW ~/ 2;
  final cellH = innerH ~/ 2;
  if (cellW < 4 || cellH < 4) return null;

  return [
    _avgCell(image, insetX, insetY, cellW, cellH),
    _avgCell(image, insetX + cellW, insetY, cellW, cellH),
    _avgCell(image, insetX, insetY + cellH, cellW, cellH),
    _avgCell(image, insetX + cellW, insetY + cellH, cellW, cellH),
  ];
}

(double, double, double) _avgCell(
  CameraImage image,
  int left,
  int top,
  int cellW,
  int cellH,
) {
  var rSum = 0.0;
  var gSum = 0.0;
  var bSum = 0.0;
  var n = 0;
  const steps = 6;
  for (var sy = 0; sy < steps; sy++) {
    final y = top + (cellH * (sy + 0.5) / steps).floor();
    for (var sx = 0; sx < steps; sx++) {
      final x = left + (cellW * (sx + 0.5) / steps).floor();
      final rgb = _sampleRgb(image, x, y);
      rSum += rgb.$1;
      gSum += rgb.$2;
      bSum += rgb.$3;
      n++;
    }
  }
  if (n == 0) return (0, 0, 0);
  return (rSum / n, gSum / n, bSum / n);
}

(int, int, int) _sampleRgb(CameraImage image, int x, int y) {
  final plane = image.planes.first;
  final bpp = plane.bytesPerPixel ?? (kIsWeb ? 4 : 1);
  if (kIsWeb || bpp >= 3) {
    final bytesPerPixel = bpp >= 3 ? bpp : 4;
    final idx = y * plane.bytesPerRow + x * bytesPerPixel;
    if (idx + 2 >= plane.bytes.length) return (0, 0, 0);
    if (bytesPerPixel == 4) {
      return (plane.bytes[idx + 2], plane.bytes[idx + 1], plane.bytes[idx]);
    }
    return (plane.bytes[idx], plane.bytes[idx + 1], plane.bytes[idx + 2]);
  }

  if (image.planes.length == 2) {
    final yPlane = image.planes[0];
    final uvPlane = image.planes[1];
    final yIdx = y * yPlane.bytesPerRow + x;
    if (yIdx >= yPlane.bytes.length) return (0, 0, 0);
    final uvX = x ~/ 2;
    final uvY = y ~/ 2;
    final uvIdx = uvY * uvPlane.bytesPerRow + uvX * 2;
    if (uvIdx + 1 >= uvPlane.bytes.length) {
      final yv = yPlane.bytes[yIdx];
      return (yv, yv, yv);
    }
    final v = uvPlane.bytes[uvIdx];
    final u = uvPlane.bytes[uvIdx + 1];
    return _yuvToRgb(yPlane.bytes[yIdx], u, v);
  }

  if (image.planes.length >= 3) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yIdx = y * yPlane.bytesPerRow + x;
    if (yIdx >= yPlane.bytes.length) return (0, 0, 0);
    final uvX = x ~/ 2;
    final uvY = y ~/ 2;
    final uIdx = uvY * uPlane.bytesPerRow + uvX * (uPlane.bytesPerPixel ?? 1);
    final vIdx = uvY * vPlane.bytesPerRow + uvX * (vPlane.bytesPerPixel ?? 1);
    final yy = yPlane.bytes[yIdx];
    final uu = uIdx < uPlane.bytes.length ? uPlane.bytes[uIdx] : 128;
    final vv = vIdx < vPlane.bytes.length ? vPlane.bytes[vIdx] : 128;
    return _yuvToRgb(yy, uu, vv);
  }

  final yIdx = y * plane.bytesPerRow + x;
  if (yIdx >= plane.bytes.length) return (0, 0, 0);
  final yv = plane.bytes[yIdx];
  return (yv, yv, yv);
}

(int, int, int) _yuvToRgb(int y, int u, int v) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
  return (r, g, b);
}
