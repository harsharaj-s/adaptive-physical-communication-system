import 'package:flutter/foundation.dart';

/// Live acoustic RX feedback for the receive UI (mic level, tone detection).
enum AcousticRxPhase {
  idle,
  permissionDenied,
  starting,
  listening,
  tonesDetected,
  decoding,
  decoded,
}

class AcousticReceiverState extends ChangeNotifier {
  AcousticRxPhase _phase = AcousticRxPhase.idle;
  double _inputLevel = 0;
  double _toneStrength = 0;
  int _packetsDecoded = 0;

  int _collected = 0;
  int _needed = 0;
  int _framesRepaired = 0;
  int _framesRejected = 0;

  AcousticRxPhase get phase => _phase;
  double get inputLevel => _inputLevel;
  double get toneStrength => _toneStrength;
  int get packetsDecoded => _packetsDecoded;

  /// Fountain symbols recovered so far, and how many the payload needs.
  int get collected => _collected;
  int get needed => _needed;

  /// Frames that passed Reed-Solomon, and frames heard but unrecoverable.
  int get framesRepaired => _framesRepaired;
  int get framesRejected => _framesRejected;

  /// Speed the receiver detected the sender using, empty until it locks.
  String get profileLabel => _profileLabel;
  String _profileLabel = '';

  bool get transferActive => _needed > 0 && _collected < _needed;

  double get transferFraction =>
      _needed == 0 ? 0 : (_collected / _needed).clamp(0.0, 1.0);

  bool get micLive =>
      _phase == AcousticRxPhase.listening ||
      _phase == AcousticRxPhase.tonesDetected ||
      _phase == AcousticRxPhase.decoding ||
      _phase == AcousticRxPhase.decoded;

  void setPhase(AcousticRxPhase value) {
    if (_phase == value) return;
    _phase = value;
    notifyListeners();
  }

  void setLevels({required double input, required double tone}) {
    var changed = false;
    if ((_inputLevel - input).abs() > 0.02) {
      _inputLevel = input;
      changed = true;
    }
    if ((_toneStrength - tone).abs() > 0.02) {
      _toneStrength = tone;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Progress for the fountain modem. Called from the microphone callback, so
  /// it only notifies when a listener would actually see a difference.
  void setFountainProgress({
    required int collected,
    required int needed,
    required int framesRepaired,
    required int framesRejected,
    String profileLabel = '',
  }) {
    if (_collected == collected &&
        _needed == needed &&
        _framesRepaired == framesRepaired &&
        _framesRejected == framesRejected &&
        _profileLabel == profileLabel) {
      return;
    }
    _collected = collected;
    _needed = needed;
    _framesRepaired = framesRepaired;
    _framesRejected = framesRejected;
    _profileLabel = profileLabel;
    if (needed > 0 && collected < needed && micLive) {
      _phase = AcousticRxPhase.decoding;
    }
    notifyListeners();
  }

  void markDecoded() {
    _packetsDecoded++;
    _phase = AcousticRxPhase.decoded;
    _collected = 0;
    _needed = 0;
    notifyListeners();
  }

  void reset({bool keepDecodeCount = true}) {
    _phase = AcousticRxPhase.idle;
    _inputLevel = 0;
    _toneStrength = 0;
    _collected = 0;
    _needed = 0;
    if (!keepDecodeCount) _packetsDecoded = 0;
    notifyListeners();
  }
}

final acousticReceiverState = AcousticReceiverState();
