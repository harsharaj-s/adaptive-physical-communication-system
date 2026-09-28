import 'dart:math' as math;
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_frame_sync.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/mt_fsk_codec.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/tone_timeline.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';
import 'package:adaptive_physical_communication/core/physical/physical_codecs.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';

/// Snapshot of an in-flight acoustic receive, for the UI.
class AcousticRxProgress {
  const AcousticRxProgress({
    required this.collected,
    required this.needed,
    required this.framesRepaired,
    required this.framesRejected,
    required this.complete,
  });

  final int collected;
  final int needed;
  final int framesRepaired;
  final int framesRejected;
  final bool complete;

  static const idle = AcousticRxProgress(
    collected: 0,
    needed: 0,
    framesRepaired: 0,
    framesRejected: 0,
    complete: false,
  );

  bool get active => needed > 0 && !complete;

  double get fraction => needed == 0 ? 0 : (collected / needed).clamp(0.0, 1.0);
}

/// Sound transfer built from three reusable pieces: multi-tone FSK for the
/// waveform, Reed-Solomon per frame, and the existing LT fountain code across
/// frames.
///
/// The layering matters. Reed-Solomon repairs the handful of bytes a single
/// frame loses to a multipath null, which is what turns a marginal frame into
/// a usable one. The fountain code then covers frames lost outright, and
/// because it is rateless the sender can keep minting fresh symbols without
/// ever needing to hear back from the receiver — the same trick the optical
/// channel uses, and the reason neither side needs a return path.
class AcousticFountainModem {
  AcousticFountainModem({
    AcousticTxProfile profile = AcousticTxProfile.standard,
    this.autoDetectProfile = true,
    StructuredLogger? logger,
  })  : _profile = profile,
        _logger = logger ?? StructuredLogger();

  final StructuredLogger _logger;
  AcousticTxProfile _profile;

  /// Listen for every profile at once and lock onto whichever the sender is
  /// using, so the receiving phone never has to be set to match. All profiles
  /// share one sync burst; only a frame that survives Reed-Solomon and the CRC
  /// under a given profile's layout counts as a detection.
  final bool autoDetectProfile;

  /// Markers heard on the locked profile without a single good frame before
  /// the lock is abandoned and all profiles are tried again. Unlocking costs
  /// only CPU — the locked profile is among those retried — so this is short.
  static const staleLockMarkers = 4;

  final _syncs = <AcousticTxProfile, AcousticFrameSync>{};
  AcousticTxProfile? _rxLocked;
  int _lockMarkersAtLastGood = 0;
  int _framesRepaired = 0;
  int _framesRejected = 0;
  final _decoders = <int, LtDecoder>{};
  final _done = <int>{};
  final _ready = <Uint8List>[];
  int? _lastEnvelopeCrc;
  AcousticRxProgress _progress = AcousticRxProgress.idle;

  bool _txActive = false;
  int _txSymbolsSent = 0;
  int _txSymbolsNeeded = 0;

  AcousticTxProfile get profile => _profile;

  AcousticRxProgress get progress => _progress;

  bool get transmitting => _txActive;

  int get txSymbolsSent => _txSymbolsSent;

  int get txSymbolsNeeded => _txSymbolsNeeded;

  /// Profile the receiver is currently locked to, or null while it is still
  /// listening for all of them.
  AcousticTxProfile? get rxProfile =>
      autoDetectProfile ? _rxLocked : (_syncs.isEmpty ? null : _profile);

  /// Sets the transmit profile. Without [autoDetectProfile] it is also the
  /// only profile the receiver hears, so the receiver restarts and partial
  /// frames for the old settings are dropped.
  set profile(AcousticTxProfile value) {
    if (value == _profile) return;
    _profile = value;
    if (!autoDetectProfile && _syncs.isNotEmpty) startReceive();
  }

  // ---------------------------------------------------------------- receive

  void startReceive() {
    _syncs.clear();
    _listenForAll();
    _decoders.clear();
    _framesRepaired = 0;
    _framesRejected = 0;
    _progress = AcousticRxProgress.idle;
  }

  /// Keeps any listener already running, so a frame half-heard on the
  /// profile that was locked is not thrown away.
  void _listenForAll() {
    _rxLocked = null;
    final profiles =
        autoDetectProfile ? AcousticTxProfile.values : [_profile];
    for (final p in profiles) {
      _syncs.putIfAbsent(p, () => AcousticFrameSync(profile: p));
    }
  }

  void _lockTo(AcousticTxProfile profile) {
    final sync = _syncs[profile]!;
    _syncs
      ..clear()
      ..[profile] = sync;
    _rxLocked = profile;
    _lockMarkersAtLastGood = sync.markersFound;
    _logger.info('Acoustic receiver locked to ${profile.label}');
  }

