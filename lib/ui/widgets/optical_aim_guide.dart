import 'package:flutter/material.dart';

/// Corner brackets marking the square the QR decoder actually reads.
///
/// The decoder crops the centre square of the camera frame, so the guide is
/// a centred square too: a QR inside the brackets is inside the crop.
class OpticalAimGuide extends StatelessWidget {
  const OpticalAimGuide({super.key, this.color = Colors.white70});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _AimGuidePainter(color: color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AimGuidePainter extends CustomPainter {
  _AimGuidePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 20.0;
    const len = 36.0;
    final side = size.shortestSide - inset * 2;
    if (side <= len * 2) return;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );

    for (final (corner, dx, dy) in [
      (rect.topLeft, len, len),
      (rect.topRight, -len, len),
      (rect.bottomLeft, len, -len),
      (rect.bottomRight, -len, -len),
    ]) {
      canvas.drawLine(corner, corner + Offset(dx, 0), paint);
      canvas.drawLine(corner, corner + Offset(0, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AimGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}
