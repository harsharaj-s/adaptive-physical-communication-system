import 'package:adaptive_physical_communication/core/physical/fountain/qr_fountain_frame.dart';

/// TX/RX speed-density profile for fountain QR optical transfers.
///
/// [txFps] is capped so every QR stays on screen for at least two camera
/// exposures (~66 ms at 30 fps capture). Displaying faster than that only
/// guarantees the receiver catches codes mid-swap, which decode as nothing.
class OpticalTxProfile {
  const OpticalTxProfile({
    required this.id,
    required this.label,
    required this.txFps,
    required this.blockLen,
    required this.errorCorrectLevel,
    required this.decodeTargetPx,
  });

  final String id;
  final String label;
  final int txFps;
  final int blockLen;
  final String errorCorrectLevel;

  /// Luminance frame size handed to the decoder. Bigger keeps dense codes
  /// readable; smaller decodes faster.
  final int decodeTargetPx;

  /// Bytes carried inside one QR after APCF framing overhead.
  int get payloadBytesPerFrame => blockLen;

  /// Approximate raw TX rate before camera loss.
  double get nominalKbps => (blockLen * txFps) / 1000.0;

  bool get isAuto => id == auto.id;

  // Density is chosen from a simulated-camera sweep
  // (test/optical_density_sweep_test.dart). With the code at half the camera
  // view, hand-held, the decode rate per captured frame was:
  //   160 B (QR v8) 100%   240 B (v10) 94%   330 B (v12) 81%
  //   600 B (v17)   31%    800 B (v20) 13%   1200 B (v25) 0%
  // The old 800 B default matched the field report almost exactly (DEC 2/s
  // out of CAP 18 fps), so dense codes are opt-in only.

  /// Picks the density from the payload size — see [resolveFor].
  static const auto = OpticalTxProfile(
    id: 'auto',
    label: 'Auto',
    txFps: 12,
    blockLen: 240,
    errorCorrectLevel: 'L',
    decodeTargetPx: 720,
  );

  /// QR v8: still decodes when the camera is too far, shaky or washed out.
  static const safe = OpticalTxProfile(
    id: 'safe',
    label: 'Safe',
    txFps: 8,
    blockLen: 160,
    errorCorrectLevel: 'L',
    decodeTargetPx: 720,
  );

  /// QR v12 (65 modules).
  static const standard = OpticalTxProfile(
    id: 'standard',
    label: 'Standard',
    txFps: 12,
    blockLen: 330,
    errorCorrectLevel: 'L',
    decodeTargetPx: 720,
  );

  /// QR v17 (85 modules): only for a steady hand, close range, good light.
  static const fast = OpticalTxProfile(
    id: 'fast',
    label: 'Fast',
    txFps: 12,
    blockLen: 600,
    errorCorrectLevel: 'L',
    decodeTargetPx: 800,
  );

  static const values = [auto, safe, standard, fast];

  /// Block lengths [auto] steps through, sparsest first.
  static const autoBlockLadder = [160, 240, 330];

  /// [auto] takes the sparsest code that needs at most this many symbols,
  /// i.e. roughly a five-second transfer at a typical decode rate.
  static const autoTargetSymbols = 48;

  static OpticalTxProfile byId(String id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return auto;
  }

  /// Concrete profile to transmit [envelopeBytes] with. Fixed profiles return
  /// themselves; [auto] keeps small payloads on sparse, robust codes and only
  /// densifies when a sparse code would make the transfer drag.
  OpticalTxProfile resolveFor(int envelopeBytes) {
    if (!isAuto) return this;
    var block = autoBlockLadder.last;
    for (final b in autoBlockLadder) {
      if ((envelopeBytes / b).ceil() <= autoTargetSymbols) {
        block = b;
        break;
      }
    }
    return OpticalTxProfile(
      id: id,
      label: label,
      txFps: txFps,
      blockLen: block,
      errorCorrectLevel: errorCorrectLevel,
      decodeTargetPx: decodeTargetPx,
    );
  }

