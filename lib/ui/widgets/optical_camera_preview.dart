import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Live camera preview for optical receiver mode (required on web for sampling).
class OpticalCameraPreview extends StatelessWidget {
  const OpticalCameraPreview({
    super.key,
    required this.controller,
    this.height = 120,
  });

  final CameraController? controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Starting camera…', style: TextStyle(fontSize: 12)),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CameraPreview(camera),
      ),
    );
  }
}
