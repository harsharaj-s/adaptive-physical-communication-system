import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Forces the sender screen to full brightness while a QR stream is shown.
///
/// A dim screen lowers the contrast the receiving camera sees and lengthens
/// its exposure, which is what smears a changing QR. Android only; elsewhere
/// the calls are no-ops.
class OpticalDisplayControl {
  const OpticalDisplayControl._();

  static const _channel = MethodChannel('apcs/optical_display');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> setMaxBrightness() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setMaxBrightness');
    } catch (_) {}
  }

  static Future<void> restoreBrightness() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('restoreBrightness');
    } catch (_) {}
  }
}
