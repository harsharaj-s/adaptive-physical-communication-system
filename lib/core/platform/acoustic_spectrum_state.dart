import 'package:flutter/foundation.dart';

import 'package:adaptive_physical_communication/core/physical/acoustic/spectrum_analyzer.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/tone_timeline.dart';

/// Live frequencies: what the speaker is playing and what the microphone hears.
///
/// Kept apart from the transmitter and receiver states because it changes at
/// audio rate; only the frequency readout listens to it.
class AcousticSpectrumState extends ChangeNotifier {
  ToneTimeline? _txTones;
  DateTime? _txStartedAt;
  SpectrumSnapshot _rx = SpectrumSnapshot.empty;

  /// Burst now playing, or null between bursts and when idle.
  ToneTimeline? get txTones => _txTones;

  SpectrumSnapshot get rx => _rx;

  /// Tones on air right now, read against the playback clock.
  ({ToneKind kind, List<double> hz})? txNow() {
    final tones = _txTones;
    final start = _txStartedAt;
    if (tones == null || start == null) return null;
    return tones.atTime(DateTime.now().difference(start));
  }

  /// [tones] started playing just now.
  void startTxBurst(ToneTimeline tones) {
    _txTones = tones;
    _txStartedAt = DateTime.now();
    notifyListeners();
  }

  void endTx() {
    if (_txTones == null) return;
    _txTones = null;
    _txStartedAt = null;
    notifyListeners();
  }

  void setRx(SpectrumSnapshot snapshot) {
    _rx = snapshot;
    notifyListeners();
  }

  void resetRx() {
    if (identical(_rx, SpectrumSnapshot.empty)) return;
    _rx = SpectrumSnapshot.empty;
    notifyListeners();
  }
}

final acousticSpectrumState = AcousticSpectrumState();
