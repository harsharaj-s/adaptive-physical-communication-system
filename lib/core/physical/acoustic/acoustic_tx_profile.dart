import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_frame.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/mt_fsk_codec.dart';

/// Where in the spectrum a sound profile lives.
///
/// Both bands share the frame format, Reed-Solomon and the fountain code;
/// only the tone plan differs, so a receiver can listen to both at once.
enum AcousticBand {
  /// 1.2–7.2 kHz chords. Every phone reproduces it, and it is loud.
  audible(
    label: 'Audible',
    baseBin: 40,
    toneSpacing: 1,
    syncBinA: 28,
    syncBinB: 36,
    sequentialMarker: false,
    peakAmplitude: 0.98,
    receiveHighPassHz: null,
  ),

  /// 18.3–19.9 kHz, one tone at a time. Above most adults' hearing and above
  /// nearly all room noise — speech, music and fans sit below 8 kHz — so it
  /// is quiet to people and clean to the microphone. Android's CDD defines
  /// near-ultrasound support around 18.5–20 kHz, which is why the plan sits
  /// here; phones that lack it simply never hear these profiles.
  nearUltrasonic(
    label: 'Silent',
    baseBin: 431,
    toneSpacing: 2,
    syncBinA: 424,
    syncBinB: 427,
    sequentialMarker: true,
    peakAmplitude: 0.8,
    receiveHighPassHz: 16000,
  );

  const AcousticBand({
    required this.label,
    required this.baseBin,
    required this.toneSpacing,
    required this.syncBinA,
    required this.syncBinB,
    required this.sequentialMarker,
    required this.peakAmplitude,
    required this.receiveHighPassHz,
  });

  final String label;
  final int baseBin;
  final int toneSpacing;
  final int syncBinA;
  final int syncBinB;
  final bool sequentialMarker;
  final double peakAmplitude;

  /// Microphone audio is high-passed here before sync, or null for none.
  final double? receiveHighPassHz;
}

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
    this.band = AcousticBand.audible,
    this.guardFrames = 0,
  });

  final String id;
  final String label;
  final AcousticBand band;

  /// Simultaneous tones, each carrying one nibble.
  final int groups;

  /// Analysis frames per symbol; longer is more reverberation-tolerant.
  final int framesPerSymbol;

  /// Leading frames of each symbol ignored by the demodulator (echo guard).
  final int guardFrames;

  /// Fountain payload bytes per frame.
  final int blockLen;

  /// Reed-Solomon parity bytes per frame.
  final int parityBytes;

  bool get isSilent => band == AcousticBand.nearUltrasonic;

  MtFskCodec buildCodec() => MtFskCodec(
        groups: groups,
        framesPerSymbol: framesPerSymbol,
        guardFrames: guardFrames,
        baseBin: band.baseBin,
        toneSpacing: band.toneSpacing,
        syncBinA: band.syncBinA,
        syncBinB: band.syncBinB,
        sequentialMarker: band.sequentialMarker,
        peakAmplitude: band.peakAmplitude,
      );

  AcousticFrameCodec buildFrameCodec() =>
      AcousticFrameCodec(parityBytes: parityBytes);

  int get codewordLength =>
      acousticFrameOverhead + blockLen + parityBytes;

  /// Payload bytes per second once markers, header, CRC and parity are paid
  /// for. This is the number a user actually experiences.
  double netBytesPerSecond() => blockLen / frameSeconds();

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
        'silent' => 'Inaudible 18–20 kHz, phones within arm\'s reach',
        'silent_robust' => 'Inaudible, weak speaker or a loud crowd',
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

  /// One 16-ary tone per 46 ms symbol in 18.3–19.9 kHz. The first 23 ms of
  /// each symbol is an echo guard, so the decision is made after the previous
  /// tone's reflections have died away; in simulation the guard alone lifted
  /// hand-held frame recovery from 2/18 to 16/18. A short block keeps a
  /// one-line text to a single ~4.8 s frame.
  static const silent = AcousticTxProfile(
    id: 'silent',
    label: 'Silent',
    band: AcousticBand.nearUltrasonic,
    groups: 1,
    framesPerSymbol: 2,
    guardFrames: 1,
    blockLen: 24,
    parityBytes: 16,
  );

  /// 70 ms symbols with the same guard, so each decision integrates twice the
  /// energy. For weak speakers, longer distances and loud crowds.
  static const silentRobust = AcousticTxProfile(
    id: 'silent_robust',
    label: 'Silent Robust',
    band: AcousticBand.nearUltrasonic,
    groups: 1,
    framesPerSymbol: 3,
    guardFrames: 1,
    blockLen: 24,
    parityBytes: 16,
  );

  /// Audible ladder, slowest to fastest, so [slower] walks the backoff.
  static const audibleValues = [rugged, safe, standard, fast];

  /// Silent ladder, slowest to fastest.
  static const silentValues = [silentRobust, silent];

  /// Every profile a receiver listens for.
  static const values = [...audibleValues, ...silentValues];

  static List<AcousticTxProfile> forBand(AcousticBand band) =>
      band == AcousticBand.audible ? audibleValues : silentValues;

  static AcousticTxProfile byId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => standard);

  /// Default profile when the user switches to [band].
  static AcousticTxProfile defaultFor(AcousticBand band) =>
      band == AcousticBand.audible ? standard : silent;

  /// One step down this profile's own band; never crosses bands, because a
  /// phone that cannot hear 19 kHz is not helped by a slower 19 kHz.
  AcousticTxProfile get slower {
    final ladder = forBand(band);
    final i = ladder.indexOf(this);
    return i <= 0 ? ladder.first : ladder[i - 1];
  }

  @override
  bool operator ==(Object other) =>
      other is AcousticTxProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
