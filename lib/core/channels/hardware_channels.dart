import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:adaptive_physical_communication/core/channels/comm_channel.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_modem.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/hardware_phy_config.dart';
import 'package:adaptive_physical_communication/core/physical/physical_codecs.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_receiver_state.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_transmitter_state.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

export 'vibration_channel.dart';
export 'hardware_optical_channel.dart';

/// Which sound modem the channel runs.
enum AcousticModemKind {
  /// Multi-tone FSK with Reed-Solomon frames and fountain coding. Several
  /// times faster than the original tones and the only one that recovers
  /// timing per frame, so microphone chunk boundaries no longer matter.
  fountain,

  /// The original two-tone FSK with whole-message repeats. Kept because it is
  /// the simplest thing that works and is useful for demonstrating the
  /// difference.
  legacyFsk,
}

/// Hardware acoustic channel using FSK tones (speaker TX, microphone RX).
class HardwareAcousticChannel implements CommChannel {
  HardwareAcousticChannel({StructuredLogger? logger})
      : _logger = logger ?? StructuredLogger();

  final StructuredLogger _logger;
  final _codec = FskCodec(symbolDurationMs: hardwareAcousticSymbolMs);
  late final FskStreamDecoder _decoder = FskStreamDecoder(codec: _codec);
  late final AcousticFountainModem _modem =
      AcousticFountainModem(logger: _logger);
  AcousticModemKind _modemKind = AcousticModemKind.fountain;
  final _audioPlayer = AudioPlayer();
  final _recorder = AudioRecorder();
  final _receiveBuffer = <DecodedPacket>[];
  final _envelopeBuffer = <Uint8List>[];
  int? _lastDeliveredEnvelopeCrc;
  bool _running = false;
  bool _micActive = false;
  int _packetsSent = 0;
  int _packetsReceived = 0;
  double _noiseLevel = 0;
  StreamSubscription<Uint8List>? _recordSub;
  int _lastRxUiUpdateMs = 0;

  bool get micStreaming => _micActive;

  AcousticModemKind get modemKind => _modemKind;

  set modemKind(AcousticModemKind value) {
    if (_modemKind == value) return;
    _modemKind = value;
    if (_micActive) _resetDecoders();
  }

  AcousticTxProfile get txProfile => _modem.profile;

  set txProfile(AcousticTxProfile value) => _modem.profile = value;

  AcousticRxProgress get rxProgress => _modem.progress;

  /// Largest envelope the current settings will carry in a sensible time.
  int get maxEnvelopeBytes => _modemKind == AcousticModemKind.fountain
      ? acousticFountainMaxBytes
      : hardwareAcousticDirectMaxBytes;

  void _resetDecoders() {
    if (_modemKind == AcousticModemKind.fountain) {
      _modem.startReceive();
    } else {
      _decoder.reset();
    }
  }

  @override
  CommChannelId get id => CommChannelId.acoustic;

  @override
  ChannelCapabilities get capabilities => const ChannelCapabilities(
        channelId: CommChannelId.acoustic,
        name: 'Acoustic (Hardware)',
        maxThroughput: 4000,
        minLatency: 200,
        supportsBinary: true,
        hardwareImplemented: true,
      );

