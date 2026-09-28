import 'dart:math' as math;
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/biquad_filter.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/mt_fsk_codec.dart';

/// Streaming receiver: finds frame markers in microphone audio and
/// demodulates the codeword that follows each one.
///
/// Every frame carries its own sync burst, so alignment is re-acquired from
/// scratch each time. That matters because the previous decoder assumed symbol
/// boundaries fell on exact multiples of the symbol length from the start of
/// its buffer — microphone chunks arrive at arbitrary offsets, so its analysis
/// windows straddled two tones and demodulated to noise.
///
/// Sample regions are probed once and then released, which keeps the cost
/// proportional to the audio arriving rather than to the buffer length.
class AcousticFrameSync {
  AcousticFrameSync({
    required this.profile,
    this.markerThreshold = 8.0,
    this.searchStep = 64,
  })  : _codec = profile.buildCodec(),
        _frameCodec = profile.buildFrameCodec(),
        _highPass = profile.band.receiveHighPassHz == null
            ? null
            : HighPassFilter(cutoffHz: profile.band.receiveHighPassHz!);

  final AcousticTxProfile profile;
  final HighPassFilter? _highPass;

  /// Minimum normalised sync-tone score to treat a frame as present. Aligned
  /// markers measure in the hundreds and unrelated audio in the tens, so this
  /// sits well clear of both.
  final double markerThreshold;

  /// Marker hunt resolution in samples. 64 at 44.1 kHz is 1.45 ms, comfortably
  /// under 2% of a symbol.
  final int searchStep;

  final MtFskCodec _codec;
  final AcousticFrameCodec _frameCodec;

  Float32List _buffer = Float32List(0);
  int _length = 0;
  int _cursor = 0;
  final _ready = <AcousticFrame>[];

  /// Absolute index of _buffer[0] in the stream, so reported positions stay
  /// meaningful after the buffer is compacted.
  int _base = 0;

  int markersFound = 0;
  int framesRepaired = 0;
  int framesRejected = 0;
  double lastConfidence = 0;

  /// Stream positions of the most recent lock, for diagnostics.
  int lastMarkerSample = -1;
  int lastDataStartSample = -1;

  MtFskCodec get codec => _codec;

  int get dataSymbols => _codec.symbolsForBytes(profile.codewordLength);

  /// Samples one framed transmission occupies.
  int get frameSamples =>
      _codec.samplesPerMarker + dataSymbols * _codec.samplesPerSymbol;

  /// Feed newly captured audio.
  void addSamples(Float32List chunk) {
    if (chunk.isEmpty) return;
    final filter = _highPass;
    if (filter != null) chunk = filter.apply(chunk);
    _ensureCapacity(_length + chunk.length);
    _buffer.setRange(_length, _length + chunk.length, chunk);
    _length += chunk.length;
    _process();
    _compact();
  }

  /// Collect frames recovered since the last call.
  List<AcousticFrame> takeFrames() {
    if (_ready.isEmpty) return const [];
    final batch = List<AcousticFrame>.from(_ready);
    _ready.clear();
    return batch;
  }

  void _ensureCapacity(int needed) {
    if (_buffer.length >= needed) return;
    var capacity = _buffer.isEmpty ? 1 << 15 : _buffer.length;
    while (capacity < needed) {
      capacity <<= 1;
    }
    final grown = Float32List(capacity);
    grown.setRange(0, _length, _buffer);
    _buffer = grown;
  }

