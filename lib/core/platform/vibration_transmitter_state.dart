import 'package:flutter/foundation.dart';

/// Controls vibration transmitter UI feedback during TX.
class VibrationTransmitterState extends ChangeNotifier {
  bool _vibrating = false;
  bool _transmitting = false;
  double _lastMagnitude = 0;

  bool get vibrating => _vibrating;
  bool get transmitting => _transmitting;
  double get lastMagnitude => _lastMagnitude;

  void setVibrating(bool value) {
    if (_vibrating != value) {
      _vibrating = value;
      notifyListeners();
    }
  }

  void setTransmitting(bool value) {
    if (_transmitting != value) {
      _transmitting = value;
      notifyListeners();
    }
  }

  void setLastMagnitude(double value) {
    _lastMagnitude = value;
    notifyListeners();
  }
}

final vibrationTransmitterState = VibrationTransmitterState();