  void stopReceive() {
    _syncs.clear();
    _rxLocked = null;
    _decoders.clear();
  }

  /// Feed captured audio. Cheap enough for the microphone callback: each
  /// sample region is probed once and then released.
  void addSamples(Float32List samples) {
    if (_syncs.isEmpty) return;

    final frames = <AcousticFrame>[];
    AcousticTxProfile? heard;
    for (final entry in _syncs.entries.toList()) {
      final sync = entry.value;
      final rejectedBefore = sync.framesRejected;
      sync.addSamples(samples);
      final got = sync.takeFrames();
      if (got.isNotEmpty) {
        frames.addAll(got);
        _lockMarkersAtLastGood = sync.markersFound;
        // The sender plays on after we finish; its leftovers must not lock.
        if (got.any((f) => !_done.contains(f.sessionId))) heard ??= entry.key;
      }
      // While hunting, every wrong profile "rejects" each frame, which would
      // make the damage counter meaningless; only count once locked.
      if (_syncs.length == 1) {
        _framesRejected += sync.framesRejected - rejectedBefore;
      }
    }
    _framesRepaired += frames.length;

    if (autoDetectProfile) {
      if (_rxLocked == null && heard != null) {
        _lockTo(heard);
      } else if (_rxLocked != null &&
          _syncs[_rxLocked]!.markersFound - _lockMarkersAtLastGood >=
              staleLockMarkers) {
        _logger.info('Acoustic lock on ${_rxLocked!.label} went stale');
        _listenForAll();
      }
    }

    for (final frame in frames) {
      if (_done.contains(frame.sessionId)) continue;
      final decoder = _decoders.putIfAbsent(
        frame.sessionId,
        () {
          _logger.info('Acoustic session ${frame.sessionId}: '
              '${frame.fileLen} B in ${frame.k} blocks');
          return LtDecoder(
            K: frame.k,
            blockLen: frame.blockLen,
            fileLen: frame.fileLen,
            sessionId: frame.sessionId,
          );
        },
      );
      decoder.addSymbol(frame.symbolIndex, frame.payload);

      final bytes = decoder.takeBytes();
      if (bytes != null) {
        _done.add(frame.sessionId);
        _decoders.remove(frame.sessionId);
        final crc = computeCrc32(bytes);
        if (_lastEnvelopeCrc != crc) {
          _lastEnvelopeCrc = crc;
          _ready.add(bytes);
          _logger.info('Acoustic envelope complete (${bytes.length} B)');
        }
        // The next message may come at a different speed.
        if (autoDetectProfile && _decoders.isEmpty) _listenForAll();
      }
    }

    _refreshProgress();
  }

  void _refreshProgress() {
    LtDecoder? leading;
    for (final decoder in _decoders.values) {
      if (leading == null || decoder.recoveredCount > leading.recoveredCount) {
        leading = decoder;
      }
    }
    _progress = AcousticRxProgress(
      collected: leading?.recoveredCount ?? 0,
      needed: leading?.K ?? 0,
      framesRepaired: _framesRepaired,
      framesRejected: _framesRejected,
      complete: leading == null && _ready.isNotEmpty,
    );
  }

  List<Uint8List> takeEnvelopes() {
    if (_ready.isEmpty) return const [];
    final batch = List<Uint8List>.from(_ready);
    _ready.clear();
    return batch;
  }

  void clearReceiveCaches({bool resetDedup = false}) {
    for (final sync in _syncs.values) {
      sync.reset();
    }
    _decoders.clear();
    _ready.clear();
    if (resetDedup) {
      _lastEnvelopeCrc = null;
      _done.clear();
    }
  }

  // --------------------------------------------------------------- transmit

