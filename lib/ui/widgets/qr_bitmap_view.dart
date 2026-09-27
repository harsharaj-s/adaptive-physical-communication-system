import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/fountain/qr_bitmap.dart';

/// Paints a [QrBitmap] with whole-pixel modules.
///
/// Snapping the module size to an integer and drawing pure black on pure white
/// keeps every edge sharp. Fractional module widths leave grey anti-aliased
/// seams, which is what makes a dense code undecodable at a distance.
class QrBitmapView extends StatelessWidget {
  const QrBitmapView({
    super.key,
    required this.bitmap,
    this.quietModules = 4,
  });

  final QrBitmap bitmap;

  /// Quiet zone in modules. The QR spec requires 4; the decoder needs it to
  /// find the finder patterns.
  final int quietModules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest.shortestSide;
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final totalModules = bitmap.size + quietModules * 2;

        // Work in device pixels so the snap is exact on screen.
        final availablePx = available * devicePixelRatio;
        final modulePx = (availablePx / totalModules).floorToDouble();
        if (modulePx < 1) {
          return const SizedBox.shrink();
        }
        final sideLogical = (modulePx * totalModules) / devicePixelRatio;

        return SizedBox(
          width: sideLogical,
          height: sideLogical,
          child: CustomPaint(
            painter: _QrBitmapPainter(
              bitmap: bitmap,
              quietModules: quietModules,
              modulePx: modulePx,
              devicePixelRatio: devicePixelRatio,
            ),
          ),
        );
      },
    );
  }
}

class _QrBitmapPainter extends CustomPainter {
  _QrBitmapPainter({
    required this.bitmap,
    required this.quietModules,
    required this.modulePx,
    required this.devicePixelRatio,
  });

  final QrBitmap bitmap;
  final int quietModules;
  final double modulePx;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final module = modulePx / devicePixelRatio;
    final origin = quietModules * module;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );

    final dark = Paint()
      ..color = Colors.black
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    // Merge horizontal runs into one rect each: far fewer draw calls than one
    // per module, which keeps a 100x100 code cheap to repaint.
    for (var row = 0; row < bitmap.size; row++) {
      var col = 0;
      while (col < bitmap.size) {
        if (!bitmap.isDark(row, col)) {
          col++;
          continue;
        }
        var run = 1;
        while (col + run < bitmap.size && bitmap.isDark(row, col + run)) {
          run++;
        }
        canvas.drawRect(
          Rect.fromLTWH(
            origin + col * module,
            origin + row * module,
            module * run,
            module,
          ),
          dark,
        );
        col += run;
      }
    }
  }

  @override
  bool shouldRepaint(_QrBitmapPainter old) =>
      old.bitmap != bitmap ||
      old.modulePx != modulePx ||
      old.quietModules != quietModules;
}