  /// Share of displayed frames a well-aimed receiver turns into symbols:
  /// the simulated decode rate, discounted for captures that straddle a
  /// display refresh (camera and screen are not synchronised).
  double get expectedCaptureYield => switch (blockLen) {
        <= 160 => 0.7,
        <= 240 => 0.65,
        <= 330 => 0.55,
        _ => 0.35,
      };

  /// Rough seconds for a receiver to finish [envelopeBytes].
  int estimatedSeconds(int envelopeBytes) {
    final p = resolveFor(envelopeBytes);
    final k = (envelopeBytes / p.blockLen).ceil().clamp(1, 1 << 20);
    final symbolsPerSecond = p.txFps * p.expectedCaptureYield;
    return ((k + 2) / symbolsPerSecond).ceil().clamp(1, 1 << 20);
  }

  /// Step down one profile when decode cannot keep up.
  OpticalTxProfile get slower => id == fast.id ? standard : safe;

  /// Frame byte budget including APCF overhead (for capacity checks).
  int get framedSymbolBytes => blockLen + qrFountainOverhead;

  @override
  bool operator ==(Object other) =>
      other is OpticalTxProfile &&
      other.id == id &&
      other.blockLen == blockLen;

  @override
  int get hashCode => Object.hash(id, blockLen);
}

/// Live optical transfer statistics for HUD / auto-backoff.
class OpticalTransferMetrics {
  const OpticalTransferMetrics({
    this.captureFps = 0,
    this.decodeFps = 0,
    this.dropped = 0,
    this.goodputKBps = 0,
    this.elapsedSec = 0,
    this.framesNew = 0,
    this.framesDup = 0,
    this.framesRed = 0,
    this.sessionId,
    this.blockLen = 0,
    this.payloadBytes = 0,
    this.symbolsCollected = 0,
    this.symbolsNeeded = 0,
    this.locked = false,
    this.complete = false,
    this.stalled = false,
    this.profileLabel = 'Standard',
  });

  final double captureFps;
  final double decodeFps;
  final int dropped;
  final double goodputKBps;
  final double elapsedSec;
  final int framesNew;
  final int framesDup;
  final int framesRed;
  final String? sessionId;
  final int blockLen;
  final int payloadBytes;
  final int symbolsCollected;
  final int symbolsNeeded;
  final bool locked;
  final bool complete;

  /// Frames are arriving but none decode — usually aim, distance or glare.
  final bool stalled;
  final String profileLabel;

  double get progress {
    if (symbolsNeeded <= 0) return complete ? 1 : 0;
    return (symbolsCollected / symbolsNeeded).clamp(0.0, 1.0);
  }

  OpticalTransferMetrics copyWith({
    double? captureFps,
    double? decodeFps,
    int? dropped,
    double? goodputKBps,
    double? elapsedSec,
    int? framesNew,
    int? framesDup,
    int? framesRed,
    String? sessionId,
    int? blockLen,
    int? payloadBytes,
    int? symbolsCollected,
    int? symbolsNeeded,
    bool? locked,
    bool? complete,
    bool? stalled,
    String? profileLabel,
  }) {
    return OpticalTransferMetrics(
      captureFps: captureFps ?? this.captureFps,
      decodeFps: decodeFps ?? this.decodeFps,
      dropped: dropped ?? this.dropped,
      goodputKBps: goodputKBps ?? this.goodputKBps,
      elapsedSec: elapsedSec ?? this.elapsedSec,
      framesNew: framesNew ?? this.framesNew,
      framesDup: framesDup ?? this.framesDup,
      framesRed: framesRed ?? this.framesRed,
      sessionId: sessionId ?? this.sessionId,
      blockLen: blockLen ?? this.blockLen,
      payloadBytes: payloadBytes ?? this.payloadBytes,
      symbolsCollected: symbolsCollected ?? this.symbolsCollected,
      symbolsNeeded: symbolsNeeded ?? this.symbolsNeeded,
      locked: locked ?? this.locked,
      complete: complete ?? this.complete,
      stalled: stalled ?? this.stalled,
      profileLabel: profileLabel ?? this.profileLabel,
    );
  }

  static const empty = OpticalTransferMetrics();
}