  /// Play [envelope] as a rateless stream of fountain symbols.
  ///
  /// Audio is handed over in short bursts rather than one long clip so that
  /// stopping is responsive; the gap between bursts costs a little time but
  /// nothing else, because every frame carries its own sync burst and is
  /// decoded independently.
  ///
  /// There is no back channel, so the sender cannot know when the receiver is
  /// done: it keeps minting fresh symbols until cancelled, until
  /// [shouldContinue] says stop, or until [maxSymbols] (default [symbolBudget])
  /// runs out. A fixed count would strand a receiver that lost a burst of
  /// frames to a door slam just short of the finish.
  ///
  /// [onBurst], if given, receives each burst's [ToneTimeline] just before
  /// that burst is handed to [play].
  Future<void> transmit({
    required Uint8List envelope,
    required Future<void> Function(Uint8List wav) play,
    bool Function()? shouldContinue,
    void Function(int sent, int needed)? onProgress,
    void Function(ToneTimeline tones)? onBurst,
    int? maxSymbols,
  }) async {
    final codec = _profile.buildCodec();
    final frameCodec = _profile.buildFrameCodec();
    final encoder = LtEncoder(
      data: envelope,
      blockLen: _profile.blockLen,
      sessionId: _newSessionId(),
    );

    // What a receiver typically needs, for the progress bar only.
    final needed = expectedSymbols(encoder.K);
    final limit = maxSymbols ?? symbolBudget(encoder.K);
    _txActive = true;
    _txSymbolsSent = 0;
    _txSymbolsNeeded = needed;

    final burst = math.max(2, math.min(4, encoder.K));
    var index = 0;

    try {
      while (_txActive && index < limit) {
        if (shouldContinue != null && !shouldContinue()) break;
        final count = math.min(burst, limit - index);
        final tones = onBurst == null
            ? null
            : ToneTimeline(sampleRate: codec.sampleRate);
        final wav = pcmToWav(
          _renderBurst(
            codec: codec,
            frameCodec: frameCodec,
            encoder: encoder,
            firstSymbol: index,
            count: count,
            tones: tones,
          ),
        );
        if (tones != null) onBurst!(tones);
        await play(wav);
        index += count;
        _txSymbolsSent = index;
        onProgress?.call(index, needed);
      }
    } finally {
      _txActive = false;
    }

    _logger.info('Acoustic TX done: $index symbols for ${envelope.length} B '
        'at ${_profile.label}');
  }

  void cancelTransmit() => _txActive = false;

  /// Modulate a run of fresh fountain symbols into one waveform.
  Float32List _renderBurst({
    required MtFskCodec codec,
    required AcousticFrameCodec frameCodec,
    required LtEncoder encoder,
    required int firstSymbol,
    required int count,
    ToneTimeline? tones,
  }) {
    // A little silence up front lets the output stream settle before the
    // first sync burst, which would otherwise be clipped by fade-in; a
    // shorter tail keeps players that trim the last buffer off the data.
    final lead = (codec.sampleRate * 0.12).round();
    final tail = (codec.sampleRate * 0.04).round();

    tones?.addSilence(lead);
    final chunks = <Float32List>[];
    for (var i = 0; i < count; i++) {
      final symbolIndex = firstSymbol + i;
      final codeword = frameCodec.encode(
        AcousticFrame(
          sessionId: encoder.sessionId & 0xFF,
          symbolIndex: symbolIndex,
          k: encoder.K,
          blockLen: encoder.blockLen,
          fileLen: encoder.fileLen,
          payload: encoder.symbolAt(symbolIndex),
        ),
      );
      chunks.add(codec.encode(codeword));
      if (tones != null) codec.describe(codeword, tones);
    }
    tones?.addSilence(tail);

    final total = chunks.fold<int>(lead + tail, (a, c) => a + c.length);
    final out = Float32List(total);
    var offset = lead;
    for (final chunk in chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    applyEdgeFades(out, lead, offset);
    return out;
  }

  /// Raised-cosine ramps over the first and last [fadeSamples] of
  /// `samples[start, end)`. Tones are phase-continuous inside a burst, so its
  /// two edges are the only places a hard step could click — and a click is
  /// broadband, audible even when the tone that caused it is not.
  static void applyEdgeFades(
    Float32List samples,
    int start,
    int end, {
    int fadeSamples = 256,
  }) {
    final n = math.min(fadeSamples, (end - start) ~/ 2);
    for (var i = 0; i < n; i++) {
      final gain = 0.5 - 0.5 * math.cos(math.pi * i / n);
      samples[start + i] *= gain;
      samples[end - 1 - i] *= gain;
    }
  }

  int _newSessionId() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 97) & 0xFF;

  /// Symbols a receiver in an ordinary room usually needs: the fountain's own
  /// ~15% overhead plus some frames lost to noise.
  static int expectedSymbols(int k) => (k * 1.25).ceil() + 2;

  /// Hard stop for an unattended sender: enough for a receiver losing most
  /// frames to still finish, short enough not to play forever.
  static int symbolBudget(int k) => math.max(k * 6, k + 24);

  /// Rough wall-clock estimate for the sender's UI.
  double estimateSeconds(int envelopeBytes) {
    final k = (envelopeBytes / _profile.blockLen).ceil();
    return expectedSymbols(k) * _profile.frameSeconds();
  }
}

/// Convert interleaved little-endian PCM16 to normalised floats.
///
/// Shared by the acoustic receive paths; building a `List<double>` per chunk
/// showed up as avoidable allocation in the microphone callback.
Float32List pcm16ToFloat32(Uint8List chunk) {
  final count = chunk.length ~/ 2;
  final out = Float32List(count);
  final view = ByteData.sublistView(chunk, 0, count * 2);
  for (var i = 0; i < count; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
