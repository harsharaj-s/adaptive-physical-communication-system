import 'dart:math';
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/fountain/qr_bitmap.dart';

/// How a phone camera degrades a QR shown on another phone's screen.
class CameraDegradation {
  const CameraDegradation({
    required this.label,
    this.framePx = 720,
    this.qrFraction = 0.5,
    this.rotationDeg = 0,
    this.skew = 0,
    this.blurSigma = 0,
    this.motionBlurPx = 0,
    this.black = 20,
    this.white = 235,
    this.gamma = 1,
    this.noiseSigma = 0,
    this.glare = 0,
    this.quietModules = 4,
  });

  final String label;

  /// Side of the square luminance frame handed to the decoder.
  final int framePx;

  /// QR symbol (including its quiet zone) as a fraction of the frame side.
  final double qrFraction;
  final double rotationDeg;

  /// Keystone strength: corners move by up to this fraction of the QR side.
  final double skew;
  final double blurSigma;
  final double motionBlurPx;

  /// Luminance the camera records for a dark module / the white screen.
  final double black;
  final double white;

  /// Tone curve exponent; < 1 lifts the darks (a washed-out bright screen).
  final double gamma;
  final double noiseSigma;

  /// Peak additive glare (0..1 of the white level) from a soft hotspot.
  final double glare;

  /// White margin the sender draws around the code, in modules.
  final int quietModules;

  CameraDegradation zoomed(double zoom) => CameraDegradation(
        label: '$label x${zoom.toStringAsFixed(1)}',
        framePx: framePx,
        qrFraction: qrFraction * zoom,
        rotationDeg: rotationDeg,
        skew: skew,
        blurSigma: blurSigma,
        motionBlurPx: motionBlurPx,
        black: black,
        white: white,
        gamma: gamma,
        noiseSigma: noiseSigma,
        glare: glare,
        quietModules: quietModules,
      );

  CameraDegradation withFrame(int px) => CameraDegradation(
        label: label,
        framePx: px,
        qrFraction: qrFraction,
        rotationDeg: rotationDeg,
        skew: skew,
        blurSigma: blurSigma * px / framePx,
        motionBlurPx: motionBlurPx * px / framePx,
        black: black,
        white: white,
        gamma: gamma,
        noiseSigma: noiseSigma,
        glare: glare,
        quietModules: quietModules,
      );

  /// Well aimed, steady, bright screen.
  static const good = CameraDegradation(
    label: 'good',
    qrFraction: 0.62,
    rotationDeg: 4,
    skew: 0.03,
    blurSigma: 0.7,
    black: 35,
    white: 220,
    gamma: 0.9,
    noiseSigma: 3,
  );

  /// What the screenshot showed: code fills about half the view, hand-held.
  static const typical = CameraDegradation(
    label: 'typical',
    qrFraction: 0.5,
    rotationDeg: 8,
    skew: 0.06,
    blurSigma: 1.1,
    motionBlurPx: 1,
    black: 60,
    white: 205,
    gamma: 0.8,
    noiseSigma: 6,
    glare: 0.1,
  );

  /// Too far away, some shake, washed out.
  static const hard = CameraDegradation(
    label: 'hard',
    qrFraction: 0.42,
    rotationDeg: 12,
    skew: 0.08,
    blurSigma: 1.5,
    motionBlurPx: 2,
    black: 80,
    white: 195,
    gamma: 0.7,
    noiseSigma: 8,
    glare: 0.2,
  );

  static const tiers = [good, typical, hard];
}

/// Render [bitmap] as a camera would capture it under [d].
///
/// Each frame gets fresh random geometry within the tier's limits, so a
/// sweep over many frames measures a decode *rate*, not one lucky pose.
({int width, int height, Int8List lum}) renderCameraFrame(
  QrBitmap bitmap,
  CameraDegradation d,
  Random rng,
) {
  final f = d.framePx;
  final n = bitmap.size;
  final q = d.quietModules;
  final total = n + 2 * q;

  // Image-space quad of the QR area (quiet zone included).
  final side = d.qrFraction * f;
  final theta = (rng.nextDouble() * 2 - 1) * d.rotationDeg * pi / 180;
  final cx = f / 2 + (rng.nextDouble() * 2 - 1) * f * 0.03;
  final cy = f / 2 + (rng.nextDouble() * 2 - 1) * f * 0.03;
  final corners = <List<double>>[];
  for (final (sx, sy) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
    final jx = (rng.nextDouble() * 2 - 1) * d.skew * side;
    final jy = (rng.nextDouble() * 2 - 1) * d.skew * side;
    final x = sx * side / 2 + jx;
    final y = sy * side / 2 + jy;
    corners.add([
      cx + x * cos(theta) - y * sin(theta),
      cy + x * sin(theta) + y * cos(theta),
    ]);
  }
  final inv = _invert3(_squareToQuad(corners));

  // The screen is portrait: white well above and below the code, a thin
  // white margin beside it, then the dark bezel and a textured background.
  const sideMargin = 0.6; // modules of white beyond the quiet zone
  const bezel = 5.0;
  final screenHalfH = total * 1.05;

  final t = Float64List(f * f);
  const ss = 3;
  for (var y = 0; y < f; y++) {
    for (var x = 0; x < f; x++) {
      var acc = 0.0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final px = x + (sx + 0.5) / ss;
          final py = y + (sy + 0.5) / ss;
          final w = inv[6] * px + inv[7] * py + inv[8];
          final u = (inv[0] * px + inv[1] * py + inv[2]) / w * total - q;
          final v = (inv[3] * px + inv[4] * py + inv[5]) / w * total - q;
          acc += _shade(bitmap, u, v, n, q, sideMargin, bezel, screenHalfH);
        }
      }
      t[y * f + x] = acc / (ss * ss);
    }
  }

  var img = t;
  if (d.blurSigma > 0) img = _gaussianBlur(img, f, d.blurSigma);
  if (d.motionBlurPx > 0) {
    img = _motionBlur(img, f, d.motionBlurPx, rng.nextDouble() * pi);
  }

  final gx = rng.nextDouble() * f;
  final gy = rng.nextDouble() * f;
  final gr2 = pow(f * 0.25, 2).toDouble();
  final lum = Int8List(f * f);
  for (var i = 0; i < f * f; i++) {
    var val = pow(img[i].clamp(0.0, 1.0), d.gamma).toDouble();
    var out = d.black + (d.white - d.black) * val;
    if (d.glare > 0) {
      final dx = (i % f) - gx;
      final dy = (i ~/ f) - gy;
      out += d.glare * d.white * exp(-(dx * dx + dy * dy) / gr2);
    }
    if (d.noiseSigma > 0) out += _gauss(rng) * d.noiseSigma;
    lum[i] = out.round().clamp(0, 255);
  }
  return (width: f, height: f, lum: lum);
}