  void _process() {
    // How far refinement may move the data start. The marker lock is already
    // good to a millisecond or so, so this only has to cover reverberation
    // smearing the burst edge. Searching wider is not just wasted work: over
    // a span approaching half a symbol the confidence score can peak on the
    // wrong symbol boundary and throw the whole frame away.
    final refineSpan = math.min(_codec.samplesPerSymbol ~/ 8, 512);

    while (true) {
      final markerLimit = _length - _codec.samplesPerMarker;
      if (_cursor > markerLimit) return;

      final marker = _findMarker(_cursor, markerLimit);
      if (marker == null) {
        // Everything up to the last probe has been examined.
        _cursor = markerLimit + 1;
        return;
      }

      final coarseStart = marker + _codec.samplesPerMarker;
      final needed =
          coarseStart + dataSymbols * _codec.samplesPerSymbol + refineSpan;
      if (needed > _length) {
        // Frame is still arriving; resume from this marker next time.
        _cursor = marker;
        return;
      }

      markersFound++;
      final dataStart = _refineDataStart(coarseStart, refineSpan);
      lastMarkerSample = _base + marker;
      lastDataStartSample = _base + dataStart;
      final demodulated = _codec.decodeBytesSoft(
        _buffer,
        dataStart,
        profile.codewordLength,
      );
      lastConfidence = demodulated.confidence;

      final frame = _frameCodec.decode(
        demodulated.bytes,
        blockLen: profile.blockLen,
        reliability: demodulated.reliability,
      );
      if (frame != null) {
        framesRepaired++;
        _ready.add(frame);
      } else {
        framesRejected++;
      }

      _cursor = marker + frameSamples;
    }
  }

  /// Drop audio that has already been examined.
  void _compact() {
    if (_cursor <= 0) return;
    final keepFrom = _cursor;
    final remaining = _length - keepFrom;
    if (remaining > 0) {
      _buffer.setRange(0, remaining, _buffer, keepFrom);
    }
    _length = remaining < 0 ? 0 : remaining;
    _base += keepFrom;
    _cursor = 0;
  }

  /// Locate the onset of the next marker at or after [from].
  ///
  /// Deliberately takes the *earliest* strong offset rather than the strongest.
  /// Sound reaches the microphone by several paths and a reflection can easily
  /// score higher than the direct arrival; locking onto that peak puts every
  /// following symbol window a thousand-odd samples late, which is a large
  /// fraction of a symbol. The direct path is always first, so the leading
  /// edge is the reliable landmark.
  int? _findMarker(int from, int limit) {
    var offset = from < 0 ? 0 : from;

    while (offset <= limit) {
      if (_codec.markerScore(_buffer, offset) >= markerThreshold) {
        var peak = 0.0;
        final windowEnd =
            math.min(offset + _codec.samplesPerMarker, limit);
        for (var probe = offset; probe <= windowEnd; probe += searchStep) {
          final score = _codec.markerScore(_buffer, probe);
          if (score > peak) peak = score;
        }
        for (var probe = offset; probe <= windowEnd; probe += searchStep) {
          if (_codec.markerScore(_buffer, probe) >= peak * 0.5) return probe;
        }
        return offset;
      }
      offset += searchStep;
    }
    return null;
  }

  /// Nudge the data start to where the first symbol resolves most cleanly.
  ///
  /// The marker onset is good to a millisecond or so, but reverberation blurs
  /// the boundary between the burst and the first data symbol. Scoring actual
  /// tone separation recovers the rest, and it is exactly the quantity that
  /// demodulation depends on.
  int _refineDataStart(int coarseStart, int span) {
    const probeGroups = 3;
    var best = -1.0;
    var bestStart = coarseStart;

    for (var delta = -span; delta <= span; delta += searchStep) {
      final candidate = coarseStart + delta;
      if (candidate < 0) continue;
      if (candidate + _codec.samplesPerSymbol > _length) break;
      final score = _codec.symbolConfidence(
        _buffer,
        candidate,
        groupLimit: probeGroups,
      );
      if (score > best) {
        best = score;
        bestStart = candidate;
      }
    }
    return bestStart;
  }

  void reset() {
    _length = 0;
    _cursor = 0;
    _base = 0;
    _ready.clear();
    _highPass?.reset();
  }

  void resetStats() {
    markersFound = 0;
    framesRepaired = 0;
    framesRejected = 0;
    lastConfidence = 0;
  }
}
