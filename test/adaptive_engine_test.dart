import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/engine/adaptive_decision_engine.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

void main() {
  group('AdaptiveDecisionEngine', () {
    final engine = AdaptiveDecisionEngine();

    test('selects best channel', () {
      final results = [
        const ChannelTestResult(
          channel: CommChannelId.optical,
          packetsSent: 20,
          packetsReceived: 19,
          packetLossRate: 0.05,
          throughput: 18000,
          latency: 80,
          confidence: 0.9,
          stability: 0.85,
        ),
        const ChannelTestResult(
          channel: CommChannelId.acoustic,
          packetsSent: 20,
          packetsReceived: 17,
          packetLossRate: 0.15,
          throughput: 9000,
          latency: 130,
          confidence: 0.75,
          stability: 0.7,
        ),
      ];

      final decision = engine.selectBestChannel(results);
      expect(decision.selectedChannel, CommChannelId.optical);
    });

    test('applies hysteresis', () {
      expect(engine.shouldSwitch(0.70, 0.71), isFalse);
      expect(engine.shouldSwitch(0.60, 0.82), isTrue);
      expect(engine.shouldSwitch(0.85, 0.90), isFalse);
    });

    test('detects degradation', () {
      expect(engine.isDegraded(0.50), isTrue);
      expect(engine.isDegraded(0.80), isFalse);
    });
  });
}
