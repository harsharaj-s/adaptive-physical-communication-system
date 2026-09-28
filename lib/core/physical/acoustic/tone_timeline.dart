import 'dart:typed_data';

/// What a stretch of transmitted audio is doing.
enum ToneKind { silence, marker, data }

/// Which frequencies a rendered sound burst plays, and when.
///
/// Built alongside the waveform by the same code that writes the tones, so a
/// live readout on the sender shows exactly what is on air instead of
/// re-analysing its own output.
class ToneTimeline {
  ToneTimeline({required this.sampleRate});

  final int sampleRate;
  final _ends = <int>[];
  final _kinds = <ToneKind>[];
  final _tones = <Float32List>[];

  static final _none = Float32List(0);

  int get totalSamples => _ends.isEmpty ? 0 : _ends.last;

  Duration get duration =>
      Duration(microseconds: totalSamples * 1000000 ~/ sampleRate);

  int get segmentCount => _ends.length;

  void addSilence(int samples) => _add(samples, ToneKind.silence, _none);

  void addTones(int samples, ToneKind kind, List<double> hz) =>
      _add(samples, kind, Float32List.fromList(hz));

  void _add(int samples, ToneKind kind, Float32List hz) {
    if (samples <= 0) return;
    final last = _ends.length - 1;
    // Consecutive silences merge, so a padded burst stays a short list.
    if (kind == ToneKind.silence && last >= 0 && _kinds[last] == kind) {
      _ends[last] += samples;
      return;
    }
    _ends.add(totalSamples + samples);
    _kinds.add(kind);
    _tones.add(hz);
  }

  /// Segment playing at [sample], or null past the end.
  ({ToneKind kind, Float32List hz})? at(int sample) {
    if (sample < 0 || sample >= totalSamples) return null;
    var lo = 0;
    var hi = _ends.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_ends[mid] > sample) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return (kind: _kinds[lo], hz: _tones[lo]);
  }

  ({ToneKind kind, Float32List hz})? atTime(Duration elapsed) =>
      at(elapsed.inMicroseconds * sampleRate ~/ 1000000);
}
