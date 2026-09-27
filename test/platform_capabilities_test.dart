import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';

void main() {
  test('isPhysicalChannelSupported includes web or mobile', () {
    // In test environment, typically not web and not mobile — both may be false.
    expect(isVibrationSupported, equals(isHardwarePlatform));
    if (isHardwarePlatform) {
      expect(isPhysicalChannelSupported, isTrue);
      expect(isVibrationSupported, isTrue);
    }
  });

  test('platform labels are non-empty', () {
    expect(platformCapabilityLabel.isNotEmpty, isTrue);
    expect(platformCapabilitySummary.isNotEmpty, isTrue);
    expect(hardwarePairingSteps, isNotEmpty);
  });
}
