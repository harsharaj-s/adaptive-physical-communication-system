import 'package:flutter/foundation.dart';

import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';

/// Pluggable optical physical modem (CSK, fountain QR, …).
abstract class OpticalModem {
  String get id;
  String get label;
  int get maxPayloadBytes;
  OpticalTransferMetrics get metrics;

  /// Begin receiving (camera frames will be forwarded).
  Future<void> startReceiver();

  Future<void> stopReceiver();

  /// Transmit a full APCM envelope (or raw bytes).
  Future<void> transmit(Uint8List envelope);

  void cancelTransmit();

  /// Native camera frame hook (no-op if unused).
  void onCameraFrame(Object image);

  /// Web timer sample hook (no-op if unused).
  void onWebSampleTick();

  /// Clear RX caches between messages.
  void clearReceiveCaches({bool resetDedup = false});

  /// Completed envelopes ready for the channel to deliver.
  List<Uint8List> takeEnvelopes();

  void dispose() {}
}

/// Notifies listeners when [OpticalTransferMetrics] change.
class OpticalMetricsNotifier extends ChangeNotifier {
  OpticalTransferMetrics _metrics = OpticalTransferMetrics.empty;

  OpticalTransferMetrics get metrics => _metrics;

  void update(OpticalTransferMetrics value) {
    _metrics = value;
    notifyListeners();
  }

  void reset() {
    _metrics = OpticalTransferMetrics.empty;
    notifyListeners();
  }
}
