import 'package:flutter/foundation.dart';

/// Live feedback while the speaker is playing a sound transfer.
///
/// The sound channel is rateless and has no return path, so there is nothing
/// to report but "how much have we played and roughly how long is left" —
/// the receiver is the one that knows when it has enough.
class AcousticTransmitterState extends ChangeNotifier {
  bool _playing = false;
  int _totalBytes = 0;
  int _symbolsSent = 0;
  int _symbolsPlanned = 0;
  String _profileLabel = '';
  double _estimateSeconds = 0;

  bool get playing => _playing;
  int get totalBytes => _totalBytes;
  int get symbolsSent => _symbolsSent;
  int get symbolsPlanned => _symbolsPlanned;
  String get profileLabel => _profileLabel;
  double get estimateSeconds => _estimateSeconds;

  double get fraction => _symbolsPlanned == 0
      ? 0
      : (_symbolsSent / _symbolsPlanned).clamp(0.0, 1.0);

  void beginAcoustic({
    required int totalBytes,
    required String profileLabel,
    required double estimateSeconds,
  }) {
    _playing = true;
    _totalBytes = totalBytes;
    _profileLabel = profileLabel;
    _estimateSeconds = estimateSeconds;
    _symbolsSent = 0;
    _symbolsPlanned = 0;
    notifyListeners();
  }

  void setAcousticProgress(int sent, int planned) {
    if (_symbolsSent == sent && _symbolsPlanned == planned) return;
    _symbolsSent = sent;
    _symbolsPlanned = planned;
    notifyListeners();
  }

  void endAcoustic() {
    if (!_playing) return;
    _playing = false;
    notifyListeners();
  }

  void reset() {
    _playing = false;
    _totalBytes = 0;
    _symbolsSent = 0;
    _symbolsPlanned = 0;
    _estimateSeconds = 0;
    notifyListeners();
  }
}

final acousticTransmitterState = AcousticTransmitterState();
