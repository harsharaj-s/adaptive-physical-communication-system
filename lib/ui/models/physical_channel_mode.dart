import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

/// User-facing physical channel modes (Light / Sound / Vibrate).
enum PhysicalChannelMode {
  light,
  sound,
  vibrate,
}

extension PhysicalChannelModeX on PhysicalChannelMode {
  String get label => switch (this) {
        PhysicalChannelMode.light => 'Light',
        PhysicalChannelMode.sound => 'Sound',
        PhysicalChannelMode.vibrate => 'Vibrate',
      };

  String get subtitle => switch (this) {
        PhysicalChannelMode.light =>
          'Animated QR — camera to screen, no Wi‑Fi (hold 15–25 cm)',
        PhysicalChannelMode.sound =>
          'Speaker tones — text and small files, across a room',
        PhysicalChannelMode.vibrate =>
          'Contact-only — short text, phones pressed together',
      };

  IconData get icon => switch (this) {
        PhysicalChannelMode.light => Icons.flashlight_on,
        PhysicalChannelMode.sound => Icons.volume_up_rounded,
        PhysicalChannelMode.vibrate => Icons.vibration,
      };

  CommChannelId get channelId => switch (this) {
        PhysicalChannelMode.light => CommChannelId.optical,
        PhysicalChannelMode.sound => CommChannelId.acoustic,
        PhysicalChannelMode.vibrate => CommChannelId.vibration,
      };

  bool get supportsBroadcast => this != PhysicalChannelMode.vibrate;

  bool get isAvailable => switch (this) {
        PhysicalChannelMode.vibrate => isVibrationSupported,
        _ => isPhysicalChannelSupported,
      };
}

List<PhysicalChannelMode> get availablePhysicalModes =>
    PhysicalChannelMode.values.where((m) => m.isAvailable).toList();

PhysicalChannelMode? channelIdToPhysicalMode(CommChannelId id) {
  return switch (id) {
    CommChannelId.optical => PhysicalChannelMode.light,
    CommChannelId.acoustic => PhysicalChannelMode.sound,
    CommChannelId.vibration => PhysicalChannelMode.vibrate,
  };
}
