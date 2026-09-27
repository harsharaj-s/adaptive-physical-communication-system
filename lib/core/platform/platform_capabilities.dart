import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/fountain/qr_bitmap.dart';

/// Optical TX/RX UI: CSK mosaic and/or fountain QR frames + decode confidence.
class OpticalTransmitterState extends ChangeNotifier {
  bool _transmitting = false;
  List<Color>? _cskCells;
  int _chunkIndex = 0;
  int _chunkTotal = 0;
  double _confidence = 0;
  bool _guard = false;

  /// Active modem overlay: `csk` or `fountain_qr`.
  String _modemId = 'fountain_qr';
  String? _qrPayload;
  QrBitmap? _qrBitmap;
  String? _fountainSessionId;
  int _fountainK = 0;
  int _fountainBlockLen = 0;
  int _fountainFileLen = 0;
  String _profileLabel = 'Standard';

  bool get transmitting => _transmitting;
  List<Color>? get cskCells => _cskCells;
  bool get showingGuard => _guard;
  int get chunkIndex => _chunkIndex;
  int get chunkTotal => _chunkTotal;
  double get confidence => _confidence;
  String get modemId => _modemId;
  bool get isFountainQr => _modemId == 'fountain_qr';
  String? get qrPayload => _qrPayload;
  QrBitmap? get qrBitmap => _qrBitmap;
  String? get fountainSessionId => _fountainSessionId;
  int get fountainK => _fountainK;
  int get fountainBlockLen => _fountainBlockLen;
  int get fountainFileLen => _fountainFileLen;
  String get profileLabel => _profileLabel;

  void setModemId(String id) {
    if (_modemId == id) return;
    _modemId = id;
    notifyListeners();
  }

  void setTransmitting(bool value) {
    if (_transmitting != value) {
      _transmitting = value;
      if (!value) {
        clearCsk();
        clearFountain();
      }
      notifyListeners();
    }
  }

  void setCskSymbol({
    required List<Color> cells,
    required int index,
    required int total,
  }) {
    _modemId = 'csk';
    _cskCells = cells;
    _qrPayload = null;
    _guard = false;
    _chunkIndex = index;
    _chunkTotal = total;
    notifyListeners();
  }

  void setCskGuard({required int index, required int total}) {
    _modemId = 'csk';
    _cskCells = null;
    _qrPayload = null;
    _guard = true;
    _chunkIndex = index;
    _chunkTotal = total;
    notifyListeners();
  }

  void setFountainSession({
    required String sessionId,
    required int k,
    required int blockLen,
    required int fileLen,
    required String profileLabel,
  }) {
    _modemId = 'fountain_qr';
    _fountainSessionId = sessionId;
    _fountainK = k;
    _fountainBlockLen = blockLen;
    _fountainFileLen = fileLen;
    _profileLabel = profileLabel;
    notifyListeners();
  }

  void setFountainQrFrame({
    required String payload,
    required int index,
    required int total,
  }) {
    _modemId = 'fountain_qr';
    _qrPayload = payload;
    _qrBitmap = null;
    _cskCells = null;
    _guard = false;
    _chunkIndex = index;
    _chunkTotal = total;
    notifyListeners();
  }

  /// Publish a pre-built module grid — the fountain TX path. Encoding happens
  /// off the paint path so the display cadence stays even.
  void setFountainQrBitmap({
    required QrBitmap bitmap,
    required int index,
    required int total,
  }) {
    _modemId = 'fountain_qr';
    _qrBitmap = bitmap;
    _qrPayload = null;
    _cskCells = null;
    _guard = false;
    _chunkIndex = index;
    _chunkTotal = total;
    notifyListeners();
  }

  void setQrFrame({
    required String payload,
    required int index,
    required int total,
  }) {
    setFountainQrFrame(payload: payload, index: index, total: total);
  }

  void clearCsk() {
    _cskCells = null;
    _guard = false;
    _chunkIndex = 0;
    _chunkTotal = 0;
  }

  void clearFountain() {
    _qrPayload = null;
    _qrBitmap = null;
    _fountainSessionId = null;
    _fountainK = 0;
    _fountainBlockLen = 0;
    _fountainFileLen = 0;
    _chunkIndex = 0;
    _chunkTotal = 0;
  }

  void clearQr() => clearFountain();

  void setConfidence(double value) {
    if ((_confidence - value).abs() < 0.001) return;
    _confidence = value;
    notifyListeners();
  }

  void resetScanFeedback() {
    _confidence = 0;
    notifyListeners();
  }
}

final opticalTransmitterState = OpticalTransmitterState();

/// Called when user taps Cancel on the full-screen optical overlay.
VoidCallback? onOpticalTransmitCancel;

/// Whether the app runs on a native mobile device (Android/iOS).
bool get isHardwarePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Optical and acoustic physical channels work on mobile and Flutter Web.
bool get isPhysicalChannelSupported => isHardwarePlatform || kIsWeb;

/// Data never leaves the device over IP, Wi-Fi, Bluetooth, or cellular.
const String physicalOnlyPolicySummary =
    'All message data uses physical channels only — no internet, Wi-Fi, '
    'Bluetooth, NFC, or cellular. Devices must be near each other; bits travel '
    'as light, sound, or vibration in the air/surface between them.';

/// Transport methods intentionally **not** used for the data path.
const List<String> excludedNetworkTransports = [
  'Internet / IP',
  'Wi-Fi',
  'Bluetooth',
  'NFC',
  'Cellular / SMS',
  'Cloud / servers',
];

/// Vibration requires a physical phone with motor + accelerometer.
bool get isVibrationSupported => isHardwarePlatform;

/// Short label for the current platform's hardware capabilities.
String get platformCapabilityLabel {
  if (isHardwarePlatform) return 'Phone: optical + acoustic + vibration';
  if (kIsWeb) return 'Laptop (Web): optical + acoustic';
  return 'Limited: simulation only';
}

/// Human-readable summary for UI banners.
String get platformCapabilitySummary {
  if (isHardwarePlatform) {
    return 'This phone supports optical (screen/camera), acoustic (speaker/mic), '
        'and vibration. Pair with another phone or a laptop running the web app.';
  }
  if (kIsWeb) {
    return 'This browser supports optical (fountain QR screen + webcam scan) and acoustic '
        '(speaker + microphone). Vibration is phone-only. Pair with a phone for '
        'phone ↔ laptop testing. $physicalOnlyPolicySummary';
  }
  return 'Physical channels require a phone or Chrome on a laptop. Simulation works here.';
}

/// Step-by-step pairing instructions for hardware transfer.
List<String> get hardwarePairingSteps => [
      'Broadcast (default): one Sender, many Receivers — all in Live mode.',
      'Optical (best for groups): sender shows animated fountain QR; receivers aim cameras (15–25 cm, QR inside the square).',
      'Acoustic: sender plays tones; any nearby receiver mic can decode (quiet room, ~30 cm).',
      if (isVibrationSupported)
        'Vibration: contact-only — not supported for broadcast (use 1:1 mode).',
      'Use 1:1 mode when you need paired ACK confirmation with one receiver.',
    ];