double _shade(
  QrBitmap bitmap,
  double u,
  double v,
  int n,
  int q,
  double sideMargin,
  double bezel,
  double screenHalfH,
) {
  final halfW = n / 2 + q + sideMargin;
  final du = u - n / 2;
  final dv = v - n / 2;
  if (du.abs() <= halfW && dv.abs() <= screenHalfH) {
    if (u >= 0 && v >= 0 && u < n && v < n) {
      return bitmap.isDark(v.floor(), u.floor()) ? 0.0 : 1.0;
    }
    return 1.0;
  }
  if (du.abs() <= halfW + bezel && dv.abs() <= screenHalfH + bezel * 3) {
    return 0.04;
  }
  // Table / hand texture.
  return 0.35 + 0.15 * sin(u * 0.37) * cos(v * 0.23);
}

List<double> _squareToQuad(List<List<double>> c) {
  final x0 = c[0][0], y0 = c[0][1];
  final x1 = c[1][0], y1 = c[1][1];
  final x2 = c[2][0], y2 = c[2][1];
  final x3 = c[3][0], y3 = c[3][1];
  final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  final den = dx1 * dy2 - dx2 * dy1;
  final g = (dx3 * dy2 - dx2 * dy3) / den;
  final h = (dx1 * dy3 - dx3 * dy1) / den;
  // Maps (u, v) in the unit square to image (x, y); row-major 3x3.
  return [
    x1 - x0 + g * x1, x3 - x0 + h * x3, x0, //
    y1 - y0 + g * y1, y3 - y0 + h * y3, y0, //
    g, h, 1,
  ];
}

List<double> _invert3(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  final det = a * A + b * B + c * C;
  return [
    A / det, -(b * i - c * h) / det, (b * f - c * e) / det, //
    B / det, (a * i - c * g) / det, -(a * f - c * d) / det, //
    C / det, -(a * h - b * g) / det, (a * e - b * d) / det,
  ];
}

Float64List _gaussianBlur(Float64List src, int f, double sigma) {
  final r = max(1, (sigma * 3).ceil());
  final k = List<double>.generate(
    2 * r + 1,
    (i) => exp(-pow(i - r, 2) / (2 * sigma * sigma)),
  );
  final sum = k.reduce((a, b) => a + b);
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  final tmp = Float64List(f * f);
  final out = Float64List(f * f);
  for (var y = 0; y < f; y++) {
    for (var x = 0; x < f; x++) {
      var acc = 0.0;
      for (var j = -r; j <= r; j++) {
        acc += src[y * f + (x + j).clamp(0, f - 1)] * k[j + r];
      }
      tmp[y * f + x] = acc;
    }
  }
  for (var y = 0; y < f; y++) {
    for (var x = 0; x < f; x++) {
      var acc = 0.0;
      for (var j = -r; j <= r; j++) {
        acc += tmp[(y + j).clamp(0, f - 1) * f + x] * k[j + r];
      }
      out[y * f + x] = acc;
    }
  }
  return out;
}

Float64List _motionBlur(Float64List src, int f, double len, double angle) {
  final steps = max(2, (len * 2).ceil());
  final dx = cos(angle) * len;
  final dy = sin(angle) * len;
  final out = Float64List(f * f);
  for (var y = 0; y < f; y++) {
    for (var x = 0; x < f; x++) {
      var acc = 0.0;
      for (var s = 0; s < steps; s++) {
        final t = s / (steps - 1) - 0.5;
        final sx = (x + dx * t).round().clamp(0, f - 1);
        final sy = (y + dy * t).round().clamp(0, f - 1);
        acc += src[sy * f + sx];
      }
      out[y * f + x] = acc / steps;
    }
  }
  return out;
}

double _gauss(Random rng) {
  final u1 = max(1e-12, rng.nextDouble());
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}
