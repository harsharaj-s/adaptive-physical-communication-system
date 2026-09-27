import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:zxing2/qrcode.dart';

/// Copied luminance frame safe to decode after the camera callback returns.
class QrFramePixels {
  const QrFramePixels({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;
  final Int32List pixels;
}

/// Extract center-crop pixels immediately (CameraImage buffers are recycled).
QrFramePixels? extractQrFramePixels(CameraImage image) {
  final srcW = image.width;
  final srcH = image.height;
  if (srcW < 8 || srcH < 8) return null;

  const cropFraction = 0.92;
  final cropW = (srcW * cropFraction).round().clamp(8, srcW);
  final cropH = (srcH * cropFraction).round().clamp(8, srcH);
  final left = (srcW - cropW) ~/ 2;
  final top = (srcH - cropH) ~/ 2;

  // Dense fountain QRs need more than 640px or modules smear.
  const targetMax = 1280;
  final scale = cropW > targetMax ? targetMax / cropW : 1.0;
  final outW = (cropW * scale).round().clamp(8, cropW);
  final outH = (cropH * scale).round().clamp(8, cropH);

  final pixels = Int32List(outW * outH);
  final plane = image.planes.first;
  final bpp = plane.bytesPerPixel ?? (kIsWeb ? 4 : 1);

  for (var y = 0; y < outH; y++) {
    final srcY = top + ((y / outH) * cropH).floor().clamp(0, cropH - 1);
    for (var x = 0; x < outW; x++) {
      final srcX = left + ((x / outW) * cropW).floor().clamp(0, cropW - 1);
      final (r, g, b) = _sampleRgb(image, plane, bpp, srcX, srcY);
      pixels[y * outW + x] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }
  }

  return QrFramePixels(width: outW, height: outH, pixels: pixels);
}

/// Decode QR from a camera frame (copies first — safe after callback returns).
String? decodeQrFromCameraImage(CameraImage image) {
  final pixels = extractQrFramePixels(image);
  if (pixels == null) return null;
  return decodeQrTextFromPixels(pixels);
}

/// Decode QR text from already-copied pixels.
String? decodeQrTextFromPixels(QrFramePixels frame) {
  return _decodeResult(frame)?.text;
}

/// Prefer raw byte segments when present; else UTF-8 text bytes.
Uint8List? decodeQrBytesFromPixels(QrFramePixels frame) {
  final result = _decodeResult(frame);
  if (result == null) return null;

  final segments = result.resultMetadata[ResultMetadataType.byteSegments];
  if (segments is List && segments.isNotEmpty) {
    final builder = BytesBuilder(copy: false);
    for (final seg in segments) {
      if (seg is Int8List) {
        builder.add(Uint8List.fromList(List<int>.from(seg)));
      } else if (seg is Uint8List) {
        builder.add(seg);
      }
    }
    final joined = builder.takeBytes();
    if (joined.isNotEmpty) return joined;
  }

  final raw = result.rawBytes;
  if (raw != null && raw.isNotEmpty) {
    return Uint8List.fromList(List<int>.from(raw));
  }

  if (result.text.isNotEmpty) {
    return Uint8List.fromList(utf8.encode(result.text));
  }
  return null;
}

/// Decode raw binary from an 8-bit luminance buffer — the fountain RX path.
///
/// `RGBLuminanceSource.crop` takes luminance bytes verbatim, so a Y-plane
/// frame needs no colour conversion at all.
Uint8List? decodeQrBytesFromLuminance(int width, int height, Int8List lum) {
  final source = RGBLuminanceSource.crop(lum, width, height, 0, 0, width, height);
  final result = _decodeLuminance(source);
  if (result == null) return null;
  return _resultBytes(result);
}

Result? _decodeLuminance(LuminanceSource source) {
  // A screen-displayed QR is high contrast and evenly lit, so the global
  // histogram threshold succeeds far more cheaply than the hybrid binarizer.
  final global = BinaryBitmap(GlobalHistogramBinarizer(source));

  // Finder-pattern detection fails on a few percent of dense codes because
  // random payload bytes can form 1:1:3:1:1 runs that outrank the real
  // corners. `pureBarcode` skips the search and reads the grid off the black
  // bounding box instead, which rescues those frames whenever the code fills
  // the crop. Both passes are Reed-Solomon checked, so neither can lie.
  for (final attempt in [
    (global, _fastHints),
    (global, _pureHints),
    (BinaryBitmap(HybridBinarizer(source)), _fastHints),
  ]) {
    try {
      return QRCodeReader().decode(attempt.$1, hints: attempt.$2);
    } catch (_) {
      // Try the next strategy.
    }
  }
  return null;
}

/// No `tryHarder`: at streaming rates it is cheaper to drop a frame and take
/// the next fountain symbol than to spend extra milliseconds on this one.
final _fastHints = DecodeHints()
  ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode]);

final _pureHints = DecodeHints()
  ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode])
  ..put(DecodeHintType.pureBarcode);

Uint8List? _resultBytes(Result result) {
  final segments = result.resultMetadata[ResultMetadataType.byteSegments];
  if (segments is List && segments.isNotEmpty) {
    final builder = BytesBuilder(copy: false);
    for (final seg in segments) {
      if (seg is Int8List) {
        builder.add(Uint8List.view(seg.buffer, seg.offsetInBytes, seg.length));
      } else if (seg is Uint8List) {
        builder.add(seg);
      }
    }
    final joined = builder.takeBytes();
    if (joined.isNotEmpty) return joined;
  }

  final raw = result.rawBytes;
  if (raw != null && raw.isNotEmpty) {
    return Uint8List.fromList(List<int>.from(raw));
  }

  if (result.text.isNotEmpty) {
    return Uint8List.fromList(utf8.encode(result.text));
  }
  return null;
}

Result? _decodeResult(QrFramePixels frame) {
  final source = RGBLuminanceSource(
    frame.width,
    frame.height,
    frame.pixels,
  );
  final hints = DecodeHints()
    ..put(DecodeHintType.tryHarder)
    ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode])
    ..put(DecodeHintType.characterSet, 'UTF-8');

  try {
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap, hints: hints);
  } catch (_) {
    try {
      final bitmap = BinaryBitmap(HybridBinarizer(source.invert()));
      return QRCodeReader().decode(bitmap, hints: hints);
    } catch (_) {
      return null;
    }
  }
}

(int r, int g, int b) _sampleRgb(
  CameraImage image,
  Plane plane,
  int bpp,
  int x,
  int y,
) {
  if (kIsWeb || bpp >= 3) {
    final bytesPerPixel = bpp >= 3 ? bpp : 4;
    final idx = y * plane.bytesPerRow + x * bytesPerPixel;
    if (idx + 2 >= plane.bytes.length) return (0, 0, 0);
    if (bytesPerPixel == 4) {
      return (
        plane.bytes[idx + 2],
        plane.bytes[idx + 1],
        plane.bytes[idx],
      );
    }
    return (
      plane.bytes[idx],
      plane.bytes[idx + 1],
      plane.bytes[idx + 2],
    );
  }

  final yIdx = y * plane.bytesPerRow + x;
  if (yIdx >= plane.bytes.length) return (0, 0, 0);
  final yVal = plane.bytes[yIdx];
  return (yVal, yVal, yVal);
}
