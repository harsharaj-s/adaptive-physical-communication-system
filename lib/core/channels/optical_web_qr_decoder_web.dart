import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:zxing2/qrcode.dart';
/// Decode a QR code from the live camera preview on Flutter Web.
String? sampleOpticalQrFromPreview() {
  final videos = web.document.querySelectorAll('video');
  if (videos.length == 0) return null;

  final video = videos.item(0)! as web.HTMLVideoElement;
  final width = video.videoWidth;
  final height = video.videoHeight;
  if (width <= 0 || height <= 0) return null;

  const patch = 640;
  final cx = width ~/ 2;
  final cy = height ~/ 2;
  final left = (cx - patch ~/ 2).clamp(0, width - patch);
  final top = (cy - patch ~/ 2).clamp(0, height - patch);

  final canvas = web.HTMLCanvasElement()
    ..width = patch
    ..height = patch;
  canvas.context2D.drawImage(
    video,
    left.toDouble(),
    top.toDouble(),
    patch.toDouble(),
    patch.toDouble(),
    0,
    0,
    patch.toDouble(),
    patch.toDouble(),
  );

  final imageData = canvas.context2D.getImageData(0, 0, patch, patch);
  final data = imageData.data.toDart;
  if (data.isEmpty) return null;

  final pixels = Int32List(patch * patch);
  var pixelIdx = 0;
  for (var i = 0; i + 3 < data.length; i += 4) {
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    pixels[pixelIdx++] = 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  final hints = DecodeHints()
    ..put(DecodeHintType.tryHarder)
    ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode])
    ..put(DecodeHintType.characterSet, 'UTF-8');

  try {
    final source = RGBLuminanceSource(patch, patch, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap, hints: hints).text;
  } catch (_) {
    try {
      final source = RGBLuminanceSource(patch, patch, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source.invert()));
      return QRCodeReader().decode(bitmap, hints: hints).text;
    } catch (_) {
      return null;
    }
  }
}
