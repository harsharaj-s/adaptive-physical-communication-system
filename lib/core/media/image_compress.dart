import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:image/image.dart' as img;

/// Thrown when the picked file cannot be converted to a transferable JPEG/PNG.
class ImageTransferException implements Exception {
  ImageTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Resize/compress photos so optical QR transfer finishes in seconds, not minutes.
/// Always returns JPEG bytes when conversion succeeds.
Future<Uint8List> compressImageForTransfer(
  Uint8List bytes, {
  int maxWidth = 960,
  int maxHeight = 960,
  int quality = 78,
  int maxBytes = 120 * 1024,
}) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    // Already a JPEG bitstream the decoder skipped? Pass through if valid SOI.
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return bytes.length <= maxBytes
          ? bytes
          : _recompressKnownJpeg(bytes, maxWidth, maxHeight, maxBytes);
    }
    throw ImageTransferException(
      'Could not read this photo. Try JPG/PNG or take a new picture.',
    );
  }

  var working = decoded;
  if (working.width > maxWidth || working.height > maxHeight) {
    working = img.copyResize(
      working,
      width: working.width > working.height ? maxWidth : null,
      height: working.height >= working.width ? maxHeight : null,
      interpolation: img.Interpolation.linear,
    );
  }

  var q = quality;
  Uint8List out = Uint8List.fromList(img.encodeJpg(working, quality: q));
  while (out.length > maxBytes && q > 40) {
    q -= 8;
    out = Uint8List.fromList(img.encodeJpg(working, quality: q));
  }

  if (out.length > maxBytes && (working.width > 640 || working.height > 640)) {
    working = img.copyResize(
      working,
      width: working.width > working.height ? 640 : null,
      height: working.height >= working.width ? 640 : null,
    );
    out = Uint8List.fromList(img.encodeJpg(working, quality: 65));
  }

  if (!ChatPayloadCodec.isDisplayableImage(out)) {
    throw ImageTransferException('Image compression failed — try another photo.');
  }

  return out;
}

Future<Uint8List> _recompressKnownJpeg(
  Uint8List bytes,
  int maxWidth,
  int maxHeight,
  int maxBytes,
) async {
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return bytes;
  var working = img.copyResize(
    decoded,
    width: decoded.width > maxWidth ? maxWidth : decoded.width,
    height: decoded.height > maxHeight ? maxHeight : decoded.height,
  );
  var out = Uint8List.fromList(img.encodeJpg(working, quality: 70));
  if (out.length <= maxBytes) return out;
  working = img.copyResize(working, width: 640);
  return Uint8List.fromList(img.encodeJpg(working, quality: 60));
}