  @override
  Future<void> initialize({bool setupCamera = true}) async {
    if (!isPhysicalChannelSupported) return;
    if (!kIsWeb) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) _logger.warning('Microphone permission denied');
    }
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer.setVolume(1.0);
    if (!kIsWeb) {
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.voiceCommunication,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
            },
          ),
        ),
      );
    }
  }

  @override
  Future<void> start({bool enableReceiver = true}) async {
    if (!isPhysicalChannelSupported) return;
    _running = true;
    if (!enableReceiver) {
      await _stopMic();
      acousticReceiverState.reset();
      return;
    }
    if (_micActive) {
      acousticReceiverState.setPhase(AcousticRxPhase.listening);
      return;
    }

    acousticReceiverState.setPhase(AcousticRxPhase.starting);
    if (!kIsWeb) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _logger.warning('Microphone permission not granted');
        acousticReceiverState.setPhase(AcousticRxPhase.permissionDenied);
        return;
      }
    }
    if (!await _recorder.hasPermission()) {
      _logger.warning('Microphone permission not granted');
      acousticReceiverState.setPhase(AcousticRxPhase.permissionDenied);
      return;
    }

    try {
      final stream = await _recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        androidConfig: const AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceCommunication,
        ),
      ));
      _micActive = true;
      _decoder.reset();
      _resetDecoders();
      _recordSub = stream.listen(_processAudioChunk);
      acousticReceiverState.setPhase(AcousticRxPhase.listening);
      _logger.info('Acoustic mic stream started');
    } catch (e) {
      _logger.warning('Failed to start mic stream: $e');
      acousticReceiverState.setPhase(AcousticRxPhase.permissionDenied);
    }
  }

  void _processAudioChunk(Uint8List chunk) {
    if (!_running || chunk.length < 2) return;
    final frames = pcm16ToFloat32(chunk);
    if (frames.isEmpty) return;

    var sumSq = 0.0;
    for (final sample in frames) {
      sumSq += sample * sample;
    }
    final rms = math.sqrt(sumSq / frames.length);
    _noiseLevel = rms;

    if (_modemKind == AcousticModemKind.fountain) {
      _processFountainChunk(frames, rms);
      return;
    }

    final samples = List<double>.of(frames);
    final n = _codec.samplesPerSymbol;
    var tone = 0.0;
    if (samples.length >= n) {
      tone = _codec.combinedToneStrength(samples.sublist(samples.length - n));
    }

    _decoder.addSamples(samples);
    final toneFromBuffer = _decoder.peekToneStrength();
    tone = math.max(tone, toneFromBuffer);

    _updateRxUi(rms: rms, tone: tone);

    final direct = _decoder.pollDirectEnvelope(
      maxPayloadBytes: hardwareAcousticDirectMaxBytes,
    );
    if (direct != null) {
      final crc = computeCrc32(direct);
      if (_lastDeliveredEnvelopeCrc != crc) {
        _lastDeliveredEnvelopeCrc = crc;
        _envelopeBuffer.add(direct);
        _packetsReceived++;
        acousticReceiverState.markDecoded();
        _logger.info('Acoustic decoded envelope (${direct.length} B)');
      }
      return;
    }

    final bytes = _decoder.pollPacket();
    if (bytes == null || bytes.isEmpty) return;
    final packet = packetCodec.decode(bytes);
    if (packet != null) {
      _receiveBuffer.add(packet);
      _packetsReceived++;
      acousticReceiverState.markDecoded();
      _logger.info('Acoustic decoded packet (${packet.packetType.name})');
    }
  }

  void _processFountainChunk(Float32List frames, double rms) {
    _modem.addSamples(frames);
    final progress = _modem.progress;

    // Frames landing is a far better "we can hear the sender" signal than
    // raw tone energy, so drive the meter from it when a transfer is live.
    final tone = progress.active
        ? (0.35 + 0.65 * progress.fraction)
        : (rms * 12).clamp(0.0, 1.0);
    _updateRxUi(rms: rms, tone: tone);
    acousticReceiverState.setFountainProgress(
      collected: progress.collected,
      needed: progress.needed,
      framesRepaired: progress.framesRepaired,
      framesRejected: progress.framesRejected,
      profileLabel: _modem.rxProfile?.label ?? '',
    );

    for (final envelope in _modem.takeEnvelopes()) {
      _envelopeBuffer.add(envelope);
      _packetsReceived++;
      acousticReceiverState.markDecoded();
    }
  }

  void _updateRxUi({required double rms, required double tone}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRxUiUpdateMs != 0 && now - _lastRxUiUpdateMs < 80) return;
    _lastRxUiUpdateMs = now;

    final input = (rms * 12).clamp(0.0, 1.0);
    final toneLevel = tone.clamp(0.0, 1.0);
    acousticReceiverState.setLevels(input: input, tone: toneLevel);

    if (toneLevel > 0.12 &&
        acousticReceiverState.phase == AcousticRxPhase.listening) {
      acousticReceiverState.setPhase(AcousticRxPhase.tonesDetected);
    } else if (toneLevel <= 0.08 &&
        acousticReceiverState.phase == AcousticRxPhase.tonesDetected) {
      acousticReceiverState.setPhase(AcousticRxPhase.listening);
    } else if (toneLevel <= 0.08 &&
        acousticReceiverState.phase == AcousticRxPhase.decoded &&
        _micActive) {
      acousticReceiverState.setPhase(AcousticRxPhase.listening);
    }
  }

  /// Send a chat envelope over whichever sound modem is selected.
  Future<void> transmitEnvelope(Uint8List envelope) async {
    if (!_running) throw StateError('Acoustic channel not running');
    if (envelope.length > maxEnvelopeBytes) {
      throw ArgumentError('Envelope too large for the acoustic channel');
    }

    if (_modemKind == AcousticModemKind.fountain) {
      await _transmitFountain(envelope);
      return;
    }

    await _stopMic();
    final framed = frameDirectEnvelope(envelope);
    final tones = _codec.encodeBytes(framed);
    final leadSamples = (44100 * hardwareAcousticLeadSilenceMs / 1000).round();
    final combined = Float32List(leadSamples + tones.length);
    combined.setRange(leadSamples, combined.length, tones);
    final wav = pcmToWav(combined);

    for (var round = 0; round < hardwareAcousticTxRepeatCount; round++) {
      await _audioPlayer.play(BytesSource(wav));
      await _audioPlayer.onPlayerComplete.first;
      if (round + 1 < hardwareAcousticTxRepeatCount) {
        await Future<void>.delayed(
          const Duration(milliseconds: hardwareAcousticTxRepeatGapMs),
        );
      }
    }
    _packetsSent++;
    _logger.info('Acoustic TX envelope (${envelope.length} B, '
        '$hardwareAcousticTxRepeatCount×)');
  }

  Future<void> _transmitFountain(Uint8List envelope) async {
    // The microphone has to go quiet: the recorder holds the audio session in
    // voice-communication mode, which ducks our own playback.
    await _stopMic();
    acousticTransmitterState.beginAcoustic(
      totalBytes: envelope.length,
      profileLabel: _modem.profile.label,
      estimateSeconds: _modem.estimateSeconds(envelope.length),
    );

    try {
      await _modem.transmit(
        envelope: envelope,
        play: (wav) async {
          await _audioPlayer.play(BytesSource(wav));
          await _audioPlayer.onPlayerComplete.first;
        },
        shouldContinue: () => _running,
        onProgress: acousticTransmitterState.setAcousticProgress,
      );
      _packetsSent++;
    } finally {
      acousticTransmitterState.endAcoustic();
    }
  }

  /// Stop a rateless sound transmission early.
  void cancelTransmit() => _modem.cancelTransmit();

  Future<List<Uint8List>> receiveEnvelopes() async {
    final batch = List<Uint8List>.from(_envelopeBuffer);
    _envelopeBuffer.clear();
    return batch;
  }

  void clearReceiveCaches({bool resetDedup = false}) {
    _decoder.reset();
    _modem.clearReceiveCaches(resetDedup: resetDedup);
    _receiveBuffer.clear();
    _envelopeBuffer.clear();
    if (resetDedup) _lastDeliveredEnvelopeCrc = null;
    if (_micActive) {
      acousticReceiverState.setPhase(AcousticRxPhase.listening);
    }
  }

  Future<void> _stopMic() async {
    await _recordSub?.cancel();
    _recordSub = null;
    _decoder.reset();
    _modem.stopReceive();
    _lastRxUiUpdateMs = 0;
    if (_micActive) {
      _micActive = false;
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _stopMic();
    await _audioPlayer.stop();
    acousticReceiverState.reset(keepDecodeCount: true);
  }

  @override
  Future<bool> discover(int timeoutMs) async {
    if (!isPhysicalChannelSupported) return false;
    final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      if (_receiveBuffer.isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  @override
  Future<ChannelTestResult> test(int testPacketCount) async {
    var received = 0;
    for (var i = 0; i < testPacketCount; i++) {
      if (_noiseLevel > 0.005) received++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return ChannelTestResult(
      channel: id,
      packetsSent: testPacketCount,
      packetsReceived: received,
      packetLossRate: (testPacketCount - received) / testPacketCount,
      throughput: 4000 * (received / testPacketCount),
      latency: 200,
      confidence: (_noiseLevel * 10).clamp(0, 1),
      stability: 0.7,
    );
  }

  @override
  Future<void> transmit(Uint8List packet) async {
    if (!_running) throw StateError('Acoustic channel not running');
    if (!isPhysicalChannelSupported) {
      _logger.warning('Acoustic TX skipped — platform unsupported');
      return;
    }

    final pcm = _codec.encodeBytes(packet);
    final wav = pcmToWav(pcm);
    await _audioPlayer.play(BytesSource(wav));
    await _audioPlayer.onPlayerComplete.first;
    _packetsSent++;
  }

  @override
  Future<List<DecodedPacket>> receive() async {
    final batch = List<DecodedPacket>.from(_receiveBuffer);
    _receiveBuffer.clear();
    return batch;
  }

  @override
  ChannelMetrics getMetrics() {
    final loss = _packetsSent > 0
        ? (_packetsSent - _packetsReceived) / _packetsSent
        : 0.08;
    return ChannelMetrics(
      throughput: 4000 * (1 - loss),
      packetLoss: loss.clamp(0, 1),
      latency: 200,
      reliability: (1 - loss).clamp(0, 1),
      errorRate: loss * 0.5,
      confidence: (_noiseLevel * 10).clamp(0, 1),
      stability: 0.7,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  bool isAvailable() => _running && isPhysicalChannelSupported;

  @override
  void setTransmissionConfig(TransmissionConfig config) {}

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
    await _recorder.dispose();
  }
}
