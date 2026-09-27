import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Samples average luminance from the live camera preview on Flutter Web.
///
/// The camera plugin renders an [HTMLVideoElement]; we draw a small center
/// patch to a canvas and read RGBA pixels (same idea as mobile frame sampling).
double? sampleOpticalLuminanceFromPreview() {
  final videos = web.document.querySelectorAll('video');
  if (videos.length == 0) return null;

  final video = videos.item(0)! as web.HTMLVideoElement;
  final width = video.videoWidth;
  final height = video.videoHeight;
  if (width <= 0 || height <= 0) return null;

  const patch = 24;
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

  var sum = 0.0;
  var count = 0;
  for (var i = 0; i + 3 < data.length; i += 4) {
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    sum += 0.299 * r + 0.587 * g + 0.114 * b;
    count++;
  }
  return count > 0 ? sum / count / 255.0 : null;
}

/// Four RGB cell averages (0–255) matching the 2×2 CSK mosaic.
List<(double, double, double)>? sampleCskCellsFromPreview() {
  final videos = web.document.querySelectorAll('video');
  if (videos.length == 0) return null;

  final video = videos.item(0)! as web.HTMLVideoElement;
  final width = video.videoWidth;
  final height = video.videoHeight;
  if (width <= 0 || height <= 0) return null;

  const patch = 20;
  final cells = <(double, double, double)>[];
  final centers = [
    (width * 0.28, height * 0.28),
    (width * 0.72, height * 0.28),
    (width * 0.28, height * 0.72),
    (width * 0.72, height * 0.72),
  ];
  for (final c in centers) {
    final left = (c.$1 - patch / 2).round().clamp(0, width - patch);
    final top = (c.$2 - patch / 2).round().clamp(0, height - patch);
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
    final data = canvas.context2D.getImageData(0, 0, patch, patch).data.toDart;
    if (data.isEmpty) return null;
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var n = 0;
    for (var i = 0; i + 3 < data.length; i += 4) {
      r += data[i];
      g += data[i + 1];
      b += data[i + 2];
      n++;
    }
    if (n == 0) return null;
    cells.add((r / n, g / n, b / n));
  }
  return cells;
}
