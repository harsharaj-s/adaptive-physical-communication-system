import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

/// Documents and verifies the physical-only data path policy.
void main() {
  test('live data path uses only physical channel IDs', () {
    expect(
      CommChannelId.values.map((c) => c.name),
      containsAll(['optical', 'acoustic', 'vibration']),
    );
    expect(CommChannelId.values.length, 3);
  });

  test('excluded transports list covers network methods', () {
    expect(excludedNetworkTransports, isNotEmpty);
    expect(
      excludedNetworkTransports.any((t) => t.toLowerCase().contains('internet')),
      isTrue,
    );
    expect(
      excludedNetworkTransports.any((t) => t.toLowerCase().contains('wi-fi')),
      isTrue,
    );
    expect(
      excludedNetworkTransports.any((t) => t.toLowerCase().contains('bluetooth')),
      isTrue,
    );
  });

  test('physical-only policy summary is documented', () {
    expect(physicalOnlyPolicySummary.toLowerCase(), contains('no internet'));
    expect(physicalOnlyPolicySummary.toLowerCase(), contains('physical'));
  });
}
