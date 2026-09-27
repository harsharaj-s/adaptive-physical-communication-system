import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/mt_fsk_codec.dart';

/// Speed and robustness settings for data over sound.
///
/// Tone count and symbol length are the two levers. More simultaneous tones
/// carry more bits but split the available power; longer symbols average out
/// reverberation. Parity is then sized against the byte error rate those
/// choices produce — see test/acoustic_channel_test.dart for the measurements
/// these numbers come from.
class AcousticTxProfile {
  const AcousticTxProfile({
    required this.id,
    required this.label,
    required this.groups,
    required this.framesPerSymbol,
    required this.blockLen,
    required this.parityBytes,
  });

  final String id;
  final String label;

  /// Simultaneous tones, each carrying one nibble.
  final int groups;

  /// Analysis frames per symbol; longer is more reverberation-tolerant.
  final int framesPerSymbol;

  /// Fountain payload bytes per frame.
  final int blockLen;

  /// Reed-Solomon parity bytes per frame.
  final int parityBytes;

  MtFskCodec buildCodec() => MtFskCodec(
        groups: groups,
        framesPerSymbol: framesPerSymbol,
      );

  AcousticFrameCodec buildFrameCodec() =>
      AcousticFrameCodec(parityBytes: parityBytes);

  int get codewordLength =>
      acousticFrameOverhead + blockLen + parityBytes;

  /// Payload bytes per second once markers, header, CRC and parity are paid
  /// for. This is the number a user actually experiences.
  double netBytesPerSecond() {
    final codec = buildCodec();
    final symbols = codec.symbolsForBytes(codewordLength);
    final samples = codec.samplesPerMarker + symbols * codec.samplesPerSymbol;
    return blockLen * codec.sampleRate / samples;
  }

  /// Seconds of audio one frame occupies.
  double frameSeconds() {
    final codec = buildCodec();
    final symbols = codec.symbolsForBytes(codewordLength);
    return (codec.samplesPerMarker + symbols * codec.samplesPerSymbol) /
        codec.sampleRate;
  }

  /// Human-readable hint about where this setting belongs.
  String get conditionHint => switch (id) {
        'rugged' => 'Loud room, phones metres apart',
        'safe' => 'Background noise or chatter',
        'fast' => 'Quiet room, phones touching',
        _ => 'Normal room, across a table',
      };

  /// Long symbols, few tones. Slowest, and in measurement the only setting
  /// that still lands frames when the room is loud and the two sample clocks
  /// are badly mismatched.
  static const rugged = AcousticTxProfile(
    id: 'rugged',
    label: 'Rugged',
    groups: 6,
    framesPerSymbol: 6,
    blockLen: 32,
    parityBytes: 20,
  );

  /// Six tones keep the whole band low, where speaker and microphone response
  /// is flattest; that is what carries it through background noise.
  static const safe = AcousticTxProfile(
    id: 'safe',
    label: 'Safe',
    groups: 6,
    framesPerSymbol: 4,
    blockLen: 48,
    parityBytes: 24,
  );

  /// Best measured throughput in an ordinary room. Eight tones with enough
  /// symbol length to ride out reverberation.
  static const standard = AcousticTxProfile(
    id: 'standard',
    label: 'Standard',
    groups: 8,
    framesPerSymbol: 4,
    blockLen: 64,
    parityBytes: 24,
  );

  /// Shorter symbols push the raw rate higher but give reverberation less time
  /// to decay, so this only pays off when the devices are close and quiet.
  static const fast = AcousticTxProfile(
    id: 'fast',
    label: 'Fast',
    groups: 8,
    framesPerSymbol: 3,
    blockLen: 64,
    parityBytes: 24,
  );

  /// Ordered slowest to fastest so [slower] walks the backoff ladder.
  static const values = [rugged, safe, standard, fast];

  static AcousticTxProfile byId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => standard);

  AcousticTxProfile get slower {
    final i = values.indexOf(this);
    return i <= 0 ? rugged : values[i - 1];
  }

  @override
  bool operator ==(Object other) =>
      other is AcousticTxProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
