# API Reference: `lib/core`, `lib/application` and `lib/main.dart`

This is the developer reference for every non-UI Dart file in the Adaptive Physical Communication System. For each file it gives the purpose, the public classes, enums, functions and constants with their signatures, what they do, what they throw, their side effects and who calls them. Every number in this document is copied from the source code. If you ever find a difference, the code is correct and this document should be fixed. The Flutter screens and widgets under `lib/ui/` are covered separately in the [UI Guide](./UI_GUIDE.md).

Back to the [documentation index](../README.md).

---

## Contents

1. [How to read this reference](#1-how-to-read-this-reference)
2. [Module dependency map](#2-module-dependency-map)
3. [chat module](#3-chat-module)
4. [channels module](#4-channels-module)
5. [engine module](#5-engine-module)
6. [logging module](#6-logging-module)
7. [manager module](#7-manager-module)
8. [media module](#8-media-module)
9. [performance module](#9-performance-module)
10. [physical module (shared files)](#10-physical-module-shared-files)
11. [physical/fountain module](#11-physicalfountain-module)
12. [physical/acoustic module](#12-physicalacoustic-module)
13. [physical/csk module](#13-physicalcsk-module)
14. [platform module](#14-platform-module)
15. [protocol module](#15-protocol-module)
16. [simulation module](#16-simulation-module)
17. [transport module](#17-transport-module)
18. [types module](#18-types-module)
19. [application module (AppController)](#19-application-module-appcontroller)
20. [App shell (main.dart)](#20-app-shell-maindart)
21. [Threading and isolates](#21-threading-and-isolates)
22. [Extension points](#22-extension-points)
23. [Related documents](#23-related-documents)

---

## 1. How to read this reference

- **Package name.** All imports use `package:adaptive_physical_communication/...`. For example, the LT codec is imported with `import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';`.
- **Signatures only.** The ```dart blocks show declarations without bodies. Private members (names starting with `_`) are mentioned only when they explain behaviour you will observe.
- **Byte order.** Light (APCF) and Sound frames are big-endian. Protocol packets are little-endian. See [Data Formats](../architecture/DATA_FORMATS.md).
- **Singletons.** Several UI-state notifiers are top-level `final` globals (for example `opticalTransmitterState`). They are listed in the file where they are declared.
- **"Direct envelope path" and "protocol path".** Light and Sound normally hand a whole APCM envelope to a rateless fountain modem (the direct path). Vibration, and Sound messages larger than 8 KiB, go through packets, `ReliableTransport` and `TransferManager` (the protocol path). See [Architecture](../architecture/ARCHITECTURE.md).

---

## 2. Module dependency map

The arrows point from a module to the modules it imports. Only project-internal imports are shown.

```
                              lib/main.dart
                                   │
                                   ▼
                    application/app_controller.dart ──────► ui/models/compose_payload.dart
                                   │                        (the only core → ui import)
    ┌────────────┬─────────────────┼─────────────────┬──────────────┬──────────────┐
    ▼            ▼                 ▼                 ▼              ▼              ▼
performance   simulation      manager/          channels/        media        platform
    │         (scenarios,     transfer_manager  hardware_*         │         (UI notifiers,
    │          orchestrator,   │  │  │  │          │               │          brightness)
    │          medium)         │  │  │  │          ▼               │              ▲
    └──────────► ▲ ◄───────────┘  │  │  │       physical/* ───────────────────────┘
                 │                │  │  │       (fountain, acoustic,
                 │                │  │  │        csk, qr_*, codecs) ─────► chat ◄── media
                 │                │  │  └──► engine
                 │                │  └─────► transport
                 │                │              │
                 │                ▼              ▼
                 └──────► manager/channel_manager ──► channels/comm_channel ──► simulation/
                                                                               simulated_medium

  Foundation used by most modules:   protocol ──► types ◄── logging        engine ──► types
  (protocol also supplies computeCrc32 to the fountain frames, modems and codecs)
```

The same information as a table, which is easier to scan:

| Module | Imports (internal) |
|---|---|
| `types` | nothing |
| `protocol` | `types` |
| `logging` | `types` |
| `chat` | nothing (`chat_payload_codec` imports `chat_message`) |
| `engine` | `types` |
| `transport` | `logging`, `manager/channel_manager`, `protocol`, `types` |
| `manager/transfer_state_machine` | `types` |
| `manager/channel_manager` | `channels/comm_channel`, `logging`, `protocol`, `types` |
| `manager/transfer_manager` | `channels` (hardware), `engine`, `logging`, `manager`, `protocol`, `physical/hardware_phy_config`, `platform`, `simulation/simulation_orchestrator`, `transport`, `types` |
| `channels/comm_channel` | `protocol`, `simulation/simulated_medium`, `types` |
| `channels/hardware_*` | `channels/comm_channel`, `logging`, `physical/*`, `platform`, `protocol`, `types` |
| `physical/fountain/lt_codec` | nothing |
| `physical/fountain/qr_fountain_frame` | `protocol` (for `computeCrc32`) |
| `physical/fountain/fountain_qr_modem` | `chat`, `logging`, `physical/fountain/*`, `physical/optical_modem`, `physical/optical_tx_profile`, `physical/qr_*`, `platform`, `protocol` |
| `physical/acoustic/reed_solomon`, `tone_timeline`, `spectrum_analyzer`, `biquad_filter` | nothing |
| `physical/acoustic/mt_fsk_codec` | `physical/acoustic/tone_timeline` |
| `physical/acoustic/acoustic_fountain_modem` | `logging`, `physical/acoustic/*`, `physical/fountain/lt_codec`, `physical/physical_codecs`, `protocol` |
| `physical/physical_codecs` | `protocol`, `chat` |
| `physical/hardware_phy_config` | `transport` (for `TransportConfig`), `types` |
| `physical/csk/csk_optical_modem` | `chat`, `logging`, `physical/optical_csk_*`, `physical/optical_modem`, `physical/optical_tx_profile`, `platform`, `protocol`, `channels/optical_web_sampler` |
| `physical/qr_decode_isolate_pool` | `channels/optical_web_qr_decoder`, `physical/qr_frame_decoder` |
| `platform/platform_capabilities` | `physical/fountain/qr_bitmap` |
| `platform/acoustic_spectrum_state` | `physical/acoustic/spectrum_analyzer`, `physical/acoustic/tone_timeline` (data types only) |
| `media` | `chat` |
| `simulation/simulated_medium` | `protocol`, `types` |
| `simulation/simulation_orchestrator` | `channels/comm_channel`, `engine`, `logging`, `manager/channel_manager`, `manager/transfer_state_machine`, `protocol`, `simulation/simulated_medium`, `transport`, `types` |
| `simulation/scenarios` | `simulation/simulated_medium`, `simulation/simulation_orchestrator` |
| `performance` | `simulation/*` |
| `application` | almost everything above, plus `ui/models/compose_payload.dart` |

Two things are worth knowing:

- `channels/comm_channel.dart` imports `simulation/simulated_medium.dart` (for `SimulatedCommChannel`), and `simulation/simulation_orchestrator.dart` imports `channels/comm_channel.dart`. Dart allows this, but keep it in mind if you split the packages.
- `application/app_controller.dart` imports `ui/models/compose_payload.dart`. This is the only place where a non-UI module depends on a UI file.

---

## 3. chat module

Folder: `lib/core/chat/`. It defines the chat message model and the **APCM envelope**, the one byte format every channel carries. See [Data Formats](../architecture/DATA_FORMATS.md) for byte-level dumps.

### 3.1 `lib/core/chat/chat_message.dart`

The immutable in-memory model of one chat message, sent or received.

```dart
enum ChatMessageType { text, image, video, file, link }

enum ChatMessageStatus { sending, sent, delivered, failed }

class ChatMessage {
  ChatMessage({
    required String id,
    required bool isOutgoing,
    required ChatMessageType type,
    required ChatMessageStatus status,
    required DateTime timestamp,
    String? text,
    Uint8List? data,
    String? fileName,
    String? mimeType,
    int? byteSize,
  });

  final String id;
  final bool isOutgoing;
  final ChatMessageType type;
  final ChatMessageStatus status;
  final DateTime timestamp;
  final String? text;
  final Uint8List? data;
  final String? fileName;
  final String? mimeType;
  final int? byteSize;

  ChatMessage copyWith({
    String? id,
    ChatMessageStatus? status,
    bool? isOutgoing,
    String? text,
    Uint8List? data,
  });

  String get preview;
}
```

| Member | Behaviour |
|---|---|
| `ChatMessageType` | The enum **index is the wire value** in the APCM type byte: text 0, image 1, video 2, file 3, link 4. Never reorder it. |
| `ChatMessageStatus` | `sending` while in flight, `sent` when a Light or Sound stream ended (no back-channel), `delivered` when confirmed or received, `failed` on error. |
| `id` | A string of `DateTime.now().millisecondsSinceEpoch`. `GallerySaver` uses it to avoid saving twice. |
| `text` / `data` | Text and link messages keep their content in `text` and leave `data` null. Media and files keep bytes in `data`. |
| `copyWith` | Copies the message. Only `id`, `status`, `isOutgoing`, `text` and `data` can change; `type`, `timestamp`, `fileName`, `mimeType` and `byteSize` are always kept. |
| `preview` | Returns `text` if non-empty, else `fileName`, else a label: `'Photo'`, `'Video'`, `'File'`, `'Link'` or `'Message'`. |

**Used by:** `ChatPayloadCodec`, `AppController` (the chat list), `GallerySaver`, `SampleMedia`, and the UI.

### 3.2 `lib/core/chat/chat_payload_codec.dart`

Packs content into, and parses it out of, the APCM envelope. Every Light, Sound and Vibration message is one envelope.

Envelope layout: magic `41 50 43 4D` ("APCM"), 1 type byte, 1 `nameLen` byte, the UTF-8 file name, 1 `mimeLen` byte, the UTF-8 MIME type, then the raw content to the end. The overhead is `7 + nameLen + mimeLen` bytes.

```dart
class ChatPayloadCodec {
  static Uint8List encode({
    required ChatMessageType type,
    required Uint8List data,
    String? fileName,
    String? mimeType,
  });
  static int overheadBytes({String? fileName, String? mimeType});
  static Uint8List encodeText(String text);
  static Uint8List encodeLink(String url);
  static bool isApcmEnvelope(Uint8List raw);
  static ChatMessage? decodeIncoming(Uint8List raw, {required bool isOutgoing});
  static bool looksComplete(Uint8List raw);
  static bool isDisplayableImage(Uint8List data);
}
```

| Method | Behaviour |
|---|---|
| `encode` | Writes the envelope. `fileName` and `mimeType` default to empty strings. **No length checks:** the name and MIME lengths are written with `addByte`, so a UTF-8 name longer than 255 bytes silently wraps and corrupts the envelope. |
| `overheadBytes({fileName, mimeType})` | Bytes `encode` adds around the data (4 magic + 3 type/length bytes + UTF-8 name + UTF-8 MIME), computed without building an envelope. `overheadBytes()` is 7. |
| `encodeText(text)` | `encode` with type `text` and an empty name and MIME type (7 bytes of overhead). `encodeText('sos')` is 10 bytes. |
| `encodeLink(url)` | `encode` with type `link` and an empty name and MIME type (also 7 bytes of overhead). |
| `isApcmEnvelope(raw)` | True when `raw` is at least 4 bytes and starts with the magic. Checks nothing else. |
| `looksComplete(raw)` | For non-APCM bytes, returns `raw.isNotEmpty`. For APCM bytes it requires a valid type index, name and MIME lengths inside the buffer, and a plausible body: text and link non-empty; image passes `isDisplayableImage`; video at least **512** bytes; file non-empty. |
| `isDisplayableImage(data)` | Requires at least **24** bytes and a JPEG (`FF D8`), PNG (`89 50 4E 47`), GIF (`47 49 46`) or WebP (`52 49 ... 57 45` at offsets 0, 1, 8, 9) signature. It does not look for a JPEG end marker. |
| `decodeIncoming(raw, isOutgoing:)` | For an APCM envelope: returns `null` unless `looksComplete` passes, then builds a `ChatMessage` with status `delivered`, a fresh timestamp id, the decoded `text` (text/link) or `data` (others), and `byteSize` = body length. For non-APCM bytes it falls back to a plain UTF-8 text message (legacy "HELLO" packets). If the bytes are not valid UTF-8 it returns a `file` message named `received.bin`. It returns `null` for empty input. It does not throw. |

**Used by:** `ComposePayload.toEnvelope` (UI), `AppController` (`_prepareEnvelope`, `_addIncomingChat`, `_tryDeliverIncomingMessage`), `FountainQrModem` and `CskOpticalModem` (magic check on completion), `FskStreamDecoder.pollDirectEnvelope`, `compressImageForTransfer` (image check).

Round-trip example:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';

final env = ChatPayloadCodec.encodeText('sos');
assert(env.length == 10);                        // 4 magic + 1 type + 1 name len + 1 mime len + 3 body
assert(ChatPayloadCodec.isApcmEnvelope(env));
assert(ChatPayloadCodec.looksComplete(env));

final msg = ChatPayloadCodec.decodeIncoming(env, isOutgoing: false)!;
assert(msg.type == ChatMessageType.text && msg.text == 'sos');
assert(msg.fileName == null && msg.mimeType == null);

// A truncated image envelope is refused rather than shown half-broken.
final photo = ChatPayloadCodec.encode(
  type: ChatMessageType.image,
  data: Uint8List.fromList([0xFF, 0xD8, ...List.filled(40, 0)]),
  fileName: 'photo.jpg',
  mimeType: 'image/jpeg',
);
final cut = Uint8List.sublistView(photo, 0, 30);
assert(ChatPayloadCodec.decodeIncoming(cut, isOutgoing: false) == null);
```

---

## 4. channels module

Folder: `lib/core/channels/`. A *channel* is one physical medium behind the common `CommChannel` interface. Hardware channels drive the real camera, screen, speaker, microphone, motor and accelerometer; simulated channels run over `SimulatedMedium`. Channel-level details are in [Light Channel](../channels/LIGHT_CHANNEL.md), [Sound Channel](../channels/SOUND_CHANNEL.md) and [Vibration Channel](../channels/VIBRATION_CHANNEL.md).

### 4.1 `lib/core/channels/comm_channel.dart`

Defines the `CommChannel` interface and the simulated implementation used by the Simulation Lab.

```dart
abstract class CommChannel {
  CommChannelId get id;
  ChannelCapabilities get capabilities;

  Future<void> initialize({bool setupCamera = true});
  Future<void> start({bool enableReceiver = true});
  Future<void> stop();
  Future<bool> discover(int timeoutMs);
  Future<ChannelTestResult> test(int testPacketCount);
  Future<void> transmit(Uint8List packet);
  Future<List<DecodedPacket>> receive();
  ChannelMetrics getMetrics();
  bool isAvailable();
  void setTransmissionConfig(TransmissionConfig config);
}

class SimulatedCommChannel implements CommChannel {
  SimulatedCommChannel({
    required CommChannelId id,
    required SimulatedMedium medium,
    required SimulatedChannelConfig config,
    required ChannelCapabilities capabilities,
  });
  SimulatedMedium get simulatedMedium;
}

SimulatedCommChannel createOpticalChannel(SimulatedMedium medium, SimulatedChannelConfig config);
SimulatedCommChannel createAcousticChannel(SimulatedMedium medium, SimulatedChannelConfig config);
SimulatedCommChannel createVibrationChannel(SimulatedMedium medium, SimulatedChannelConfig config);
```

`CommChannel` contract:

| Member | Contract |
|---|---|
| `initialize({setupCamera})` | One-time hardware setup and permission requests. `setupCamera` only matters for the optical channel (receivers need the camera, senders do not). |
| `start({enableReceiver})` | Begin operating. With `enableReceiver: false` the channel can transmit but must not hold the sensor (camera, microphone, accelerometer). |
| `stop()` | Stop transmitting and receiving and release sensors. |
| `discover(timeoutMs)` | Return true if a peer seems present within the timeout. |
| `test(n)` | Produce a `ChannelTestResult` for the adaptive engine. |
| `transmit(packet)` | Send one encoded protocol packet. Implementations throw `StateError` if not started. |
| `receive()` | Return and clear the protocol packets decoded since the last call. |
| `getMetrics()` | Current `ChannelMetrics` for scoring. |
| `isAvailable()` | True when running (and, for hardware, when the platform supports it). |
| `setTransmissionConfig` | Accepted by all current implementations but ignored. |

`SimulatedCommChannel` behaviour: `initialize` does nothing; `start`/`stop` toggle a running flag; `discover` calls `medium.runDiscoveryTest`; `test` runs `medium.runChannelTest` and converts it with `profileToTestResult`; `transmit` throws `StateError('Channel $id is not running')` when stopped and otherwise awaits `medium.send`; `receive` decodes whatever `medium.pollReceived()` returned (bad CRCs are dropped by `decodeRawPackets`); `getMetrics` returns `medium.getMetrics()`.

The three `create*Channel` factories set `name` to `'Optical (Simulated)'`, `'Acoustic (Simulated)'` or `'Vibration (Simulated)'`, copy `maxThroughput` and `minLatency` from the profile, and set `supportsBinary: true`, `hardwareImplemented: false`.

**Used by:** `ChannelManager`, `createSimulationPair` (simulation), the hardware channels (which implement the interface).

### 4.2 `lib/core/channels/hardware_optical_channel.dart`

The Light channel. It owns the camera and delegates everything else to a pluggable `OpticalModem` (fountain QR by default, CSK as a legacy option).

```dart
enum OpticalModemKind { fountainQr, csk }

class HardwareOpticalChannel implements CommChannel {
  HardwareOpticalChannel({
    StructuredLogger? logger,
    OpticalModemKind defaultModem = OpticalModemKind.fountainQr,
    OpticalTxProfile? profile,
  });

  static const defaultReceiveZoom = 1.5;
  static const receiveExposureOffsetEv = -0.7;

  OpticalModem get activeModem;
  FountainQrModem get fountainModem;
  CskOpticalModem get cskModem;
  OpticalModemKind get modemKind;
  OpticalMetricsNotifier get metricsNotifier;
  (int received, int total)? get chunkProgress;
  double get minZoom;
  double get maxZoom;
  double get zoom;
  bool get receiverReady;
  bool get isCameraStreaming;
  CameraController? get cameraController;

  void selectModem(OpticalModemKind kind);
  void setTxProfile(OpticalTxProfile profile);
  Future<double> setZoom(double level);
  Future<void> focusAt(Offset point);
  Future<void> transmitEnvelope(Uint8List envelope);
  Future<List<Uint8List>> receiveEnvelopes();
  void clearReceiveCaches({bool resetDedup = false});
  Future<void> ensureReceiverStreaming();
  Future<void> dispose();
  // plus every CommChannel member
}
```

| Member | Behaviour |
|---|---|
| Constructor | Builds both a `FountainQrModem` (profile defaults to `OpticalTxProfile.auto`) and a `CskOpticalModem`, selects one, and tells `opticalTransmitterState` which modem id is active. |
| `capabilities` | `name: 'Optical (Hardware)'`, `maxThroughput: 200000`, `minLatency: 50`. |
| `initialize({setupCamera})` | Returns at once on unsupported platforms. With `setupCamera` it requests the camera permission (not on web), picks the back camera (first camera on web), and opens it at `ResolutionPreset.high`, no audio, YUV420 (BGRA8888 on web). It then sets auto focus and exposure and, on native platforms, tunes for screens: zoom `defaultReceiveZoom` clamped to the device range, focus and exposure point at the centre `(0.5, 0.5)`, exposure offset `receiveExposureOffsetEv` clamped to the device range. Permission denial or no camera logs a warning and returns without throwing. |
| `start({enableReceiver})` | With a receiver, calls `activeModem.startReceiver()` and starts the camera image stream, forwarding each frame to `activeModem.onCameraFrame`. On web, where image streaming is unsupported, it runs a `Timer.periodic` every **33 ms** that calls `activeModem.onWebSampleTick()`. Without a receiver, it stops the modem receiver and the stream. It does nothing if already running in the same mode. |
| `setZoom(level)` | Clamps to `[minZoom, maxZoom]`, applies it and returns the zoom actually in effect. Errors are swallowed. |
| `focusAt(point)` | Sets focus and exposure point (0..1 preview coordinates) where supported. Used by tap-to-focus. |
| `transmitEnvelope(env)` | Throws `StateError('Optical channel not running')` if not started and `ArgumentError` if the envelope exceeds `activeModem.maxPayloadBytes`. On unsupported platforms it logs and returns. Otherwise it awaits `activeModem.transmit(env)`, which for fountain QR streams until stopped. |
| `receiveEnvelopes()` | Returns and clears `activeModem.takeEnvelopes()`. |
| `clearReceiveCaches({resetDedup})` | Forwards to the modem. With `resetDedup: false` the fountain modem keeps partial sessions. |
| `ensureReceiverStreaming()` | Restarts the camera image stream if it stopped (for example after a decode or a navigation). Errors are logged. |
| `stop()` | Stops the receiver and stream, cancels any transmission and clears the transmitting flag. |
| `discover` / `test` / `getMetrics` | Derived from the modem metrics: "locked" counts as a discovery, goodput becomes throughput, latency is a fixed 50 ms, stability 0.75 (`test`) or 0.8 (`getMetrics`). Loss defaults to 0.05 before anything is sent. |
| `transmit(packet)` | Protocol path: sends raw packet bytes through the active modem. |
| `receive()` | Returns an internal packet buffer that nothing fills in the current code, so it always returns an empty list. Light receives through `receiveEnvelopes` only. |

**Used by:** `AppController` (send, receive, zoom and focus from the receive screen), `createChannelManagerForMode`.

### 4.3 `lib/core/channels/hardware_channels.dart`

The Sound channel (`HardwareAcousticChannel`). The file also re-exports `vibration_channel.dart` and `hardware_optical_channel.dart`, so importing it gives you all three hardware channels.

```dart
enum AcousticModemKind { fountain, legacyFsk }

class HardwareAcousticChannel implements CommChannel {
  HardwareAcousticChannel({StructuredLogger? logger});

  bool get micStreaming;
  AcousticModemKind get modemKind;
  set modemKind(AcousticModemKind value);
  AcousticTxProfile get txProfile;
  set txProfile(AcousticTxProfile value);
  AcousticRxProgress get rxProgress;
  int get maxEnvelopeBytes;

  Future<void> transmitEnvelope(Uint8List envelope);
  void cancelTransmit();
  Future<List<Uint8List>> receiveEnvelopes();
  void clearReceiveCaches({bool resetDedup = false});
  Future<void> dispose();
  // plus every CommChannel member
}
```

| Member | Behaviour |
|---|---|
| `AcousticModemKind` | `fountain` (default): MT-FSK + Reed-Solomon + LT via `AcousticFountainModem`. `legacyFsk`: the old two-tone `FskCodec` with whole-message repeats. Changing it while the microphone runs resets the decoders. |
| `capabilities` | `name: 'Acoustic (Hardware)'`, `maxThroughput: 4000`, `minLatency: 200`. |
| `maxEnvelopeBytes` | `acousticFountainMaxBytes` (8192) in fountain mode, `hardwareAcousticDirectMaxBytes` (900) in legacy mode. `AppController` uses it to choose between the direct path and the protocol path. |
| `initialize()` | Requests the microphone (native only), sets the player to full volume and, on native platforms, applies the audio session for the current profile's band. **Audible:** Android speakerphone on, stay awake, speech content, voice-communication usage, audio focus gain; iOS `playAndRecord` with `defaultToSpeaker` and `allowBluetooth`. **Silent:** Android plain media playback (normal mode, music content, media usage) with stay awake and audio focus gain; iOS `playAndRecord` with `defaultToSpeaker` only. The voice-call path and Bluetooth hands-free audio would filter out 18–20 kHz. Each transmit re-applies the session if the band changed. |
| `start({enableReceiver})` | Without a receiver it stops the microphone and resets `acousticReceiverState`. With a receiver it checks permission (setting phase `permissionDenied` on failure), starts a PCM16 mono 44 100 Hz stream from `AndroidAudioSource.voiceRecognition` (the Android CDD requires noise suppression and AGC off and a flat response there, and covers 18.5–20 kHz on devices that claim near-ultrasound support), resets the decoders and sets phase `listening`. |
| Microphone callback | Converts each chunk with `pcm16ToFloat32`, computes RMS and the high-band level (RMS after a 16 kHz `HighPassFilter`, mapped from −70…−20 dBFS onto 0…1), and in fountain mode feeds `AcousticFountainModem.addSamples`, updates `acousticReceiverState` (levels throttled to one update per **80 ms**) and moves finished envelopes to an internal buffer. The tone meter shows `0.35 + 0.65 × progress` while a transfer is live, otherwise `max(clamp(RMS × 12), highBand)`, so Silent tones also move it. The phase goes to `tonesDetected` above 0.12 and back to `listening` at or below 0.08. In both modes every chunk is also copied into a `SpectrumAnalyzer`, and each time the 80 ms throttle lets an update through, `acousticSpectrumState.setRx(analyzer.analyze())` publishes the receiver's live spectrum. |
| `transmitEnvelope(env)` | Throws `StateError('Acoustic channel not running')` if stopped and `ArgumentError('Envelope too large for the acoustic channel')` above `maxEnvelopeBytes`. Always stops the microphone first (voice-mode recording ducks playback). Fountain mode: publishes progress through `acousticTransmitterState` and awaits `AcousticFountainModem.transmit` until cancelled or `stop()` is called. It passes `onBurst` to capture each burst's `ToneTimeline`; `_playWav` calls `acousticSpectrumState.startTxBurst(tones)` as soon as `AudioPlayer.play()` returns, and `endTx()` runs when the transmission ends. Legacy mode: frames with `frameDirectEnvelope`, prepends `hardwareAcousticLeadSilenceMs` (180) of silence, and plays the WAV `hardwareAcousticTxRepeatCount` (3) times with `hardwareAcousticTxRepeatGapMs` (350) gaps. |
| `cancelTransmit()` | If a fountain transmission is running: cancels the modem loop, clears the sender readout (`acousticSpectrumState.endTx()`), stops the audio player and completes the pending playback wait, so the current burst is cut off immediately. `stop()` calls it first. |
| `receiveEnvelopes()` | Returns and clears finished envelopes. |
| `clearReceiveCaches({resetDedup})` | Resets both decoders and buffers. With `resetDedup` the same envelope can be delivered again. |
| `transmit(packet)` | Protocol path. **Always uses the legacy two-tone `FskCodec`**, even in fountain mode. |
| `receive()` | Returns packets decoded by the legacy `FskStreamDecoder`. In fountain mode no packets are decoded, so this returns an empty list. |
| `discover` / `test` / `getMetrics` | Heuristics from microphone noise level; fixed latency 200 ms and stability 0.7; loss defaults to 0.08. |
| `stop()` | Stops the microphone and player and resets `acousticReceiverState` (keeping the decode count). Stopping the microphone, here or before a transmit, also resets the spectrum analyzer and `acousticSpectrumState.resetRx()`. |

**Used by:** `AppController`, `createChannelManagerForMode`.

### 4.4 `lib/core/channels/vibration_channel.dart`

The Vibration channel: pulse-width keying with the motor and the accelerometer. It only carries protocol packets.

```dart
class HardwareVibrationChannel implements CommChannel {
  HardwareVibrationChannel({StructuredLogger? logger});
  void clearReceiveCaches();
  Future<void> dispose();
  // plus every CommChannel member
}
```

| Member | Behaviour |
|---|---|
| `capabilities` | `name: 'Vibration (Hardware)'`, `maxThroughput: 800`, `minLatency: 300`. |
| `initialize()` | Only on Android/iOS (`isHardwarePlatform`). Logs a warning if no motor is reported (it will fall back to haptics). |
| `start({enableReceiver})` | With a receiver: resets the gravity baseline to 9.8 and subscribes to `accelerometerEventStream()`. Without: cancels the subscription but still allows transmitting. |
| Accelerometer callback | Magnitude `√(x²+y²+z²)`. Confidence `|mag − baseline| / 6`, clamped, published to `vibrationTransmitterState.setLastMagnitude`. While quiet the baseline follows `b = 0.92·b + 0.08·mag`. A pulse is "active" when `|mag − baseline| ≥ 1.4` (`VibrationBitCodec.relativeThreshold`). Pulses shorter than **25 ms** are ignored; others become bits via `decodePulseDuration`. |
| Packet decoding | Once 24 bits are buffered it looks for the preamble, reads the 24-byte header, rejects `payloadLength > 512`, then reads `24 + payloadLength + 4` bytes and runs `packetCodec.decode`. Without a preamble and more than 64 bits it drops the oldest quarter. |
| `transmit(packet)` | Throws `StateError('Vibration channel not running')` if stopped. Off-hardware it logs and returns. Otherwise it vibrates each bit (preamble plus data, MSB first) for 80 ms or 180 ms, waits the pulse length plus **50 ms**, then waits the 60 ms gap. It uses a full-intensity pattern when amplitude control exists, otherwise a plain duration vibrate, and `HapticFeedback.heavyImpact()` as the last resort. `vibrationTransmitterState` is updated throughout. |
| `getMetrics` | Throughput 800 scaled by loss, latency `(180 + 60) × 8 = 1920` ms, stability 0.65. |

**Used by:** `AppController` (only on phones, `isVibrationSupported`), `createChannelManagerForMode`.

### 4.5 Web helpers

These files use conditional exports so that `package:web` code is only compiled for Flutter Web. On other platforms the stubs return `null`.

| File | Public API | Purpose |
|---|---|---|
| `optical_web_qr_decoder.dart` | re-exports stub or web | Chooses the implementation with `if (dart.library.html)`. |
| `optical_web_qr_decoder_stub.dart` | `String? sampleOpticalQrFromPreview()` | Always returns `null`. |
| `optical_web_qr_decoder_web.dart` | `String? sampleOpticalQrFromPreview()` | Finds the first `<video>` element, copies a centred **640 × 640** patch to a canvas, and decodes it with zxing2 (`HybridBinarizer`, `tryHarder`, `characterSet: 'UTF-8'`), retrying with inverted luminance. Returns the decoded **text**, or `null`. |
| `optical_web_sampler.dart` | re-exports stub or web | Same conditional export pattern. |
| `optical_web_sampler_stub.dart` | `double? sampleOpticalLuminanceFromPreview()`, `List<(double, double, double)>? sampleCskCellsFromPreview()` | Both return `null`. |
| `optical_web_sampler_web.dart` | same two functions | `sampleOpticalLuminanceFromPreview` averages a 24 × 24 centre patch (BT.601 weights) to 0..1. `sampleCskCellsFromPreview` averages four 20 × 20 patches centred at 28 % and 72 % of the width and height, for the 2 × 2 CSK mosaic. |

**Used by:** `QrDecodeIsolatePool.submitWebPreview` (QR) and `CskOpticalModem.onWebSampleTick` (CSK). `sampleOpticalLuminanceFromPreview` has no caller in `lib/`.

Note: the web QR path returns `Result.text`, not the raw byte segment, and asks zxing2 for UTF-8. The phone sender always emits raw binary APCF frames in QR byte mode, so on the web those bytes pass through a text decode before `QrFountainFrameCodec.decodeFromQrString` tries to recover them. See [Light Channel](../channels/LIGHT_CHANNEL.md) for the web receiver's caveats.

---

## 5. engine module

Folder: `lib/core/engine/`. One file: the metric normaliser, the weighted channel scorer and the switch decision logic. The theory is in [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md).

### 5.1 `lib/core/engine/adaptive_decision_engine.dart`

```dart
class NormalizedMetrics {
  const NormalizedMetrics({
    required double throughput,
    required double reliability,
    required double latency,
    required double confidence,
    required double stability,
  });
}

class MetricNormalizer {
  final double maxThroughput = 25000;
  final double maxLatency = 500;
  NormalizedMetrics normalize(ChannelMetrics metrics);
  NormalizedMetrics normalizeFromTestResult(ChannelTestResult result);
}

class ChannelScorer {
  ChannelScorer({ScoringWeights weights = defaultScoringWeights});
  void setWeights(ScoringWeights weights);
  double scoreMetrics(ChannelMetrics metrics);
  double scoreTestResult(ChannelTestResult result);
  List<({CommChannelId channel, double score, double confidence})> rankChannels(
    List<ChannelTestResult> results,
  );
}

class AdaptiveDecisionEngine {
  AdaptiveDecisionEngine({
    ChannelScorer? scorer,
    double hysteresisThreshold = switchHysteresisThreshold,     // 0.15
    double degradationThresholdValue = degradationThreshold,    // 0.65
  });
  final ChannelScorer scorer;
  final double hysteresisThreshold;
  final double degradationThresholdValue;

  ChannelDecision selectBestChannel(List<ChannelTestResult> testResults);
  bool isDegraded(double currentScore);
  bool shouldSwitch(double currentScore, double alternativeScore);
  ({bool shouldSwitch, String reason, double currentScore, double alternativeScore})
      evaluateSwitch(
    CommChannelId currentChannel,
    ChannelMetrics currentMetrics,
    ChannelTestResult alternativeResult,
  );
}
```

| Member | Behaviour |
|---|---|
| `MetricNormalizer.normalize` | Every output is clamped to [0, 1]: `T = throughput / 25000`, `R = reliability`, `L = 1 − latency / 500`, `C = confidence`, `S = stability`. |
| `normalizeFromTestResult` | Same, but reliability is `packetsReceived / packetsSent` (0 if nothing was sent). |
| `ChannelScorer` score | `0.35·T + 0.25·R + 0.15·L + 0.15·C + 0.10·S` with the default `ScoringWeights`. |
| `rankChannels` | Scores every test result and sorts highest first. |
| `selectBestChannel` | Throws `StateError('No channel test results available')` for an empty list. Picks the top-ranked channel. The `reason` string compares it with the runner-up: `'Higher throughput and reliability'`, `'Lower packet loss'`, `'Lower latency'`, or the default `'Highest composite channel score'`. |
| `isDegraded(score)` | `score < degradationThresholdValue` (0.65). |
| `shouldSwitch(cur, alt)` | True only if `isDegraded(cur)` **and** `alt − cur ≥ hysteresisThreshold` (0.15). |
| `evaluateSwitch` | Scores the current metrics and the alternative test result, applies `shouldSwitch` and returns a human-readable reason. No side effects. |

**Used by:** `TransferManager` and `VirtualEndpoint` (each owns an `AdaptiveDecisionEngine`), `SimulationOrchestrator`.

Scoring example (the numbers match the healthy and degraded optical rows of the README table):

```dart
import 'package:adaptive_physical_communication/core/engine/adaptive_decision_engine.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

final engine = AdaptiveDecisionEngine();

final healthy = ChannelMetrics(
  throughput: 18000, packetLoss: 0.01, latency: 2, reliability: 0.99,
  errorRate: 0.005, confidence: 0.92, stability: 0.88, timestamp: 0,
);
// 0.35·0.72 + 0.25·0.99 + 0.15·0.996 + 0.15·0.92 + 0.10·0.88 ≈ 0.875
final healthyScore = engine.scorer.scoreMetrics(healthy);

final degraded = ChannelMetrics(
  throughput: 2000, packetLoss: 0.30, latency: 500, reliability: 0.70,
  errorRate: 0.3, confidence: 0.3, stability: 0.2, timestamp: 0,
);
// 0.35·0.08 + 0.25·0.70 + 0 + 0.15·0.3 + 0.10·0.2 = 0.268
final degradedScore = engine.scorer.scoreMetrics(degraded);

assert(!engine.isDegraded(healthyScore));
assert(engine.isDegraded(degradedScore));
assert(engine.shouldSwitch(degradedScore, 0.70));   // 0.70 − 0.268 ≥ 0.15
assert(!engine.shouldSwitch(degradedScore, 0.40));  // gap 0.13 < 0.15
```

---

## 6. logging module

Folder: `lib/core/logging/`.

### 6.1 `lib/core/logging/structured_logger.dart`

A small in-memory logger with categories and listeners. It never prints to the console.

```dart
typedef LogListener = void Function(LogEntry entry);

class StructuredLogger {
  StructuredLogger({int maxEntries = 1000});
  final int maxEntries;

  void log(String category, String message, [Map<String, dynamic>? data]);
  void discovery(String message, [Map<String, dynamic>? data]);     // 'DISCOVERY'
  void info(String message, [Map<String, dynamic>? data]);          // 'INFO'
  void test(String message, [Map<String, dynamic>? data]);          // 'TEST'
  void decision(String message, [Map<String, dynamic>? data]);      // 'DECISION'
  void transfer(String message, [Map<String, dynamic>? data]);      // 'TRANSFER'
  void warning(String message, [Map<String, dynamic>? data]);       // 'WARNING'
  void adapt(String message, [Map<String, dynamic>? data]);         // 'ADAPT'
  void switchChannel(String message, [Map<String, dynamic>? data]); // 'SWITCH'
  void error(String message, [Map<String, dynamic>? data]);         // 'ERROR'

  List<LogEntry> get entries;          // unmodifiable copy
  void clear();
  void Function() onLog(LogListener listener);
}
```

| Member | Behaviour |
|---|---|
| `log` | Appends a `LogEntry` with the current epoch milliseconds, drops the oldest entry past `maxEntries` (default **1000**), and calls every listener synchronously. |
| `onLog(listener)` | Registers a listener and returns a function that unregisters it. |
| `clear()` | Removes entries but keeps listeners. |

**Used by:** nearly every core class takes an optional logger. `AppController` owns one and mirrors entries into `liveLogs` through `onLog`.

---

## 7. manager module

Folder: `lib/core/manager/`. Channel registry, the transfer state machine and the full protocol-path transfer lifecycle. See [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md).

### 7.1 `lib/core/manager/transfer_state_machine.dart`

A validated 10-state machine with a timestamped history.

```dart
class TransferStateMachine {
  TransferState get state;
  bool canTransition(TransferState to);
  void transition(TransferState to);
  void forceState(TransferState to);
  void reset();
  List<({TransferState from, TransferState to, int timestamp})> get history;
}
```

Allowed transitions (copied from `_validTransitions`):

| From | Allowed targets |
|---|---|
| `idle` | `discovering`, `failed` |
| `discovering` | `testingChannels`, `failed` |
| `testingChannels` | `negotiating`, `failed` |
| `negotiating` | `transferring`, `failed` |
| `transferring` | `degraded`, `completed`, `failed` |
| `degraded` | `switchingChannel`, `recovering`, `transferring`, `failed` |
| `switchingChannel` | `recovering`, `transferring`, `failed` |
| `recovering` | `transferring`, `failed` |
| `completed` | `idle` |
| `failed` | `idle` |

- `transition(to)` throws `StateError('Invalid state transition: $_state → $to')` for anything else. On success it appends to `history`.
- `forceState(to)` skips validation (still recorded). `TransferManager` and `SimulationOrchestrator` use it to enter `failed` from any state.
- `reset()` returns to `idle` and clears history.

**Used by:** `TransferManager`, `VirtualEndpoint`.

### 7.2 `lib/core/manager/channel_manager.dart`

A registry of `CommChannel`s keyed by `CommChannelId`, with one "active" channel for transmitting.

```dart
class ChannelManager {
  ChannelManager(StructuredLogger logger);
  final StructuredLogger logger;

  void registerChannel(CommChannel channel);
  CommChannel? getChannel(CommChannelId id);
  List<CommChannel> get allChannels;
  List<CommChannelId> get availableChannelIds;
  CommChannel? get activeChannel;
  CommChannelId? get activeChannelId;
  void setActiveChannel(CommChannelId id);

  Future<void> initializeAll({bool setupOpticalCamera = true});
  Future<void> startAll({
    bool enableOpticalReceiver = true,
    bool enableVibrationReceiver = true,
    bool enableAcousticReceiver = true,
  });
  Future<void> stopAll();
  Future<List<CommChannelId>> discoverAll(int timeoutMs);
  Future<List<ChannelTestResult>> testAll(int testPacketCount);
  Future<ChannelTestResult> testChannel(CommChannelId id, int testPacketCount);
  ChannelTestResult? getTestResult(CommChannelId id);
  Map<CommChannelId, ChannelMetrics> getMetricsForAll();
  Future<void> transmit(Uint8List packet);
  Future<List<DecodedPacket>> receive();
  Future<List<DecodedPacket>> receiveActive();
}
```

| Member | Behaviour |
|---|---|
| `registerChannel` | Adds or replaces the channel for its id. |
| `setActiveChannel(id)` | Throws `StateError('Channel … not registered')` for an unknown id. |
| `initializeAll` / `startAll` / `stopAll` | Run sequentially over every channel. Only the optical channel receives `setupCamera`. |
| `discoverAll(t)` | Calls `discover(t)` on each channel **one after another** and logs each hit. Returns the ids that answered. |
| `testAll(n)` | Tests every registered channel, including ones that failed discovery. Stores and logs each result. |
| `testChannel(id, n)` | Throws `StateError('Channel … not found')` for an unknown id. |
| `transmit(packet)` | Sends on the active channel. Throws `StateError('No active channel selected')` if none. |
| `receive()` | Collects packets from **all** channels. `receiveActive()` only from the active one (empty list if none). |

**Used by:** `TransferManager`, `ReliableTransport`, `VirtualEndpoint`, `createSimulationPair`, `createChannelManagerForMode`.

### 7.3 `lib/core/manager/transfer_manager.dart`

The complete protocol-path lifecycle for one endpoint: discovery, testing, channel choice, reliable transfer, optional adaptive switching. `AppController.runHardwareTransfer` uses it for Vibration and oversized Sound messages.

```dart
enum OperationMode { simulation, hardware, hybrid }

class TransferManagerConfig {
  const TransferManagerConfig({
    int testPacketCount = 20,
    int discoveryTimeoutMs = 500,
    int peerDiscoveryTimeoutMs = 20000,
    int peerInactivityTimeoutMs = 45000,
    int monitorIntervalMs = 100,
    bool enableAdaptiveSwitching = true,
    OperationMode mode = OperationMode.simulation,
    TransferMode transferMode = TransferMode.broadcast,
    CommChannelId? forcedChannel,
    bool Function()? isCancelled,
  });
}

Future<ChannelManager> createChannelManagerForMode(
  OperationMode mode,
  StructuredLogger logger, {
  SimulationPair? simulationPair,
  HardwareOpticalChannel? optical,
  HardwareAcousticChannel? acoustic,
  HardwareVibrationChannel? vibration,
  EndpointRole? hardwareRole,
});

class TransferManager {
  TransferManager({
    required EndpointRole role,
    required StructuredLogger logger,
    required ChannelManager channelManager,
    TransferManagerConfig config = const TransferManagerConfig(),
  });

  final EndpointRole role;
  final TransferStateMachine stateMachine;
  final AdaptiveDecisionEngine decisionEngine;
  int sessionId;
  int transferId;
  ReliableTransport? transport;
  ChannelDecision? currentDecision;
  final Map<CommChannelId, double> channelScores;
  final List<SwitchEvent> switchEvents;
  Uint8List? receivedData;
  List<Uint8List> allPackets;
  Uint8List? dataToSend;
  void Function(DashboardSnapshot)? onSnapshot;

  DashboardSnapshot getSnapshot();
  Future<Uint8List?> runTransfer(Uint8List data);
  Future<void> shutdown();
}
```

`TransferManagerConfig` fields: `monitorIntervalMs` is declared but not read anywhere. `forcedChannel` skips discovery and selection. `isCancelled` is polled once per loop iteration.

`createChannelManagerForMode` registers channels and then calls `initializeAll(setupOpticalCamera: hardwareRole == EndpointRole.receiver)`:

| Mode | Channels registered |
|---|---|
| `simulation` | Endpoint A's channels from the given `SimulationPair`, or from a fresh `createSimulationPair()`. |
| `hardware` | The passed `optical` and `acoustic` (plus `vibration` if given). If either is missing, new hardware channels are created, with vibration only when `isVibrationSupported`. |
| `hybrid` | Simulated channels from a fresh pair, then the hardware channels, which **replace** the simulated ones with the same ids. |

`runTransfer(data)` steps:

1. Resets state, draws random `sessionId` and `transferId`, and starts all channels. Optical and vibration receivers run only for the receiver role; the acoustic receiver always runs.
2. Enters `discovering`. Broadcast is on when `transferMode == broadcast` **and** `mode == hardware`.
   - With `forcedChannel`: fails if not registered, else uses only that channel.
   - Broadcast: uses every registered channel except vibration.
   - Hardware unicast: runs a discovery handshake for up to `peerDiscoveryTimeoutMs`. The sender beacons a `discovery` packet on acoustic, optical and (phones only) vibration, and waits for a `discoveryResponse` with its session id. The receiver answers the first matching `discovery`. Rounds are 300 ms apart.
   - Simulation: `discoverAll(discoveryTimeoutMs)`.
   - Any failure moves to `failed`, logs an error, emits a snapshot and returns `null`.
3. Enters `testingChannels` and `negotiating`, then picks a channel. Forced: score 1.0. Broadcast: optical (0.95), else acoustic (0.85), else the first channel (0.5). Otherwise it tests all channels; in **hardware** mode it then always picks acoustic ("Acoustic is bidirectional — best for phone-to-phone") when available, and only in simulation does it use `selectBestChannel`.
4. Builds a `ReliableTransport` with `hardwareTransportConfig` and `hardwareTransmissionConfigFor(channel)` in hardware mode, or the defaults otherwise. `broadcastMode` is true for a broadcast sender.
5. The sender fragments `data` with `createDataPackets`. Enters `transferring` and runs the loop.
6. Returns `receivedData` (receiver) or `null`.

The loop runs at most **2000** iterations in hardware mode and **1500** otherwise, sleeping **50 ms** (hardware) or **5 ms** per iteration. Each iteration sends the next window, receives, answers with ACK/NACK/retransmissions, checks timeouts, and receives again. It stops when the receiver has every packet, the broadcast sender has sent every packet, or the unicast sender has every ACK. In hardware unicast it also stops if every in-flight packet has exhausted its retries with nothing ever ACKed, or after `peerInactivityTimeoutMs` without progress. With `enableAdaptiveSwitching`, `_evaluateSwitch` runs when `i % 20 == 0`. A snapshot is emitted every 5 iterations. At the end the state becomes `completed` on success, or is forced to `failed`.

`_evaluateSwitch` scores the active channel's metrics. If degraded, it enters `degraded`, tests each other channel and switches to the first one for which `evaluateSwitch` says yes. `_performSwitch` moves through `switchingChannel` → `recovering` → `transferring`, calls `resumeFromSequence(lastAcked)`, sends a `channelSwitchRequest` and records a `SwitchEvent`. It **does not wait for a `channelSwitchAck`**.

`shutdown()` stops every channel.

**Used by:** `AppController.runHardwareTransfer` (always with `enableAdaptiveSwitching: false` and a `forcedChannel`).

---

## 8. media module

Folder: `lib/core/media/`. Photo compression, the bundled demo samples and saving to the Gallery. More background is in the README sections on media.

### 8.1 `lib/core/media/image_compress.dart`

Turns any picked photo into a JPEG of at most 120 KB so that a Light transfer finishes in seconds.

```dart
class ImageTransferException implements Exception {
  ImageTransferException(String message);
  final String message;
}

Future<Uint8List> compressImageForTransfer(
  Uint8List bytes, {
  int maxWidth = 960,
  int maxHeight = 960,
  int quality = 78,
  int maxBytes = 120 * 1024,
});
```

Algorithm:

1. Decode with `package:image`. If decoding fails but the bytes start with `FF D8`, return them unchanged when within `maxBytes`; otherwise try a JPEG-only recompress (resize to the limits, quality 70; if still too big, width 640 at quality 60), returning the original bytes if even `decodeJpg` fails. If decoding fails and the bytes are not JPEG, throw `ImageTransferException('Could not read this photo. Try JPG/PNG or take a new picture.')`.
2. Resize so the long side is at most `maxWidth`/`maxHeight` (linear interpolation).
3. Encode JPEG at `quality`. While the result exceeds `maxBytes` and `q > 40`, lower `q` by 8 (78 → 70 → 62 → 54 → 46 → 38).
4. If still too big and the image is larger than 640 px, resize to 640 px and encode at quality 65.
5. If the output fails `ChatPayloadCodec.isDisplayableImage`, throw `ImageTransferException('Image compression failed — try another photo.')`.

**Used by:** `SendComposeScreen` when a photo is picked, and again by `AppController._prepareEnvelope` for every image at send time (including demo samples). A picked photo is therefore compressed twice; the second pass usually re-encodes an already small JPEG.

### 8.2 `lib/core/media/sample_media.dart`

Describes and loads the demo photos and videos bundled under `assets/samples/`.

```dart
class SampleMedia {
  const SampleMedia({
    required String assetPath,
    required ChatMessageType type,
    required String mimeType,
  });

  static const assetPrefix = 'assets/samples/';
  final String assetPath;
  final ChatMessageType type;
  final String mimeType;

  String get fileName;
  String get title;
  int? get budgetKb;
  Future<Uint8List> load([AssetBundle? bundle]);
  static SampleMedia? fromAssetPath(String path);
}

Future<List<SampleMedia>> loadSampleMediaCatalog([AssetBundle? bundle]);
```

| Member | Behaviour |
|---|---|
| `fileName` | Last path segment. |
| `title` | File-name words without the `_<N>kb` budget word, `qr` shown as `QR`, first letter upper-cased. `how_qr_codes_work_140kb.mp4` → `How QR codes work`. |
| `budgetKb` | The `N` in a `<N>kb` word (regex `^(\d+)kb$`), or `null`. |
| `load([bundle])` | Reads the asset bytes from `bundle` or `rootBundle`. |
| `fromAssetPath(path)` | Returns `null` unless the path starts with `assets/samples/`. Maps `jpg`/`jpeg` → image `image/jpeg`, `png` → image `image/png`, `mp4` → video `video/mp4`, `webm` → video `video/webm`. Any other extension → `null`. |
| `loadSampleMediaCatalog` | Reads the `AssetManifest`, keeps every sample, sorts by type (images first, by `ChatMessageType.index`), then title, then budget. |

The class comment says samples "skip recompression", but images are recompressed at send time by `AppController._prepareEnvelope` (see 8.1).

**Used by:** the sample picker in `send_compose_screen.dart`, and `test/sample_media_test.dart`.

```dart
final samples = await loadSampleMediaCatalog();
final video = samples.firstWhere((s) => s.fileName == 'speed_of_light_80kb.webm');
assert(video.title == 'Speed of light' && video.budgetKb == 80);
final bytes = await video.load();
final envelope = ChatPayloadCodec.encode(
  type: video.type, data: bytes, fileName: video.fileName, mimeType: video.mimeType,
);
```

### 8.3 `lib/core/media/gallery_saver.dart`

Saves received photos and videos to the device Gallery in the album "Adaptive Comm", at most once per message.

```dart
class GallerySaver extends ChangeNotifier {
  static final GallerySaver instance;
  static const albumName = 'Adaptive Comm';

  bool get isSupported;
  static bool canSave(ChatMessage m);
  bool isSaved(String id);
  bool isSaving(String id);
  String? errorFor(String id);
  Future<bool> save(ChatMessage m);
}
```

| Member | Behaviour |
|---|---|
| `instance` | The only instance (private constructor). |
| `isSupported` | True on Android and iOS only (not web or desktop). |
| `canSave(m)` | Image or video with non-empty `data`. |
| `save(m)` | Returns `false` at once if unsupported or not saveable. Otherwise it returns the same `Future` for repeated calls with the same `m.id`, so auto-save and the button never duplicate. The work: request album access through `gal` if needed; write the bytes to a temporary file `APC_<17 digits>.<ext>`; call `Gal.putImage` or `Gal.putVideo` into the album; delete the temporary file. It never throws. |
| Errors | On failure the id is removed from the in-flight map (so **Retry** works) and `errorFor(id)` returns one of: `'Gallery permission denied'`, `'Not enough storage'`, `'Format not supported by the gallery'`, `'Could not save to gallery'`. |
| Extensions | Images: `png`, `webp`, `gif` from the MIME type or name, else `jpg`. Videos: `webm`, `mov` (for `quicktime`), else `mp4`. |
| Notifications | `notifyListeners()` at the start and end of every save. |

**Used by:** `AppController._addIncomingChat` (auto-save) and `received_content_view.dart` (button state).

```dart
final saver = GallerySaver.instance;
if (GallerySaver.canSave(msg) && saver.isSupported) {
  final ok = await saver.save(msg);           // safe to call again; returns the same future
  if (!ok) debugPrint(saver.errorFor(msg.id));
}
```

---

## 9. performance module

Folder: `lib/core/performance/`.

### 9.1 `lib/core/performance/performance_comparator.dart`

Runs a simple comparison of an adaptive strategy against "fixed" strategies in the simulator.

```dart
enum TransferStrategy { fixedOptical, fixedAcoustic, staticSwitch, adaptive }

class StrategyResult {
  const StrategyResult({
    required TransferStrategy strategy,
    required bool success,
    required int durationMs,
    required double throughput,
    required double packetLoss,
    required int retransmissions,
    required int switchCount,
    required double goodput,
  });
}

class PerformanceComparator {
  Future<List<StrategyResult>> runComparison({int dataSize = 4096});
}

String strategyLabel(TransferStrategy s);
```

| Strategy run | How it is simulated |
|---|---|
| `adaptive` | Scenario `optical-degrades`. `switchCount` is the number of switch events. |
| `fixedOptical` | `createSimulationPair(opticalProfileA: ChannelSimulationProfile(packetLossRate: 0.08))`. `switchCount` is reported as 0. |
| `fixedAcoustic` | Optical undiscoverable on both sides. `switchCount` is reported as 0. |

All three use a full `SimulationOrchestrator`, so the "fixed" runs still use adaptive selection and switching internally. `staticSwitch` is defined (with the label `'Static Switch'`) but never run. `throughput` is the sender's final metric throughput; `goodput = dataSize / seconds` on success, else 0. Results come back in the order adaptive, fixed optical, fixed acoustic.

**Used by:** `AppController.runPerformanceComparison`; `strategyLabel` is used by `performance_screen.dart`.

---

## 10. physical module (shared files)

Folder: `lib/core/physical/`. Everything between bytes and the physical signal. This section covers the files directly in the folder; the `fountain/`, `acoustic/` and `csk/` sub-folders follow.

### 10.1 `lib/core/physical/optical_modem.dart`

The plug-in interface every Light modem implements, and the notifier for live Light metrics.

```dart
abstract class OpticalModem {
  String get id;
  String get label;
  int get maxPayloadBytes;
  OpticalTransferMetrics get metrics;

  Future<void> startReceiver();
  Future<void> stopReceiver();
  Future<void> transmit(Uint8List envelope);
  void cancelTransmit();
  void onCameraFrame(Object image);
  void onWebSampleTick();
  void clearReceiveCaches({bool resetDedup = false});
  List<Uint8List> takeEnvelopes();
  void dispose() {}
}

class OpticalMetricsNotifier extends ChangeNotifier {
  OpticalTransferMetrics get metrics;
  void update(OpticalTransferMetrics value);
  void reset();
}
```

| Member | Contract |
|---|---|
| `onCameraFrame(image)` | Called synchronously from the camera stream with a `CameraImage`. Implementations must copy what they need before returning, because the plugin recycles the buffers. |
| `onWebSampleTick()` | Called every 33 ms on web by `HardwareOpticalChannel`. |
| `takeEnvelopes()` | Returns and clears completed envelopes. |
| `OpticalMetricsNotifier.update` / `reset` | Replace the metrics (reset uses `OpticalTransferMetrics.empty`) and notify listeners. |

**Implemented by:** `FountainQrModem`, `CskOpticalModem`. **Used by:** `HardwareOpticalChannel`, the Light HUD (through `AppController.opticalMetricsNotifier`).

### 10.2 `lib/core/physical/optical_tx_profile.dart`

Light density and speed profiles, the Auto density rule, the ETA formula and the live metrics record.

```dart
class OpticalTxProfile {
  const OpticalTxProfile({
    required String id,
    required String label,
    required int txFps,
    required int blockLen,
    required String errorCorrectLevel,
    required int decodeTargetPx,
  });

  static const auto, safe, standard, fast;
  static const values = [auto, safe, standard, fast];
  static const autoBlockLadder = [160, 240, 330];
  static const autoTargetSymbols = 48;

  int get payloadBytesPerFrame;         // == blockLen
  double get nominalKbps;               // blockLen * txFps / 1000
  bool get isAuto;
  double get expectedCaptureYield;
  int get framedSymbolBytes;            // blockLen + qrFountainOverhead (26)
  OpticalTxProfile get slower;

  static OpticalTxProfile byId(String id);
  OpticalTxProfile resolveFor(int envelopeBytes);
  int estimatedSeconds(int envelopeBytes);
}
```

The four profiles (all use `errorCorrectLevel: 'L'`):

| Constant | `id` | `label` | `txFps` | `blockLen` | `decodeTargetPx` |
|---|---|---|---|---|---|
| `auto` | `'auto'` | Auto | 12 | 240 (replaced by `resolveFor`) | 720 |
| `safe` | `'safe'` | Safe | 8 | 160 | 720 |
| `standard` | `'standard'` | Standard | 12 | 330 | 720 |
| `fast` | `'fast'` | Fast | 12 | 600 | 800 |

| Member | Behaviour |
|---|---|
| `resolveFor(bytes)` | Fixed profiles return themselves. `auto` returns a copy with the first `blockLen` in `[160, 240, 330]` such that `ceil(bytes / blockLen) ≤ 48`, else 330. So ≤ 7 680 B → 160, ≤ 11 520 B → 240, larger → 330. |
| `expectedCaptureYield` | 0.7 for `blockLen ≤ 160`, 0.65 for ≤ 240, 0.55 for ≤ 330, 0.35 above. |
| `estimatedSeconds(bytes)` | `ceil((K + 2) / (txFps × yield))` with `K = ceil(bytes / blockLen)` for the resolved profile, clamped to at least 1. |
| `slower` | `fast` → `standard`; everything else → `safe`. |
| `byId(id)` | Unknown ids return `auto`. |
| `==` / `hashCode` | Compare `id` and `blockLen`. A resolved Auto profile equals plain `auto` only when it resolved to 240. |

```dart
class OpticalTransferMetrics {
  const OpticalTransferMetrics({
    double captureFps = 0, double decodeFps = 0, int dropped = 0,
    double goodputKBps = 0, double elapsedSec = 0,
    int framesNew = 0, int framesDup = 0, int framesRed = 0,
    String? sessionId, int blockLen = 0, int payloadBytes = 0,
    int symbolsCollected = 0, int symbolsNeeded = 0,
    bool locked = false, bool complete = false, bool stalled = false,
    String profileLabel = 'Standard',
  });
  double get progress;           // symbolsCollected / symbolsNeeded, clamped; 1 if complete with no K
  OpticalTransferMetrics copyWith({...});
  static const empty = OpticalTransferMetrics();
}
```

**Used by:** `FountainQrModem` (TX density, decode target size, metrics), `HardwareOpticalChannel`, `AppController` (`opticalTxProfile`, `setOpticalTxProfile`), `send_transmit_screen.dart` (profile chips and ETA), the Light HUD.

### 10.3 `lib/core/physical/hardware_phy_config.dart`

Timing, packet sizes and transport settings for the real phone hardware.

| Constant / function | Value | Meaning |
|---|---|---|
| `hardwareOpticalBitMs` | `35` | Declared; not used by current code. |
| `hardwareAcousticSymbolMs` | `18` | Legacy two-tone FSK bit length (ms). |
| `hardwareAcousticTxRepeatCount` | `3` | Legacy FSK plays each message this many times. |
| `hardwareAcousticTxRepeatGapMs` | `350` | Gap between legacy FSK repeats (ms). |
| `hardwareAcousticLeadSilenceMs` | `180` | Legacy FSK lead silence (ms). |
| `hardwareTransportConfig` | `TransportConfig(ackTimeoutMs: 20000, maxRetries: 8, windowSize: 4)` | Protocol timing on hardware. |
| `hardwareOpticalPacketSize` | `1400` | Protocol payload per optical packet. |
| `hardwareAcousticPacketSize` | `512` | Protocol payload per acoustic packet. |
| `hardwareVibrationPacketSize` | `48` | Protocol payload per vibration packet. |
| `hardwareAcousticDirectMaxBytes` | `900` | Largest envelope for legacy FSK direct send. |
| `acousticFountainMaxBytes` | `8192` | Largest envelope for the fountain Sound modem. |
| `TransmissionConfig hardwareTransmissionConfigFor(CommChannelId channel)` | | A `TransmissionConfig` whose `packetSize` is one of the three sizes above; other fields keep their defaults. |
| `Uint8List get hardwareDiscoveryPayload` | `[0xDC, 0x01]` | Payload of discovery and discovery-response packets. |
| `int estimateHardwareTxMs(int byteCount)` | | `(8 + byteCount × 8) × 18` ms (legacy FSK airtime). No caller in `lib/`. |

**Used by:** `HardwareAcousticChannel`, `TransferManager`, `AppController`.

### 10.4 `lib/core/physical/physical_codecs.dart`

Legacy bit-level codecs (two-tone FSK, on/off light, vibration pulse width), the Goertzel detector and the WAV writer.

```dart
class Goertzel {
  Goertzel({required double sampleRate, required double targetFrequency});
  double detect(List<double> samples);
}

class FskCodec {
  FskCodec({
    int sampleRate = 44100,
    double f0 = 1800,
    double f1 = 3200,
    int symbolDurationMs = 80,
    List<int> preambleBits = const [1, 0, 1, 0, 1, 0, 1, 0],
  });
  int get samplesPerSymbol;
  List<int> bytesToBits(Uint8List data);
  Uint8List bitsToBytes(List<int> bits, {int? expectedByteCount});
  int findPreambleIndex(List<int> bits);
  Float32List generateToneSamples(int bit);
  Float32List encodeBytes(Uint8List data);
  int decodeSymbol(List<double> samples);
  (double, double) measureToneStrength(List<double> samples);
  double combinedToneStrength(List<double> samples);
  List<int> decodeSamples(List<double> samples);
}

class FskStreamDecoder {
  FskStreamDecoder({FskCodec? codec});
  void addSamples(List<double> samples);
  Uint8List? pollPacket({int? expectedByteCount});
  Uint8List? pollDirectEnvelope({int maxPayloadBytes = 900});
  void reset();
  double peekToneStrength();
}

Uint8List frameDirectEnvelope(Uint8List envelope);
Uint8List pcmToWav(Float32List samples, {int sampleRate = 44100});

class OpticalBitCodec {
  OpticalBitCodec({int bitDurationMs = 100, List<int> preamble = const [1, 0, 1, 0, 1, 0, 1, 1]});
  List<int> bytesToBits(Uint8List data);
  Uint8List bitsToBytes(List<int> bits, {int? expectedLength});
  bool luminanceToBit(double luminance);          // luminance > 0.5
}

class VibrationBitCodec {
  VibrationBitCodec({
    int shortPulseMs = 80,
    int longPulseMs = 180,
    int gapMs = 60,
    List<int> preamble = const [0, 1, 0, 1, 0, 1, 1, 0],
    double detectionThreshold = 12.0,
    double relativeThreshold = 1.4,
  });
  int pulseDurationMs(int bit);
  int symbolPeriodMs(int bit);
  int decodePulseDuration(double durationMs);
  List<int> bytesToBits(Uint8List data);
  Uint8List bitsToBytes(List<int> bits, {int? expectedLength});
  Uint8List extractWireBytes(List<int> bits, int byteCount);
  int findPreambleIndex(List<int> bits);
  bool isVibrationActive(double magnitude, {double? baseline});
}
```

| Item | Behaviour |
|---|---|
| `Goertzel.detect` | Power at `targetFrequency` divided by the sample count. |
| `FskCodec` | Bits are MSB first after the preamble. The **default** symbol is 80 ms; the hardware channel constructs it with `hardwareAcousticSymbolMs` (18 ms). `decodeSymbol` returns 1 when the f1 power exceeds the f0 power. `measureToneStrength` scales each power by 800 and clamps to [0, 1]. |
| `FskStreamDecoder.pollPacket` | Needs at least 16 symbols buffered. Finds the preamble, reads the 24-byte header, rejects `payloadLength > 8192`, waits for the whole packet, and returns it only if `packetCodec.decode` accepts it. On a bad CRC it skips one symbol past the preamble. It halves the buffer if it exceeds 8 s of audio (`44100 × 8` samples). |
| `FskStreamDecoder.pollDirectEnvelope` | Reads a 2-byte little-endian length after the preamble, requires `0 < length ≤ maxPayloadBytes` and an APCM magic, and returns the envelope. |
| `frameDirectEnvelope(env)` | Prepends a 2-byte little-endian length. |
| `pcmToWav(samples)` | A 44-byte RIFF header plus mono 16-bit PCM (samples clamped to [−1, 1] and scaled by 32767). The output of every Sound transmitter goes through it. |
| `VibrationBitCodec.decodePulseDuration(d)` | 1 if `d ≥ (80 + 180) / 2 = 130` ms, else 0. |
| `symbolPeriodMs(bit)` | Pulse plus the 60 ms gap: 140 or 240 ms (the channel adds 50 ms of motor settle on top). |
| `isVibrationActive(mag, baseline:)` | With a baseline: `|mag − baseline| ≥ 1.4`. Without: `mag ≥ 12.0`. |
| `extractWireBytes(bits, n)` | The `n` bytes after the first preamble, or an empty list if there are not enough bits. |

**Used by:** `HardwareAcousticChannel` (legacy mode and `pcmToWav`), `AcousticFountainModem` (`pcmToWav`), `HardwareVibrationChannel`, tests (`OpticalBitCodec` is test-only).

### 10.5 `lib/core/physical/qr_gray_frame.dart`

Copies the centre square of a camera frame into an 8-bit luminance buffer that zxing2 can read directly.

```dart
class QrGrayFrame {
  const QrGrayFrame({required int width, required int height, required Int8List lum});
  final int width;
  final int height;
  final Int8List lum;
  int get pixelCount;
}

QrGrayFrame? extractQrGrayFrame(
  CameraImage image, {
  double cropFraction = 0.98,
  int targetPx = 720,
});
```

- Must be called synchronously inside the camera callback.
- The crop side is `round(shortSide × cropFraction)` clamped to [16, shortSide], centred. The sampling step is `round(cropSide / targetPx)` clamped to [1, 8]. The output side is `cropSide ~/ step`.
- For YUV (pixel stride 1, step 1) each row is a single `setRange` copy of the Y plane. For BGRA (pixel stride ≥ 3) each pixel is `(r + 2g + b) >> 2`.
- Returns `null` for frames smaller than 16 px, frames without planes, or outputs smaller than 16 px.

At 1280 × 720 with defaults: crop 706 px, step 1, a 706 × 706 frame.

**Used by:** `FountainQrModem.onCameraFrame` (with `targetPx: profile.decodeTargetPx`).

### 10.6 `lib/core/physical/qr_frame_decoder.dart`

The zxing2 decode strategies for both the fast fountain path (luminance) and the older RGB path.

```dart
class QrFramePixels {
  const QrFramePixels({required int width, required int height, required Int32List pixels});
}

QrFramePixels? extractQrFramePixels(CameraImage image);
String? decodeQrFromCameraImage(CameraImage image);
String? decodeQrTextFromPixels(QrFramePixels frame);
Uint8List? decodeQrBytesFromPixels(QrFramePixels frame);
Uint8List? decodeQrBytesFromLuminance(int width, int height, Int8List lum);
```

| Function | Behaviour |
|---|---|
| `decodeQrBytesFromLuminance` | **The production fountain path.** Wraps the buffer in `RGBLuminanceSource.crop` (no colour conversion) and tries, in order: (1) `GlobalHistogramBinarizer` with QR-only hints; (2) the same bitmap with `pureBarcode`; (3) `HybridBinarizer` with QR-only hints. No `tryHarder`. Returns the joined raw byte segments, else `rawBytes`, else the UTF-8 text, else `null`. |
| `extractQrFramePixels` | Older path: copies a centred 92 % crop as ARGB, downscaled so the width is at most 1280. |
| `decodeQrTextFromPixels` / `decodeQrBytesFromPixels` | Older path: `HybridBinarizer` with `tryHarder` and UTF-8, retrying on inverted luminance. |
| `decodeQrFromCameraImage` | `extractQrFramePixels` then `decodeQrTextFromPixels`. |

All functions return `null` on failure and never throw.

**Used by:** `QrDecodeWorker` (luminance path), `QrDecodeIsolatePool` (pixel path).

### 10.7 `lib/core/physical/qr_decode_worker.dart`

One long-lived background isolate that decodes luminance frames, with at most one decode in flight.

```dart
class QrDecodeWorker {
  int submitted;
  int decoded;
  int dropped;
  bool get isBusy;
  bool get isReady;
  Future<void> start();
  Future<Uint8List?> decode(QrGrayFrame frame);
  void resetStats();
  void dispose();
}
```

| Member | Behaviour |
|---|---|
| `start()` | Spawns the isolate `qr-decode` and completes a two-port handshake. Does nothing on web, when already started, or after `dispose`. If spawning fails it logs with `debugPrint` and the worker decodes inline. |
| `decode(frame)` | Returns `null` immediately (and counts `dropped`) if a decode is already running. Otherwise it sends `[width, height, TransferableTypedData]` to the isolate and awaits the reply with a **2 second** timeout, after which it gives up and frees the slot. Without an isolate it yields once (`Future.delayed(Duration.zero)`) and decodes on the main isolate. |
| Isolate entry | Always replies, sending `null` on any error, so the caller never waits forever. |
| `dispose()` | Completes any pending decode with `null`, closes the port and kills the isolate immediately. |

**Used by:** `FountainQrModem`.

### 10.8 `lib/core/physical/qr_decode_isolate_pool.dart`

Despite its name, this class does not use isolates. It decodes on the main isolate after one `await`, and limits concurrency with a counter.

```dart
class QrDecodeIsolatePool {
  QrDecodeIsolatePool({int maxInFlight = 2});
  final int maxInFlight;
  int dropped;
  int decoded;
  int captureTicks;
  bool get isBusy;
  Future<String?> submitCameraImage(CameraImage image);
  Future<Uint8List?> submitCameraImageBytes(CameraImage image);
  Future<String?> submitWebPreview();
  void resetStats();
}
```

- `submitCameraImage` / `submitCameraImageBytes`: copy the frame with `extractQrFramePixels` **before** yielding, then decode with the pixel-path functions. They return `null` when busy (counted as `dropped`).
- `submitWebPreview`: calls `sampleOpticalQrFromPreview()`.

**Used by:** `FountainQrModem.onWebSampleTick` (only `submitWebPreview`). The two camera methods have no caller in `lib/`.

### 10.9 `lib/core/physical/qr_optical_codec.dart` (legacy)

The original sequential text QR codec, `APCS1:<id>:<i>/<n>:<base64url>`. Kept for reuse and tests; the current UI does not use it.

| Constant | Value |
|---|---|
| `qrOpticalMagic` | `'APCS1'` |
| `qrMaxChunkBytes` | `1400` |
| `qrFrameDurationMs` | `220` |
| `qrFrameRepeatCount` | `2` |
| `qrScanIntervalMs` | `40` |

```dart
class QrOpticalChunk {
  const QrOpticalChunk({required String messageId, required int index, required int total, required Uint8List data});
}
class QrOpticalCodec {
  List<String> encodeToQrStrings(Uint8List data);
  QrOpticalChunk? decodeQrString(String raw);
}
class QrOpticalReassembler {
  Uint8List? addChunk(QrOpticalChunk chunk);
  void pruneStale({int maxAgeMs = 15000});
  void reset();
  (int received, int total)? get progress;
}
final qrOpticalCodec = QrOpticalCodec();
```

The message id is the low 24 bits of the CRC-32 of the data as 6 hex digits. `decodeQrString` returns `null` for anything that is not a well-formed `APCS1` chunk. `addChunk` returns the reassembled bytes once chunks 1..n are present; if `total` changes mid-message the parts are cleared.

**Used by:** `test/qr_optical_codec_test.dart`, `test/image_envelope_test.dart`.

### 10.10 `lib/core/physical/optical_csk_codec.dart` and `optical_csk_sampler.dart` (legacy CSK support)

Colour-shift keying for the legacy CSK modem (section 13). Each byte is shown as a 2 × 2 colour mosaic, 2 bits per cell.

```dart
enum CskSymbol { red, green, blue, white }   // dibit 0..3, with colours below

const cskPreambleBytes = [0x00, 0x55, 0xAA, 0xFF];
const hardwareOpticalCskMaxBytes = 180;
const hardwareOpticalCskSymbolMs = 140;
const hardwareOpticalCskGuardMs = 20;
const hardwareOpticalCskLeadMs = 250;
const hardwareOpticalCskRepeatCount = 3;
const hardwareOpticalCskRepeatGapMs = 400;

class OpticalCskCodec {
  List<Color> cellsForByte(int byte);
  Uint8List frameEnvelope(Uint8List envelope);
  int classifyRgb(double r, double g, double b);
  int? packFrame(List<(double, double, double)> cells);
}
final opticalCskCodec = OpticalCskCodec();

class OpticalCskDecoder {
  (int received, int expected)? get progress;
  void noteGuard();
  void addSampledByte(int byte);
  Uint8List? pollEnvelope({int maxPayloadBytes = hardwareOpticalCskMaxBytes});
  void reset();
}

List<(double, double, double)>? sampleCskCellsFromCamera(CameraImage image);
```

| Item | Detail |
|---|---|
| Colours | red `0xFFFF1414`, green `0xFF14DC28`, blue `0xFF1E50FF`, white `0xFFFFFFFF`. |
| `cellsForByte(b)` | Cells carry bits 7–6, 5–4, 3–2, 1–0. |
| `frameEnvelope(env)` | Preamble `00 55 AA FF`, 2-byte little-endian length, envelope. |
| `classifyRgb` | Returns −1 (guard) when the brightest channel is below 48, else the nearest colour's dibit. |
| `packFrame(cells)` | −1 if 3 or more cells are black, `null` if some (but fewer than 3) are black, else the packed byte. |
| `OpticalCskDecoder` | Commits a byte after one sample following a guard; ignores repeats of the last byte until a guard is seen; keeps at most 2048 bytes. `pollEnvelope` finds the preamble and returns the payload once complete. |
| `sampleCskCellsFromCamera` | Averages a 6 × 6 grid of samples in each quadrant of the frame, inset 18 % from each edge, converting YUV to RGB (BT.601 integer maths). |

---

## 11. physical/fountain module

Folder: `lib/core/physical/fountain/`. The rateless LT code shared by Light and Sound, the APCF Light frame, the QR bitmap builder and the fountain QR modem. Theory and proofs are in [Fountain Code](../algorithms/FOUNTAIN_CODE.md); the Light pipeline is in [Light Channel](../channels/LIGHT_CHANNEL.md).

### 11.1 `lib/core/physical/fountain/lt_codec.dart`

A systematic Luby Transform encoder and an exact incremental Gauss–Jordan decoder over GF(2). It has no Flutter dependency and is web-safe.

```dart
class LtEncoder {
  LtEncoder({
    required Uint8List data,
    required int blockLen,
    required int sessionId,
  });

  static const denseMaxK = 256;
  final Uint8List data;        // private copy of the input
  final int blockLen;
  final int sessionId;
  late final int K;
  late final int fileLen;

  Uint8List symbolAt(int symbolIndex);
  static List<int> neighborsFor(int sessionId, int symbolIndex, int k);
  static int sparseDegree(int k);
}

class LtDecoder {
  LtDecoder({
    required int K,
    required int blockLen,
    required int fileLen,
    required int sessionId,
  });

  final int K;
  final int blockLen;
  final int fileLen;
  final int sessionId;
  int newSymbols;
  int duplicateSymbols;
  int redundantSymbols;

  int get recoveredCount;
  int get rank;
  bool get isComplete;
  double get progress;
  bool addSymbol(int symbolIndex, Uint8List payload);
  Uint8List? takeBytes();
  void reset();
}
```

| Member | Behaviour |
|---|---|
| `LtEncoder` constructor | Asserts `blockLen > 0`. `K = ceil(data.length / blockLen)`, or 1 for empty data. Blocks are zero-padded. |
| `symbolAt(i)` | For `i < K` returns a copy of block `i`. For `i ≥ K` returns the XOR of the blocks in `neighborsFor(sessionId, i, K)`. Any non-negative index is valid; the stream is endless. |
| `neighborsFor(sid, i, k)` | Deterministic neighbour list, sorted ascending. `k ≤ 0` → empty. `i < k` → `[i]`. `k == 1` → `[0]`. `k ≤ 8` → cycles through a session-keyed shuffle of all `2^k − 1` non-empty subsets. `k ≤ 256` → uniformly random non-empty subset (one 32-bit draw per 32 blocks, redrawn if empty). Larger `k` → `sparseDegree(k)` distinct random blocks. |
| `sparseDegree(k)` | `min(k ~/ 2, ceil(2·ln k) + 8)`. For example 20 at K = 257 and 23 at K = 1133. |
| `LtDecoder` constructor | Asserts `K > 0`, `blockLen > 0`, `fileLen ≥ 0`. |
| `addSymbol(i, payload)` | Returns `false` without changes if `payload.length != blockLen`. Returns `false` and counts `duplicateSymbols` for a repeated index. Returns `false` and counts `redundantSymbols` if already complete or if the symbol reduces to zero. Otherwise stores a new pivot, back-eliminates it, counts `newSymbols` and returns `true`. The payload is copied. |
| `rank` / `isComplete` / `progress` | `rank` is the number of independent symbols; complete at `rank ≥ K`; `progress = rank / K`. |
| `recoveredCount` | Blocks already isolated (a row with a single bit). It can be lower than `rank` until the end. |
| `takeBytes()` | `null` until complete; then the file trimmed to `fileLen`. It can be called more than once. |
| `reset()` | Clears all rows, seen indices and counters. |

The encoder and decoder must agree on `K`, `blockLen` and `sessionId`. Changing the neighbour mapping breaks compatibility; that is why the APCF version was raised to 3.

**Used by:** `FountainQrModem` (sessions keyed by 32-bit id), `AcousticFountainModem` (sessions keyed by an 8-bit id).

Round trip with 30 % of symbols lost:

```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:adaptive_physical_communication/core/physical/fountain/lt_codec.dart';

final data = Uint8List.fromList(List.generate(5000, (i) => i * 7 & 0xFF));
final enc = LtEncoder(data: data, blockLen: 160, sessionId: 0xABCDEF01);   // K = 32
final dec = LtDecoder(K: enc.K, blockLen: enc.blockLen, fileLen: enc.fileLen, sessionId: enc.sessionId);

final rng = Random(1);
for (var i = 0; !dec.isComplete; i++) {
  if (rng.nextDouble() < 0.30) continue;          // this frame was never seen
  dec.addSymbol(i, enc.symbolAt(i));
}
assert(dec.newSymbols == enc.K);                  // exactly K useful symbols
final out = dec.takeBytes()!;                     // byte-identical to data
```

### 11.2 `lib/core/physical/fountain/qr_fountain_frame.dart`

The APCF v3 frame: one LT symbol plus its session parameters and a CRC-32, sized to fit one QR code.

| Constant | Value |
|---|---|
| `qrFountainMagic` | `[0x41, 0x50, 0x43, 0x46]` ("APCF") |
| `qrFountainVersion` | `3` |
| `qrFountainQrPrefix` | `'FQR3:'` |
| `qrFountainHeaderSize` | `22` |
| `qrFountainCrcSize` | `4` |
| `qrFountainOverhead` | `26` (`22 + 4`) |
| `qrFountainFlagGzip` | `0x01` (defined, never set by the sender, never acted on by the receiver) |

```dart
class QrFountainFrame {
  const QrFountainFrame({
    required int sessionId,
    required int symbolIndex,
    required int k,
    required int blockLen,
    required int fileLen,
    required Uint8List payload,
    int flags = 0,
  });
  bool get isGzip;
  int get encodedLength;       // 26 + payload.length
}

class QrFountainFrameCodec {
  const QrFountainFrameCodec();
  Uint8List encode(QrFountainFrame frame);
  QrFountainFrame? decode(Uint8List raw);
  String encodeToQrString(QrFountainFrame frame);
  QrFountainFrame? decodeFromQrString(String text);
  QrFountainFrame? decodeFromQrBytes(Uint8List bytes);
}

const qrFountainFrameCodec = QrFountainFrameCodec();
```

Big-endian layout: magic (4), version (1), flags (1), sessionId u32, symbolIndex u32, K u16, blockLen u16, fileLen u32, payload (`blockLen` bytes), CRC-32 u32 over everything before it.

| Method | Behaviour |
|---|---|
| `encode` | Throws `ArgumentError('payload length must equal blockLen')` on a mismatch. |
| `decode(raw)` | Returns `null` if shorter than 26 bytes, wrong magic, version ≠ 3, `k < 1`, `blockLen < 1`, too short for the payload, or the CRC fails. Extra trailing bytes (QR padding) are ignored. The payload is copied. |
| `encodeToQrString` | `'FQR3:' + base64Url(encode(frame))`, for text-only decoders. |
| `decodeFromQrString` | Accepts the `FQR3:` form, else tries the string's code units as bytes, else its UTF-8 bytes. The input is `trim()`med first. |
| `decodeFromQrBytes` | `decode(bytes)` first (the normal case), else treats the bytes as text. |

**Used by:** `FountainQrModem` (encode on TX, decode on RX), `OpticalTxProfile.framedSymbolBytes`, tests.

### 11.3 `lib/core/physical/fountain/qr_bitmap.dart`

Builds a QR module grid from raw bytes in true 8-bit byte mode, off the paint path.

```dart
class QrBitmap {
  QrBitmap({required int size, required Uint8List modules, required int typeNumber});
  final int size;              // modules per side, without quiet zone
  final Uint8List modules;     // row-major, 1 = dark
  final int typeNumber;        // QR version 1..40
  bool isDark(int row, int col);
}

QrBitmap buildQrBitmap(
  Uint8List data, {
  int errorCorrectLevel = QrErrorCorrectLevel.L,
  int? maskPattern,
});

({int width, int height, Int8List lum}) rasterizeQrBitmap(
  QrBitmap bitmap, {
  int moduleScale = 4,
  int quietModules = 4,
});
```

- `buildQrBitmap` uses `QrCode.fromUint8List` and picks the smallest version that fits. With `maskPattern` it skips the 8-mask search. It throws whatever `package:qr` throws if the data does not fit version 40.
- `rasterizeQrBitmap` draws an 8-bit luminance image (white is −1, which zxing reads as 255) with integer module scaling and no anti-aliasing. It is used by the headless tests to feed the real decoder.

**Used by:** `FountainQrModem` (TX, with mask 0), `OpticalTransmitterState` (holds the current bitmap), `qr_bitmap_view.dart` and `optical_fountain_qr_overlay.dart` (UI), tests.

### 11.4 `lib/core/physical/fountain/fountain_qr_modem.dart`

The animated fountain QR modem. The sender streams fresh LT symbols as QR codes until stopped; the receiver decodes camera frames in a background isolate and finishes at rank K.

```dart
enum FountainTxEnd { none, stopped, safetyCap }

class FountainQrModem implements OpticalModem {
  FountainQrModem({
    StructuredLogger? logger,
    OpticalMetricsNotifier? metricsNotifier,
    OpticalTxProfile? profile,
    QrDecodeIsolatePool? decodePool,
    QrDecodeWorker? decodeWorker,
  });

  static const maxStreamDuration = Duration(minutes: 10);
  static const maxEnvelopeBytes = 8 * 1024 * 1024;

  final OpticalMetricsNotifier metricsNotifier;
  OpticalTxProfile profile;
  FountainTxEnd lastTxEnd;
  int lastTxFrames;
  Duration lastTxDuration;

  String get id;                  // 'fountain_qr'
  String get label;               // 'Fountain QR'
  int get maxPayloadBytes;        // maxEnvelopeBytes
  OpticalTransferMetrics get metrics;
  (int received, int total)? get chunkProgress;   // (rank, K) of the current session

  static int sessionIdFor(Uint8List envelope, int blockLen);
  // plus every OpticalModem member
}
```

Private constants you will see in behaviour: the TX mask pattern is `0`, and the receiver keeps at most `3` partial sessions.

**Transmit** — `Future<void> transmit(Uint8List envelope)`:

- Throws `ArgumentError('Payload too large for fountain QR (… B)')` above `maxEnvelopeBytes`.
- Resolves the profile with `profile.resolveFor(envelope.length)`, computes `sessionIdFor(envelope, blockLen)` and builds an `LtEncoder`.
- `frameMs = max(40, round(1000 / txFps))`: 83 ms at 12 fps, 125 ms at 8 fps.
- Side effects: enables the wakelock (native), sets maximum screen brightness (`OpticalDisplayControl`), sets `opticalTransmitterState.transmitting = true` and publishes the session, then pushes each `QrBitmap` with `setFountainQrBitmap`.
- The loop shows symbol `i`, builds symbol `i + 1` while `i` is on screen, and sleeps the rest of the frame. The first frame is held `frameMs + 250` ms for autofocus.
- It continues while not cancelled, `opticalTransmitterState.transmitting` is true, and elapsed time is under 10 minutes. The returned `Future` completes only when the stream ends.
- On exit it records `lastTxEnd` (`safetyCap` or `stopped`), `lastTxFrames` and `lastTxDuration`; remembers the next unshown index for this session (up to 16 sessions) so the next `transmit` of the same content continues with new symbols; clears the transmitter state; restores brightness; and releases the wakelock if the receiver is not running.

`sessionIdFor(envelope, blockLen)` = `(computeCrc32(envelope) ^ (blockLen * 0x9E3779B1)) & 0xFFFFFFFF`, with 0 replaced by 1. The same content at the same density always gets the same session.

`cancelTransmit()` clears the internal flag and `opticalTransmitterState.transmitting`, so the loop exits after the current sleep.

**Receive:**

| Member | Behaviour |
|---|---|
| `startReceiver()` | Keeps any partial sessions, resets fps counters and stats, starts the `QrDecodeWorker`, enables the wakelock (native), and starts a **500 ms** `Timer.periodic` that refreshes the fps window so the HUD updates even when nothing decodes. |
| `stopReceiver()` | Cancels the timer and releases the wakelock unless transmitting. Partial sessions survive. |
| `onCameraFrame(image)` | Counts a capture. If the worker is busy, returns without copying. Otherwise copies with `extractQrGrayFrame(targetPx: profile.decodeTargetPx)` and decodes asynchronously. |
| `onWebSampleTick()` | Counts a capture and decodes the browser preview through `QrDecodeIsolatePool.submitWebPreview`. |
| Frame ingest | Parses with `qrFountainFrameCodec`. Ignores sessions already completed. Creates a new `LtDecoder` when the session is new or its K, blockLen or fileLen changed, evicting the oldest beyond 3 sessions. On completion it requires the APCM magic (`isApcmEnvelope`), marks the session complete, de-duplicates by CRC-32 against the last delivered envelope, queues the envelope, sets `opticalTransmitterState` confidence to 1.0 and publishes final metrics. Full APCM validation happens later in `ChatPayloadCodec.decodeIncoming`. |
| `takeEnvelopes()` | Returns and clears completed envelopes. |
| `clearReceiveCaches({resetDedup})` | Always clears queued envelopes. With `resetDedup: true` it also drops partial sessions, the completed-session list, the dedup CRC, stats and metrics. |
| `dispose()` | Cancels the timer, disposes the worker and the notifier. |

Metrics published to `metricsNotifier`: `captureFps` and `decodeFps` over windows of at least 400 ms (normally the 500 ms timer), `dropped` from the worker and pool, `goodputKBps` (useful symbols × blockLen ÷ elapsed; on completion fileLen ÷ elapsed), `framesNew/Dup/Red` from the decoder, `symbolsCollected = rank`, `symbolsNeeded = K`, `locked` when a session is current, and `stalled` when not complete, `captureFps > 2`, and 4 consecutive windows had captures but no decodes.

**Used by:** `HardwareOpticalChannel` (default modem), `AppController` (`_opticalStreamSummary` reads `lastTxEnd`, `lastTxFrames`, `lastTxDuration`; `maxEnvelopeBytes` check).

The modem touches the wakelock, the brightness MethodChannel and global UI state, so in practice you drive it through `HardwareOpticalChannel`. Direct use looks like this:

```dart
final modem = FountainQrModem(profile: OpticalTxProfile.auto);

// Sender: runs until cancelTransmit() or the 10-minute cap.
final envelope = ChatPayloadCodec.encodeText('Hello from light!');
final streaming = modem.transmit(envelope);       // shows QR frames via opticalTransmitterState
// ... when the receiver shows DONE:
modem.cancelTransmit();
await streaming;
print('${modem.lastTxFrames} frames, ended: ${modem.lastTxEnd}');

// Receiver: feed camera frames, then drain envelopes (the channel polls every 80 ms).
await modem.startReceiver();
cameraController.startImageStream(modem.onCameraFrame);
for (final env in modem.takeEnvelopes()) {
  final msg = ChatPayloadCodec.decodeIncoming(env, isOutgoing: false);
}
```

The channel-level equivalents are `HardwareOpticalChannel.transmitEnvelope` and `HardwareOpticalChannel.receiveEnvelopes`.

---

## 12. physical/acoustic module

Folder: `lib/core/physical/acoustic/`. The Sound modem: multi-tone FSK waveform, per-frame sync, Reed-Solomon, the frame format, speed profiles and the rateless modem. See [Sound Channel](../channels/SOUND_CHANNEL.md) and [Reed-Solomon](../algorithms/REED_SOLOMON.md).

### 12.1 `lib/core/physical/acoustic/mt_fsk_codec.dart`

Multi-tone FSK modulation and Goertzel demodulation with soft outputs.

```dart
class MtFskCodec {
  MtFskCodec({
    int sampleRate = 44100,
    int frameSamples = 1024,
    int baseBin = 40,
    int groups = 6,
    int framesPerSymbol = 4,
    int markerFrames = 2,
    int toneSpacing = 1,
    int guardFrames = 0,
    bool sequentialMarker = false,
    double peakAmplitude = 0.98,
    int? syncBinA,
    int? syncBinB,
  });

  final int syncBinA;           // default baseBin - 12  (28 → 1205.9 Hz)
  final int syncBinB;           // default baseBin - 4   (36 → 1550.4 Hz)
  double get bytesPerSymbol;    // groups / 2  (0.5 for one group)
  int get samplesPerSymbol;     // frameSamples * framesPerSymbol
  int get samplesPerMarker;     // frameSamples * markerFrames
  double get binHz;             // sampleRate / frameSamples  (43.066 Hz)
  double get symbolMs;
  double get rawBytesPerSecond;
  double get lowestHz;          // lowest tone, sync included
  double get highestHz;

  int binFor(int group, int value);           // baseBin + (16*group + value) * toneSpacing
  double frequencyFor(int group, int value);
  int symbolsForBytes(int byteCount);         // ceil(2 * byteCount / groups)
  int samplesForBytes(int byteCount);

  Float32List encode(Uint8List payload);
  void describe(Uint8List payload, ToneTimeline into);
  double markerScore(Float32List samples, int start);
  double symbolConfidence(Float32List samples, int start, {int? groupLimit});
  ({List<int> nibbles, double confidence}) decodeSymbol(Float32List samples, int start);
  ({Uint8List bytes, double confidence}) decodeBytes(Float32List samples, int start, int byteCount);
  ({Uint8List bytes, double confidence, Float64List reliability}) decodeBytesSoft(
    Float32List samples, int start, int byteCount);
}
```

| Member | Behaviour |
|---|---|
| Constructor | Asserts `groups ≥ 1`, `framesPerSymbol ≥ 1`, `0 ≤ guardFrames < framesPerSymbol`, `toneSpacing ≥ 1`, an even `markerFrames` when `sequentialMarker`, and `0 < peakAmplitude ≤ 1`. Odd `groups` are allowed: with one group a byte spans two symbols. Precomputes one Goertzel coefficient per tone (16 per group). The defaults reproduce the audible plan exactly. |
| `encode(payload)` | A marker for `samplesPerMarker` samples (both sync tones together, or with `sequentialMarker` tone A in the first half and tone B in the second), then the data symbols. Nibble `s·groups + g` goes to group `g` of symbol `s`, high nibble first. Each tone has amplitude `peakAmplitude / (tones sounding)`. Missing trailing bytes are zeros. |
| `describe(payload, into)` | Appends to `into` what `encode(payload)` would play, without synthesising audio: two marker halves (`ToneKind.marker`), then one `ToneKind.data` segment per symbol listing its tone frequencies in Hz. It shares `_markerBins` and `_symbolBins` with `encode`, so the two can't disagree, and the timeline's length equals `encode(payload).length`. |
| `markerScore(samples, start)` | 0 if out of range or silent. Otherwise, for each half of the marker window, `(tones in that half) · weakest tone power / meanSquare`; returns the lower half. An ideal aligned marker scores about 512 in both marker styles. |
| `symbolConfidence` | Mean over the first `groupLimit` groups of best-tone power ÷ total group power, over the analysis window. Used to fine-tune alignment. |
| `decodeBytesSoft` | Hard decision per group (strongest of 16 tones), measured only after the first `guardFrames` frames of each symbol. Nibbles are packed into bytes for any group count. Per-byte reliability = the lower margin `1 − second/best` of its two nibbles; bytes whose symbols never arrived keep reliability 0. `confidence` = mean best/total. Stops early if the samples run out. |

**Used by:** `AcousticTxProfile.buildCodec`, `AcousticFrameSync`, `AcousticFountainModem`.

### 12.2 `lib/core/physical/acoustic/reed_solomon.dart`

A systematic Reed-Solomon codec over GF(256) with errors-and-erasures decoding.

```dart
class ReedSolomon {
  ReedSolomon(int parityBytes);
  final int parityBytes;
  int get correctableBytes;     // parityBytes ~/ 2
  int maxDataLength();          // 255 - parityBytes
  Uint8List encode(Uint8List data);
  Uint8List? decode(Uint8List codeword, {int? dataLength, List<int> erasures = const []});
}
```

| Member | Behaviour |
|---|---|
| Field | Primitive polynomial `0x11D` (x⁸+x⁴+x³+x²+1), generator α = 2. Tables are built once, lazily. |
| Constructor | Asserts `0 < parityBytes < 255`. Builds g(x) = ∏(x − αⁱ) for i = 0 … P−1. |
| `encode(data)` | Returns `data` followed by `parityBytes` parity bytes. Throws `ArgumentError('data of … B exceeds RS limit of … B')` above `maxDataLength()`. |
| `decode(codeword, ...)` | Returns a view of the corrected data, or `null` if the damage is beyond repair. `dataLength` defaults to `codeword.length − parityBytes`; the call returns `null` if they do not add up. Without erasures: Berlekamp–Massey, Chien search, Forney. With erasures: Berlekamp–Massey seeded with the erasure locator; it succeeds when `2·errors + erasures ≤ parityBytes`. Out-of-range and duplicate erasure positions are ignored; more distinct erasures than parity bytes → `null`. The syndromes are re-checked after correction. The input is not modified. |

**Used by:** `AcousticFrameCodec`.

```dart
import 'dart:typed_data';
import 'package:adaptive_physical_communication/core/physical/acoustic/reed_solomon.dart';

final rs = ReedSolomon(24);                                   // the Standard profile's parity
final data = Uint8List.fromList(List.generate(75, (i) => i));
final word = rs.encode(data);                                 // 99 bytes

final damaged = Uint8List.fromList(word);
for (var i = 0; i < 12; i++) { damaged[i * 7] ^= 0x5A; }     // 12 unknown errors = limit
assert(rs.decode(damaged, dataLength: 75) != null);

final erased = Uint8List.fromList(word);
final suspects = List.generate(24, (i) => i * 4);             // 24 known-bad positions
for (final p in suspects) { erased[p] = 0; }
assert(rs.decode(erased, dataLength: 75, erasures: suspects) != null);   // 2·0 + 24 ≤ 24
```

### 12.3 `lib/core/physical/acoustic/acoustic_fountain_frame.dart`

The Sound frame format (9-byte header, LT payload, CRC-16) and the codec that wraps it in Reed-Solomon, including GMD erasure retries.

| Constant | Value |
|---|---|
| `acousticHeaderSize` | `9` |
| `acousticCrcSize` | `2` |
| `acousticFrameOverhead` | `11` |
| `AcousticFrameCodec.gmdStep` | `4` |
| `AcousticFrameCodec.gmdReserve` | `4` |

```dart
class AcousticFrame {
  const AcousticFrame({
    required int sessionId,        // 8 bits on the wire
    required int symbolIndex,      // 16 bits
    required int k,                // 16 bits
    required int blockLen,         // 8 bits
    required int fileLen,          // 24 bits
    required Uint8List payload,
  });
}

class AcousticFrameCodec {
  AcousticFrameCodec({required int parityBytes});
  final int parityBytes;
  int get correctableBytes;
  int codewordLength(int blockLen);             // 11 + blockLen + parityBytes
  Uint8List encode(AcousticFrame frame);
  AcousticFrame? decode(Uint8List codeword, {required int blockLen, Float64List? reliability});
}

int crc16(Uint8List data);                      // CRC-16/CCITT-FALSE
```

Big-endian body: symbolIndex u16, K u16, blockLen u8, fileLen u24, sessionId u8, payload, CRC-16 over the header and payload. Reed-Solomon parity follows.

| Member | Behaviour |
|---|---|
| `encode` | Throws `ArgumentError('payload length must equal blockLen')` on a mismatch. Values wider than their field are truncated by masking. |
| `decode` | Returns `null` if the codeword is shorter than `codewordLength(blockLen)`. Tries a plain RS decode. If that fails and `reliability` is given, retries with the 4, 8, 12, … least reliable positions erased, up to `parityBytes − 4`. A candidate is accepted only if the CRC-16 matches, the header's blockLen equals `blockLen`, and K ≥ 1. |
| `crc16` | Polynomial `0x1021`, init `0xFFFF`, MSB-first, no reflection, no final XOR. |

**Used by:** `AcousticTxProfile.buildFrameCodec`, `AcousticFrameSync`, `AcousticFountainModem`.

### 12.4 `lib/core/physical/acoustic/acoustic_tx_profile.dart`

The two Sound bands, the six speed profiles and their derived rates.

```dart
enum AcousticBand {
  audible,          // label 'Audible', baseBin 40, toneSpacing 1, sync 28/36, chords, peak 0.98
  nearUltrasonic;   // label 'Silent', baseBin 431, toneSpacing 2, sync 424/427, sequential marker, peak 0.8

  final String label;
  final int baseBin, toneSpacing, syncBinA, syncBinB;
  final bool sequentialMarker;
  final double peakAmplitude;
  final double? receiveHighPassHz;   // null (audible) or 16000 (Silent)
}

class AcousticTxProfile {
  const AcousticTxProfile({
    required String id,
    required String label,
    required int groups,
    required int framesPerSymbol,
    required int blockLen,
    required int parityBytes,
    AcousticBand band = AcousticBand.audible,
    int guardFrames = 0,
  });

  static const rugged, safe, standard, fast, silentRobust, silent;
  static const audibleValues = [rugged, safe, standard, fast];   // slowest to fastest
  static const silentValues = [silentRobust, silent];
  static const values = [...audibleValues, ...silentValues];     // everything a receiver hears

  bool get isSilent;                     // band == nearUltrasonic
  MtFskCodec buildCodec();               // passes the band's tone plan
  AcousticFrameCodec buildFrameCodec();
  int get codewordLength;                // 11 + blockLen + parityBytes
  double netBytesPerSecond();            // blockLen / frameSeconds()
  double frameSeconds();
  String get conditionHint;
  AcousticTxProfile get slower;
  static List<AcousticTxProfile> forBand(AcousticBand band);
  static AcousticTxProfile defaultFor(AcousticBand band);   // standard or silent
  static AcousticTxProfile byId(String id);
}
```

| Constant | `id` | Band | `groups` | `framesPerSymbol` (guard) | `blockLen` | `parityBytes` | Codeword | `frameSeconds()` | `netBytesPerSecond()` |
|---|---|---|---|---|---|---|---|---|---|
| `rugged` | `'rugged'` | audible | 6 | 6 | 32 | 20 | 63 | 2.972 s | 10.8 |
| `safe` | `'safe'` | audible | 6 | 4 | 48 | 24 | 83 | 2.647 s | 18.1 |
| `standard` | `'standard'` | audible | 8 | 4 | 64 | 24 | 99 | 2.368 s | 27.0 |
| `fast` | `'fast'` | audible | 8 | 3 | 64 | 24 | 99 | 1.788 s | 35.8 |
| `silentRobust` | `'silent_robust'` | nearUltrasonic | 1 | 3 (1) | 24 | 16 | 51 | 7.152 s | 3.4 |
| `silent` | `'silent'` | nearUltrasonic | 1 | 2 (1) | 24 | 16 | 51 | 4.783 s | 5.0 |

The last two columns are computed by the methods (see the README's worked calculation). `conditionHint`: rugged `'Loud room, phones metres apart'`, safe `'Background noise or chatter'`, fast `'Quiet room, phones touching'`, silent `'Inaudible 18–20 kHz, phones within arm's reach'`, silent_robust `'Inaudible, weak speaker or a loud crowd'`, anything else `'Normal room, across a table'`. `slower` steps one place down its own band's list and never crosses bands (rugged and silentRobust stay put). `byId` falls back to `standard`. `==` compares `id` only.

**Used by:** `AcousticFountainModem`, `AcousticFrameSync`, `HardwareAcousticChannel`, `AppController` (`acousticTxProfile`, `acousticEtaSeconds`), `send_transmit_screen.dart` and `acoustic_transfer_hud.dart` (band switch, speed chips, frame breakdown).

### 12.4a `lib/core/physical/acoustic/biquad_filter.dart`

IIR high-pass filtering for the Silent receiver and the high-band level meter.

```dart
class Biquad {
  Biquad.highPass({required double cutoffHz, required double q, int sampleRate = 44100});
  void process(Float32List samples);    // in place; state carries across calls
  void reset();
}

class HighPassFilter {                  // 4th-order Butterworth: Q 0.5412 and 1.3066
  HighPassFilter({required double cutoffHz, int sampleRate = 44100});
  Float32List apply(Float32List samples);   // filtered copy; input untouched
  void reset();
}
```

`Biquad` uses the RBJ cookbook coefficients in transposed direct form II, so a stream filtered chunk by chunk gives the same output as in one piece. `HighPassFilter.apply` returns a copy because one microphone chunk is shared by every profile's frame-sync.

**Used by:** `AcousticFrameSync` (profiles whose band has `receiveHighPassHz`), `HardwareAcousticChannel` (the *Silent band* meter).

### 12.4b `lib/core/physical/acoustic/tone_timeline.dart`

The schedule of tones in one rendered burst, for the sender's live readout.

```dart
enum ToneKind { silence, marker, data }

class ToneTimeline {
  ToneTimeline({required int sampleRate});

  final int sampleRate;
  int get totalSamples;
  Duration get duration;
  int get segmentCount;

  void addSilence(int samples);                              // merges with a preceding silence
  void addTones(int samples, ToneKind kind, List<double> hz);
  ({ToneKind kind, Float32List hz})? at(int sample);         // null outside [0, totalSamples)
  ({ToneKind kind, Float32List hz})? atTime(Duration elapsed);
}
```

Segments are stored as cumulative end positions, so `at` is a binary search. A zero-length segment is ignored. Silence segments share one empty list. A Standard burst of four frames is about 110 segments.

**Used by:** `MtFskCodec.describe`, `AcousticFountainModem.transmit` (`onBurst`), `HardwareAcousticChannel._playWav`, `AcousticSpectrumState`.

### 12.4c `lib/core/physical/acoustic/spectrum_analyzer.dart`

A windowed FFT over the latest microphone audio, for the receiver's live readout.

```dart
class SpectrumSnapshot {
  final Float32List bands;       // loudest level per band, −100…−20 dBFS mapped to 0…1
  final double bandHz;           // width of one band
  final List<double> peaksHz;    // distinct tones, strongest first
  final double? peakDbfs;        // level of the strongest tone
  double? get strongestHz;
  static final SpectrumSnapshot empty;
}

class SpectrumAnalyzer {
  SpectrumAnalyzer({
    int size = 1024,             // power of two
    int sampleRate = 44100,
    int bandCount = 96,
    double minPeakHz = 500,
    double maxPeakHz = 21000,
    int maxPeaks = 8,
  });

  static const floorDbfs = -100.0;
  static const ceilingDbfs = -20.0;
  static const peakMarginDb = 18.0;
  static const peakMinDbfs = -85.0;

  double get binHz;              // 43.066 Hz at the defaults
  void add(Float32List samples); // copy into the ring only
  void reset();
  SpectrumSnapshot analyze();    // empty until the ring has been filled once
}
```

| Member | Behaviour |
|---|---|
| `add` | Copies samples into a ring of `size`. It does no maths, so it is safe to call on every microphone chunk. |
| `analyze` | Hann window, then an in-place iterative radix-2 FFT with precomputed twiddles. Power is scaled so that a full-scale sine reads 0 dBFS. |
| Bands | `bandCount` equal-width bands from 0 Hz to Nyquist, each the loudest bin inside it. |
| Peaks | Local maxima between `minPeakHz` and `maxPeakHz` that are at least `peakMarginDb` above the median bin and at or above `peakMinDbfs`. Taken strongest first, a peak is dropped if it is within 4 bins of one already kept (window leakage) or more than 35 dB below the strongest. Each position is refined by a parabola through the dB values of the peak bin and its neighbours. |

**Used by:** `HardwareAcousticChannel` (writes `acousticSpectrumState.rx`).

### 12.5 `lib/core/physical/acoustic/acoustic_frame_sync.dart`

A streaming receiver for one profile. It finds frame markers in microphone audio, aligns and demodulates each frame, and repairs it.

```dart
class AcousticFrameSync {
  AcousticFrameSync({
    required AcousticTxProfile profile,
    double markerThreshold = 8.0,
    int searchStep = 64,
  });

  final AcousticTxProfile profile;
  final double markerThreshold;
  final int searchStep;
  int markersFound;
  int framesRepaired;
  int framesRejected;
  double lastConfidence;
  int lastMarkerSample;
  int lastDataStartSample;

  MtFskCodec get codec;
  int get dataSymbols;          // symbolsForBytes(codewordLength)
  int get frameSamples;         // marker + dataSymbols * samplesPerSymbol

  void addSamples(Float32List chunk);
  List<AcousticFrame> takeFrames();
  void reset();
  void resetStats();
}
```

`addSamples` first high-passes the chunk if the profile's band sets `receiveHighPassHz` (Silent: 16 kHz, filter state kept across chunks and cleared by `reset()`), then appends it to a growable buffer (starting at 2¹⁵ samples, doubling) and processes it:

1. Scan from the cursor in `searchStep` (64-sample) steps until `markerScore ≥ markerThreshold` (8.0).
2. Within the next marker length, find the peak score and take the **first** probe reaching 50 % of it (the leading edge).
3. If the whole frame plus the refinement span is not buffered yet, wait for more audio.
4. Refine the data start by up to ±`min(samplesPerSymbol ~/ 8, 512)` samples in 64-sample steps, maximising `symbolConfidence` over 3 groups.
5. Demodulate with `decodeBytesSoft` and decode with `AcousticFrameCodec.decode` (with reliabilities). Count `framesRepaired` or `framesRejected`.
6. Move the cursor past the frame and compact the buffer.

`takeFrames()` returns and clears recovered frames. `reset()` clears the buffer; `resetStats()` clears the counters.

**Used by:** `AcousticFountainModem` (one instance per listened profile).

### 12.6 `lib/core/physical/acoustic/acoustic_fountain_modem.dart`

The rateless Sound modem: LT symbols across frames, Reed-Solomon within each frame, and automatic detection of the sender's profile.

```dart
class AcousticRxProgress {
  const AcousticRxProgress({
    required int collected,
    required int needed,
    required int framesRepaired,
    required int framesRejected,
    required bool complete,
  });
  static const idle;
  bool get active;              // needed > 0 && !complete
  double get fraction;          // collected / needed, clamped
}

class AcousticFountainModem {
  AcousticFountainModem({
    AcousticTxProfile profile = AcousticTxProfile.standard,
    bool autoDetectProfile = true,
    StructuredLogger? logger,
  });

  static const staleLockMarkers = 4;
  final bool autoDetectProfile;

  AcousticTxProfile get profile;
  set profile(AcousticTxProfile value);
  AcousticRxProgress get progress;
  bool get transmitting;
  int get txSymbolsSent;
  int get txSymbolsNeeded;
  AcousticTxProfile? get rxProfile;

  void startReceive();
  void stopReceive();
  void addSamples(Float32List samples);
  List<Uint8List> takeEnvelopes();
  void clearReceiveCaches({bool resetDedup = false});

  Future<void> transmit({
    required Uint8List envelope,
    required Future<void> Function(Uint8List wav) play,
    bool Function()? shouldContinue,
    void Function(int sent, int needed)? onProgress,
    void Function(ToneTimeline tones)? onBurst,
    int? maxSymbols,
  });
  void cancelTransmit();
  double estimateSeconds(int envelopeBytes);

  static int expectedSymbols(int k);     // ceil(1.25·k) + 2
  static int symbolBudget(int k);        // max(6·k, k + 24)
  static void applyEdgeFades(Float32List samples, int start, int end, {int fadeSamples = 256});
}

Float32List pcm16ToFloat32(Uint8List chunk);
```

**Receive:**

| Member | Behaviour |
|---|---|
| `startReceive()` | Clears listeners, decoders and counters and listens on every profile (or only `profile` when `autoDetectProfile` is false). |
| `addSamples(samples)` | Does nothing if not receiving. Feeds every active `AcousticFrameSync`. With auto-detect, the first profile that yields a good frame from a not-yet-finished session becomes the lock and the others are dropped. If the locked profile hears 4 markers (`staleLockMarkers`) without a good frame, all profiles are heard again. Frames feed one `LtDecoder` per 8-bit session id. A finished session is added to a "done" set, de-duplicated by CRC-32, queued, and (with auto-detect, when no other session is open) all profiles are heard again. Rejected frames are counted only while a single profile is listening. |
| `progress` | From the decoder with the most **recovered blocks**: `collected = recoveredCount`, `needed = K`. |
| `rxProfile` | The locked profile with auto-detect (null while hunting), else `profile` while receiving. |
| `profile` setter | Changes the TX profile. Without auto-detect it also restarts the receiver on the new profile. |
| `takeEnvelopes()` | Returns and clears finished envelopes. |
| `clearReceiveCaches({resetDedup})` | Resets every sync buffer, decoders and queued envelopes. With `resetDedup` it also forgets the dedup CRC and the done sessions. |
| `stopReceive()` | Drops all listeners, the lock and the decoders. |

**Transmit** — `transmit(...)`:

- The session id is `(millisecondsSinceEpoch ~/ 97) & 0xFF`, new for every call.
- `needed = expectedSymbols(K)` is reported to `onProgress` for the progress bar only. The stream stops at `maxSymbols ?? symbolBudget(K)`.
- It renders bursts of `max(2, min(4, K))` frames, each burst starting with **0.12 s** of silence and ending with a **40 ms** tail, fades the audio in and out with `applyEdgeFades`, converts each burst with `pcmToWav` and awaits `play(wav)`.
- With `onBurst`, each burst also gets a `ToneTimeline` (lead silence, then `MtFskCodec.describe` for every frame, then the tail), passed to `onBurst` just before `play`. Without it no timeline is built.
- `applyEdgeFades(samples, start, end)` applies raised-cosine ramps of `fadeSamples` (256, 5.8 ms) at both ends of `[start, end)`, so a burst never starts or stops with a click. For Silent profiles a click would be the only audible part.
- It stops when `cancelTransmit()` is called, `shouldContinue()` returns false, or the budget is reached. Returns when the last burst has played.

`estimateSeconds(bytes)` = `expectedSymbols(ceil(bytes / blockLen)) × frameSeconds()`.

`pcm16ToFloat32(chunk)` converts little-endian PCM16 to floats by dividing by 32768.

**Used by:** `HardwareAcousticChannel` (fountain mode), `AppController.acousticEtaSeconds` (the static helpers).

Loopback example (the same pattern as `test/acoustic_modem_test.dart`, without the room model):

```dart
import 'dart:typed_data';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_modem.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';

final tx = AcousticFountainModem(profile: AcousticTxProfile.standard);
final rx = AcousticFountainModem()..startReceive();          // detects the sender's profile
final received = <Uint8List>[];

await tx.transmit(
  envelope: ChatPayloadCodec.encodeText('Hello from sound!'), // 24-byte envelope, K = 1
  play: (wav) async {
    rx.addSamples(pcm16ToFloat32(Uint8List.sublistView(wav, 44)));  // skip the WAV header
    received.addAll(rx.takeEnvelopes());
  },
  shouldContinue: () => received.isEmpty,
);
assert(received.length == 1);
// rxProfile is null again here: after a message completes the receiver
// listens for every profile, because the next sender may pick another speed.
```

---

## 13. physical/csk module

Folder: `lib/core/physical/csk/`. The legacy colour-shift-keying Light modem. It is kept working but the current UI never selects it. See the legacy modems notes in [Light Channel](../channels/LIGHT_CHANNEL.md).

### 13.1 `lib/core/physical/csk/csk_optical_modem.dart`

```dart
class CskOpticalModem implements OpticalModem {
  CskOpticalModem({StructuredLogger? logger, OpticalMetricsNotifier? metricsNotifier});
  final OpticalMetricsNotifier metricsNotifier;
  String get id;                          // 'csk'
  String get label;                       // 'Color Shift Keying'
  int get maxPayloadBytes;                // hardwareOpticalCskMaxBytes (180)
  (int received, int total)? get chunkProgress;
  int get bytesSeen;
  // plus every OpticalModem member
}
```

| Member | Behaviour |
|---|---|
| `transmit(env)` | Throws `ArgumentError('Message too large for CSK light (… B). Use short text.')` above 180 bytes. Frames with `opticalCskCodec.frameEnvelope`, waits the 250 ms lead, then shows each byte for 140 ms followed by a 20 ms black guard, repeating the whole frame 3 times with 400 ms gaps. Cells are published through `opticalTransmitterState.setCskSymbol` and `setCskGuard`. Stops early when `opticalTransmitterState.transmitting` turns false. Holds the wakelock while sending. |
| `onCameraFrame(image)` | Samples at most every **45 ms** with `sampleCskCellsFromCamera`, then packs and feeds `OpticalCskDecoder`. |
| `onWebSampleTick()` | Uses `sampleCskCellsFromPreview`. |
| Completion | A decoded payload with the APCM magic is de-duplicated by CRC-32, queued and reported as complete in the metrics; anything else is logged as a warning. |
| `cancelTransmit()` | Clears `opticalTransmitterState.transmitting`. |

**Used by:** `HardwareOpticalChannel` when `OpticalModemKind.csk` is selected.

---

## 14. platform module

Folder: `lib/core/platform/`. Platform detection, the physical-only policy, the `ChangeNotifier` singletons that connect channels to the UI, and the brightness MethodChannel.

### 14.1 `lib/core/platform/platform_capabilities.dart`

```dart
class OpticalTransmitterState extends ChangeNotifier {
  bool get transmitting;
  List<Color>? get cskCells;
  bool get showingGuard;
  int get chunkIndex;
  int get chunkTotal;
  double get confidence;
  String get modemId;                 // 'fountain_qr' (default) or 'csk'
  bool get isFountainQr;
  String? get qrPayload;
  QrBitmap? get qrBitmap;
  String? get fountainSessionId;
  int get fountainK;
  int get fountainBlockLen;
  int get fountainFileLen;
  String get profileLabel;            // default 'Standard'

  void setModemId(String id);
  void setTransmitting(bool value);
  void setCskSymbol({required List<Color> cells, required int index, required int total});
  void setCskGuard({required int index, required int total});
  void setFountainSession({required String sessionId, required int k, required int blockLen,
                           required int fileLen, required String profileLabel});
  void setFountainQrFrame({required String payload, required int index, required int total});
  void setFountainQrBitmap({required QrBitmap bitmap, required int index, required int total});
  void setQrFrame({required String payload, required int index, required int total});
  void clearCsk();
  void clearFountain();
  void clearQr();
  void setConfidence(double value);
  void resetScanFeedback();
}

final opticalTransmitterState = OpticalTransmitterState();
VoidCallback? onOpticalTransmitCancel;

bool get isHardwarePlatform;
bool get isPhysicalChannelSupported;
bool get isVibrationSupported;
const String physicalOnlyPolicySummary;
const List<String> excludedNetworkTransports;
String get platformCapabilityLabel;
String get platformCapabilitySummary;
List<String> get hardwarePairingSteps;
```

| Item | Behaviour |
|---|---|
| `OpticalTransmitterState` | Shared state for the full-screen Light overlay and the receiver's confidence. `setTransmitting(false)` also clears the CSK and fountain state. `setConfidence` ignores changes smaller than 0.001. `clearCsk`, `clearFountain` and `clearQr` do **not** notify. Every other setter notifies. `transmitting` doubles as the stop signal for `FountainQrModem` and `CskOpticalModem`. |
| `opticalTransmitterState` | The global instance. |
| `onOpticalTransmitCancel` | Set by `AppController` to `requestCancelTransfer`; the overlay's Stop button calls it. |
| `isHardwarePlatform` | Not web, and Android or iOS. |
| `isPhysicalChannelSupported` | `isHardwarePlatform || kIsWeb`. Light and Sound. |
| `isVibrationSupported` | `isHardwarePlatform`. |
| `excludedNetworkTransports` | `['Internet / IP', 'Wi-Fi', 'Bluetooth', 'NFC', 'Cellular / SMS', 'Cloud / servers']`. |
| `platformCapabilityLabel` | `'Phone: optical + acoustic + vibration'`, `'Laptop (Web): optical + acoustic'` or `'Limited: simulation only'`. |
| `platformCapabilitySummary`, `hardwarePairingSteps`, `physicalOnlyPolicySummary` | User-facing strings for banners. |

**Used by:** the modems and channels (state and platform checks), `AppController`, and UI overlays and screens (`optical_active_overlay.dart`, `optical_fountain_qr_overlay.dart`, `optical_csk_overlay.dart`, `receive_screen.dart`, `send_transmit_screen.dart`, `hardware_screen.dart`, `app_layout.dart`). `test/physical_only_test.dart` checks the policy.

### 14.2 `lib/core/platform/acoustic_receiver_state.dart`

Live Sound receive feedback.

```dart
enum AcousticRxPhase { idle, permissionDenied, starting, listening, tonesDetected, decoding, decoded }

class AcousticReceiverState extends ChangeNotifier {
  AcousticRxPhase get phase;
  double get inputLevel;
  double get toneStrength;
  double get highBandLevel;      // 0..1, energy above 16 kHz (Silent band meter)
  int get packetsDecoded;
  int get collected;
  int get needed;
  int get framesRepaired;
  int get framesRejected;
  String get profileLabel;
  bool get transferActive;
  double get transferFraction;
  bool get micLive;              // listening, tonesDetected, decoding or decoded

  void setPhase(AcousticRxPhase value);
  void setLevels({required double input, required double tone, double highBand = 0});
  void setFountainProgress({required int collected, required int needed,
      required int framesRepaired, required int framesRejected, String profileLabel = ''});
  void markDecoded();
  void reset({bool keepDecodeCount = true});
}

final acousticReceiverState = AcousticReceiverState();
```

`setLevels` only notifies when a level moves by more than 0.02; `reset` also clears `highBandLevel`. `setFountainProgress` only notifies on a real change, and switches the phase to `decoding` while a transfer is active and the microphone is live. `markDecoded` increments `packetsDecoded`, sets phase `decoded` and clears progress.

**Used by:** `HardwareAcousticChannel` (writer), `receive_screen.dart` and `acoustic_transfer_hud.dart` (readers).

### 14.3 `lib/core/platform/acoustic_transmitter_state.dart`

Live Sound transmit feedback.

```dart
class AcousticTransmitterState extends ChangeNotifier {
  bool get playing;
  int get totalBytes;
  int get symbolsSent;
  int get symbolsPlanned;
  String get profileLabel;
  double get estimateSeconds;
  double get fraction;           // symbolsSent / symbolsPlanned, clamped
  bool get silent;               // the current send uses a Silent profile
  void beginAcoustic({required int totalBytes, required String profileLabel,
      required double estimateSeconds, bool silent = false});
  void setAcousticProgress(int sent, int planned);
  void endAcoustic();
  void reset();
}

final acousticTransmitterState = AcousticTransmitterState();
```

**Used by:** `HardwareAcousticChannel._transmitFountain` (writer), `send_transmit_screen.dart` and `acoustic_transfer_hud.dart` (readers).

### 14.3a `lib/core/platform/acoustic_spectrum_state.dart`

Live frequencies for the Sound readout: the tones on air (sender) and the microphone spectrum (receiver). It is separate from the transmitter and receiver states because it changes at audio rate, and only `LiveToneMeter` listens to it.

```dart
class AcousticSpectrumState extends ChangeNotifier {
  ToneTimeline? get txTones;                          // burst now playing, or null
  SpectrumSnapshot get rx;
  ({ToneKind kind, List<double> hz})? txNow();        // segment at the playback clock
  void startTxBurst(ToneTimeline tones);              // starts the clock now
  void endTx();
  void setRx(SpectrumSnapshot snapshot);
  void resetRx();
}

final acousticSpectrumState = AcousticSpectrumState();
```

`txNow()` looks up `txTones.atTime(now − start)`, so it returns `null` once the burst's audio has run out and before the next burst starts. It notifies only on burst start and end. The widget polls `txNow()` on its own 50 ms timer while `txTones` is non-null. `setRx` notifies on every call, which is at most once per 80 ms because of the channel's throttle. `endTx` and `resetRx` do nothing if already clear.

**Used by:** `HardwareAcousticChannel` (writer), `LiveToneMeter` (reader).

### 14.4 `lib/core/platform/vibration_transmitter_state.dart`

```dart
class VibrationTransmitterState extends ChangeNotifier {
  bool get vibrating;
  bool get transmitting;
  double get lastMagnitude;      // receiver "signal" 0..1
  void setVibrating(bool value);
  void setTransmitting(bool value);
  void setLastMagnitude(double value);   // always notifies
}

final vibrationTransmitterState = VibrationTransmitterState();
```

**Used by:** `HardwareVibrationChannel` (writer), `AppController` (cancel), `send_transmit_screen.dart`, `receive_screen.dart`, `hardware_screen.dart`.

### 14.5 `lib/core/platform/optical_display_control.dart`

Forces full screen brightness during a Light stream (Android only; no-op elsewhere).

```dart
class OpticalDisplayControl {
  static Future<void> setMaxBrightness();
  static Future<void> restoreBrightness();
}
```

Both call `MethodChannel('apcs/optical_display')` with the method names `'setMaxBrightness'` and `'restoreBrightness'`, handled in the Android `MainActivity.kt`. Errors are swallowed.

**Used by:** `FountainQrModem.transmit`.

---

## 15. protocol module

Folder: `lib/core/protocol/`. The 24-byte packet header, CRC-32 and the packet codec used by the protocol path and the simulator. Byte dumps are in [Data Formats](../architecture/DATA_FORMATS.md).

### 15.1 `lib/core/protocol/packet_codec.dart`

| Constant | Value |
|---|---|
| `headerSize` | `24` |
| `crcSize` | `4` |

```dart
class PacketHeader {
  const PacketHeader({
    required int protocolVersion,
    required int sessionId,
    required int transferId,
    required PacketType packetType,
    required CommChannelId channelId,
    required int sequenceNumber,
    required int payloadLength,
    int totalPackets = 0,
  });
}

class DecodedPacket extends PacketHeader {
  DecodedPacket({ /* all PacketHeader fields */ required Uint8List payload, required int crc, required Uint8List raw });
  final Uint8List payload;
  final int crc;
  final Uint8List raw;
}

int createSessionId();
int createTransferId();
int computeCrc32(Uint8List data);
bool verifyCrc32(Uint8List data, int expectedCrc);

class PacketCodec {
  Uint8List encode(PacketHeader header, [Uint8List? payload]);
  DecodedPacket? decode(Uint8List raw);
}

final packetCodec = PacketCodec();
```

Little-endian layout: version u8 (offset 0), sessionId u32 (1), transferId u32 (5), packetType u8 (9), channelId u8 (10), sequenceNumber u32 (11), payloadLength u16 (15), totalPackets u16 (17), 5 reserved zero bytes (19–23), payload (24), CRC-32 u32 over bytes 0 … 23+N.

| Function | Behaviour |
|---|---|
| `createSessionId` / `createTransferId` | `Random().nextInt(0xFFFFFFFF)` (not cryptographic). |
| `computeCrc32(data)` | IEEE CRC-32: reflected polynomial `0xEDB88320`, init `0xFFFFFFFF`, final XOR `0xFFFFFFFF`, table-driven. Also used by APCF frames, envelope de-duplication and fountain session ids. |
| `encode(header, payload)` | Writes the header, payload and CRC. `totalPackets` is clamped to 0…65535. The **header's `payloadLength` is written as given**; callers must set it to the payload length or the packet will not decode. |
| `decode(raw)` | Returns `null` if shorter than 28 bytes, the version is not `protocolVersion` (1), the buffer is shorter than the stated payload, or the CRC fails. Trailing bytes are ignored. Payload and raw are copied. After a CRC pass, an unknown packet-type or channel byte makes `PacketType.fromValue` / `CommChannelId.fromValue` throw `StateError`. |

**Used by:** `ReliableTransport`, `TransferManager`, `AppController` (ACK and discovery replies), the hardware channels, `FskStreamDecoder`, `SimulatedMedium`, `QrFountainFrameCodec` and the modems (CRC only).

```dart
import 'dart:typed_data';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

final payload = Uint8List.fromList(List.generate(10, (i) => i));
final raw = packetCodec.encode(
  PacketHeader(
    protocolVersion: protocolVersion,
    sessionId: createSessionId(),
    transferId: createTransferId(),
    packetType: PacketType.data,
    channelId: CommChannelId.vibration,
    sequenceNumber: 1,
    payloadLength: payload.length,
    totalPackets: 1,
  ),
  payload,
);
assert(raw.length == 24 + 10 + 4);

final back = packetCodec.decode(raw)!;
assert(back.packetType == PacketType.data && back.payload.length == 10);

raw[30] ^= 0xFF;                                  // flip a payload byte
assert(packetCodec.decode(raw) == null);          // rejected by CRC-32
```

---

## 16. simulation module

Folder: `lib/core/simulation/`. A packet-level channel model, virtual links, two virtual endpoints, nine scenarios and the orchestrator that runs them. See the [Simulation Lab](./SIMULATION_LAB.md) notes and [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md).

### 16.1 `lib/core/simulation/simulated_medium.dart`

```dart
class ChannelSimulationProfile {
  const ChannelSimulationProfile({
    double baseThroughput = 18000,
    double packetLossRate = 0.01,
    double baseLatencyMs = 80,
    double confidence = 0.92,
    double stability = 0.88,
    double corruptionRate = 0.005,
    bool discoverable = true,
  });
  ChannelSimulationProfile merge(ChannelSimulationProfile other);
  ChannelSimulationProfile copyWith({...});
}

class DegradationSchedule {
  const DegradationSchedule({required int afterPacket, required ChannelSimulationProfile profile});
}

class SimulatedChannelConfig {
  const SimulatedChannelConfig({
    required ChannelSimulationProfile profile,
    DegradationSchedule? degradation,
    DegradationSchedule? recovery,
  });
}

const defaultOpticalProfile;
const defaultAcousticProfile;
const defaultVibrationProfile;

ChannelMetrics profileToMetrics(ChannelSimulationProfile profile);
ChannelTestResult profileToTestResult(CommChannelId channelId, ChannelSimulationProfile profile,
    int packetsSent, int packetsReceived);

typedef PacketDeliveryHandler = void Function(Uint8List raw);

class SimulatedMedium {
  SimulatedMedium(String peerId, SimulatedChannelConfig config);
  final String peerId;
  SimulatedChannelConfig config;
  ChannelSimulationProfile get activeProfile;
  void setOutboundHandler(PacketDeliveryHandler handler);
  Future<void> send(Uint8List raw);
  void receiveFromPeer(Uint8List raw);
  List<Uint8List> pollReceived();
  Future<bool> runDiscoveryTest(int timeoutMs);
  Future<({int sent, int received})> runChannelTest(int testPacketCount);
  ChannelMetrics getMetrics();
  ChannelTestResult getTestResult(CommChannelId channelId);
  List<DecodedPacket> decodeRawPackets(List<Uint8List> rawPackets);
}

class VirtualLink {
  VirtualLink(SimulatedMedium mediaA, SimulatedMedium mediaB);
}
```

Default profiles (fields not listed take the `ChannelSimulationProfile` defaults above):

| Constant | Throughput | Loss | Latency | Confidence | Stability | Corruption |
|---|---|---|---|---|---|---|
| `defaultOpticalProfile` | 18000 | 0.01 | **2** | 0.92 | 0.88 | 0.005 |
| `defaultAcousticProfile` | 9000 | 0.04 | 3 | 0.78 | 0.72 | 0.01 |
| `defaultVibrationProfile` | 800 | 0.06 | 120 | 0.72 | 0.68 | 0.015 |

| Member | Behaviour |
|---|---|
| `merge(other)` | Returns `other`'s values for **every** field (it is a full replacement, not a partial overlay). |
| `profileToMetrics` | Reliability `max(0, 1 − loss − corruption)`; other metrics copied. |
| `profileToTestResult` | Loss from the counts (the profile's loss if nothing was sent), throughput `base × (1 − loss)`, confidence `confidence × (1 − loss/2)`. |
| `send(raw)` | Throws `StateError('SimulatedMedium $peerId: no outbound handler')` if not linked. Counts the packet, applies the degradation schedule and then the recovery schedule once their `afterPacket` counts are reached, drops the packet with probability `packetLossRate`, corrupts one byte after the header (XOR `0xFF`) with probability `corruptionRate`, then waits `max(1, round(latency ± 15 + len·8 / throughput · 1000))` ms and hands it to the peer. |
| `pollReceived()` | Returns and removes delivered raw packets. |
| `runDiscoveryTest(t)` | `false` if undiscoverable; otherwise waits `min(t, 50…150)` ms and returns true with probability `1 − 2·loss`. |
| `runChannelTest(n)` | Counts packets that survive the loss probability, waiting `round(latency / n)` ms per packet. |
| `decodeRawPackets` | `packetCodec.decode` on each, dropping failures. |
| `VirtualLink` | Wires A's outbound to B's inbound and vice versa. |

**Used by:** `SimulatedCommChannel`, `createSimulationPair`, scenarios, `PerformanceComparator`.

### 16.2 `lib/core/simulation/simulation_orchestrator.dart`

Two virtual endpoints and the loop that runs one full simulated transfer between them.

```dart
class VirtualEndpoint {
  VirtualEndpoint({
    required String id,
    required EndpointRole role,
    required StructuredLogger logger,
    required ChannelManager channelManager,
  });
  final TransferStateMachine stateMachine;
  final AdaptiveDecisionEngine decisionEngine;
  int sessionId;
  int transferId;
  ReliableTransport? transport;
  ChannelDecision? currentDecision;
  final Map<CommChannelId, double> channelScores;
  final List<SwitchEvent> switchEvents;
  Uint8List? receivedData;
  List<Uint8List> allPackets;
  Uint8List? dataToSend;
  DashboardSnapshot getSnapshot();
}

class SimulationPair {
  SimulationPair({required VirtualEndpoint endpointA, required VirtualEndpoint endpointB});
}

SimulationPair createSimulationPair({
  ChannelSimulationProfile? opticalProfileA,
  ChannelSimulationProfile? opticalProfileB,
  ChannelSimulationProfile? acousticProfileA,
  ChannelSimulationProfile? acousticProfileB,
  ChannelSimulationProfile? vibrationProfileA,
  ChannelSimulationProfile? vibrationProfileB,
  DegradationSchedule? opticalDegradation,
  DegradationSchedule? acousticDegradation,
  DegradationSchedule? vibrationDegradation,
  DegradationSchedule? opticalRecovery,
  DegradationSchedule? acousticRecovery,
  DegradationSchedule? vibrationRecovery,
});

class SimulationResult {
  final bool success;
  final bool dataMatch;
  final int originalSize;
  final int receivedSize;
  final int switchEvents;
  final DashboardSnapshot senderSnapshot;
  final DashboardSnapshot receiverSnapshot;
  final int durationMs;
  final List<String> logs;
}

class SimulationOrchestrator {
  SimulationOrchestrator(SimulationPair pair);
  final SimulationPair pair;
  void Function(DashboardSnapshot sender, DashboardSnapshot receiver)? onUpdate;
  Future<SimulationResult> runTransfer(Uint8List data);
}

Uint8List generateTestData(int size);      // byte i = i % 256
```

`createSimulationPair` builds each channel's profile as `default*Profile.copyWith(...)` from the override's fields. Because a `const ChannelSimulationProfile(...)` literal always has every field set, an override replaces all fields, not only the ones written. Degradation and recovery schedules are attached to **endpoint A only**. Endpoint A is the sender and B the receiver; each has its own logger and `ChannelManager` with three `SimulatedCommChannel`s joined by `VirtualLink`s.

`runTransfer(data)`:

1. Initialise and start both managers; copy the random session and transfer ids to the receiver.
2. `discoverAll(300)` on both. If either side finds nothing, return a failed result.
3. The sender runs `testAll(20)` (all channels, discoverable or not) and `selectBestChannel`. Both endpoints set that channel active.
4. Both get a `ReliableTransport` with default configs. The sender fragments; the receiver is told the packet count.
5. Loop at most **1500** times with a **5 ms** sleep: send window, receive on both sides, answer, handle switch negotiation, check timeouts, receive again. Stop when the receiver is complete. Every 20 iterations the sender re-scores the active channel and, if degraded, tests the others and may switch.
6. Success means the received bytes equal the input. Stop both managers and return the result, including all log lines as `'[CATEGORY] message'`.

Switching (`_performSwitch`) sets **both** endpoints to the new channel directly, calls `resumeFromSequence` on both, sends a `channelSwitchRequest`, waits 30 ms and processes one round of switch negotiation. The switch therefore does not depend on the ACK arriving.

**Used by:** `AppController.runSimulation` and `runAllScenarios`, `PerformanceComparator`, `createChannelManagerForMode` (simulation and hybrid modes), `test/simulation_integration_test.dart`.

### 16.3 `lib/core/simulation/scenarios.dart`

```dart
class ScenarioDefinition {
  const ScenarioDefinition({
    required String id,
    required String name,
    required String description,
    required int dataSize,
    required SimulationPair Function() createPair,
  });
}

final scenarios = <ScenarioDefinition>[ /* nine entries */ ];
ScenarioDefinition? getScenario(String id);
```

| `id` | `dataSize` | Setup (endpoint A unless stated) |
|---|---|---|
| `optical-always-good` | 4096 | Optical 0.5 % loss, 20 000 throughput (both sides); acoustic 5 % loss with otherwise default-profile fields (both sides). |
| `acoustic-always-good` | 4096 | Optical undiscoverable (both); acoustic 2 % loss, 10 000 throughput (both). |
| `optical-degrades` | 8192 | Acoustic 3 % loss, 9 000 throughput (A confidence 0.8). Optical degrades after 15 packets to 2 000 throughput, 30 % loss, 500 ms, confidence 0.3, stability 0.2. |
| `random-loss` | 4096 | Optical 8 % loss (A also 2 % corruption); acoustic 6 % loss. |
| `burst-loss` | 6144 | Optical degrades after 8 packets to 45 % loss, 4 000 throughput, 300 ms. |
| `both-degrade` | 2048 | After 10 packets optical becomes 25 % loss / 3 000, acoustic 20 % loss / 4 000. |
| `acoustic-recovers` | 4096 | Optical undiscoverable; acoustic 15 % loss / 3 000 (A confidence 0.4), recovering after 30 packets to 2 % / 10 000 / confidence 0.85. |
| `repeated-degradation` | 10240 | Acoustic 5 % / 8 000. Optical degrades after 12 packets (35 % / 2 500 / confidence 0.25) and recovers after 35 (1 % / 18 000 / confidence 0.9). |
| `vibration-coupled` | 2048 | Optical and acoustic undiscoverable; vibration 3 % loss / 900 (A confidence 0.82). |

`getScenario(id)` returns `null` for an unknown id. `AppController` defaults to `'optical-degrades'`.

**Used by:** `AppController` (`availableScenarios`, `runSimulation`, `runAllScenarios`), `PerformanceComparator`.

---

## 17. transport module

Folder: `lib/core/transport/`. Fragmentation, sliding-window reliability and the channel-switch packets. See [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md).

### 17.1 `lib/core/transport/reliable_transport.dart`

```dart
class TransportConfig {
  const TransportConfig({int ackTimeoutMs = 500, int maxRetries = 5, int windowSize = 8});
}
const defaultTransportConfig = TransportConfig();

class ReliableTransport {
  ReliableTransport({
    required int sessionId,
    required int transferId,
    required CommChannelId channelId,
    required ChannelManager channelManager,
    required StructuredLogger logger,
    TransmissionConfig transmissionConfig = defaultTransmissionConfig,
    TransportConfig config = defaultTransportConfig,
    bool broadcastMode = false,
  });

  CommChannelId get channelId;
  void setChannelId(CommChannelId id);
  int get lastAckedSequence;
  int get lastSentSequence;
  int get retryCount;
  int get duplicateCount;
  bool get allPacketsTransmitted;
  bool get hasPendingRetriesExhausted;

  TransferProgress getProgress(int totalPackets, int totalBytes);
  List<Uint8List> createDataPackets(Uint8List data);
  Future<void> sendNextWindow(List<Uint8List> allPackets);
  Future<List<Uint8List>> handleReceivedPackets(List<DecodedPacket> packets);
  List<Uint8List> checkTimeouts();
  List<int> findMissingSequences();
  bool isTransferComplete();
  Uint8List? reassembleData();
  void setExpectedTotalPackets(int count);
  void resumeFromSequence(int lastConfirmed);
  Uint8List createSwitchRequest(CommChannelId newChannelId, int lastConfirmed);
  Uint8List createSwitchAck(CommChannelId newChannelId, int lastConfirmed);
  ({CommChannelId newChannelId, int lastConfirmed})? parseSwitchRequest(DecodedPacket packet);
  ({CommChannelId newChannelId, int lastConfirmed})? parseSwitchAck(DecodedPacket packet);
}
```

| Member | Behaviour |
|---|---|
| `createDataPackets(data)` | Splits into `transmissionConfig.packetSize` chunks (one empty chunk for empty data) and encodes `data` packets with sequence numbers 1…N and `totalPackets = N`. Sets the expected total. |
| `sendNextWindow(all)` | **Broadcast:** sends the next `windowSize` unsent packets and advances `lastSentSequence`. **Unicast:** (re)sends packets `lastAcked+1 … lastAcked+windowSize`, tracking each as pending. |
| `handleReceivedPackets(pkts)` | Ignores packets for other transfer ids. `data`: duplicates are counted and re-ACKed; new packets are stored and ACKed, then a NACK is produced for every gap below the highest received sequence. `ack`: treated as **cumulative**, raising `lastAckedSequence` and dropping pending packets up to it. `nack`: retransmits that sequence. `retransmissionRequest`: retransmits each u32 (little-endian) sequence in the payload. Returns the packets the caller must transmit. |
| `checkTimeouts()` | Retransmits pending packets older than `ackTimeoutMs` that have retries left; logs packets that have run out. |
| Retransmission | Each retransmission increments that packet's retry count and `retryCount`; packets at `maxRetries` are skipped with an error log. |
| `allPacketsTransmitted` | Broadcast only: every packet sent once. |
| `hasPendingRetriesExhausted` | Every pending packet has reached `maxRetries`. |
| `isTransferComplete()` / `reassembleData()` | Complete when 1…expected are all present; reassembly concatenates in order (`null` if incomplete). |
| `resumeFromSequence(n)` | Sets `lastAcked = n` and drops pending packets up to `n`. |
| Switch packets | Payload: new channel value u32 LE, then last confirmed u32 LE; `sequenceNumber = lastConfirmed`. The request is sent on the current channel id; the ACK carries the new channel id. The parse methods return `null` for other packet types. |
| `getProgress` | `bytesTransferred` is approximated as received packets × packet size. |

**Used by:** `TransferManager`, `SimulationOrchestrator`, `VirtualEndpoint`.

---

## 18. types module

Folder: `lib/core/types/`. Shared enums, value classes and thresholds with no dependencies.

### 18.1 `lib/core/types/types.dart`

```dart
const int protocolVersion = 1;

enum PacketType {
  discovery(0), discoveryResponse(1), channelTest(2), channelTestResponse(3),
  negotiation(4), data(5), ack(6), nack(7), retransmissionRequest(8),
  channelSwitchRequest(9), channelSwitchAck(10), heartbeat(11),
  transferStatus(12), transferComplete(13), error(14);
  final int value;
  static PacketType fromValue(int v);
}

enum CommChannelId {
  optical(1), acoustic(2), vibration(3);
  final int value;
  static CommChannelId fromValue(int v);
}

enum TransferState { idle, discovering, testingChannels, negotiating, transferring,
                     degraded, switchingChannel, recovering, completed, failed }
enum EndpointRole { sender, receiver }
enum TransferMode { unicast, broadcast }

class ChannelMetrics { throughput, packetLoss, latency, reliability, errorRate,
                       confidence, stability (double); timestamp (int);
                       ChannelMetrics copyWith({int? timestamp}); }
class ChannelTestResult { channel, packetsSent, packetsReceived, packetLossRate,
                          throughput, latency, confidence, stability }
class TransmissionConfig { const TransmissionConfig({int packetSize = 256, double dataRate = 18000,
                           int redundancy = 0, int retryLimit = 5, String modulation = 'default'}); }
class ChannelCapabilities { channelId, name, maxThroughput, minLatency, supportsBinary, hardwareImplemented }
class ChannelDecision { selectedChannel, score, confidence, reason }
class ScoringWeights { const ScoringWeights({double throughput = 0.35, double reliability = 0.25,
                       double latency = 0.15, double confidence = 0.15, double stability = 0.10}); }
class TransferProgress { transferId (String), totalPackets, sentPackets, acknowledgedPackets,
                         receivedPackets, lastConfirmedSequence, retryCount, bytesTransferred,
                         totalBytes, progressPercent }
class SwitchEvent { fromChannel, toChannel, lastConfirmedPacket, timestamp, reason }
class LogEntry { category, message, timestamp, data }
class DashboardSnapshot { state, role, currentChannel, channelScore, channelConfidence, metrics,
                          progress, channelScores (Map<String, double>), switchEvents, logs,
                          availableChannels }

const defaultTransmissionConfig = TransmissionConfig();
const defaultScoringWeights = ScoringWeights();
const switchHysteresisThreshold = 0.15;
const degradationThreshold = 0.65;

String channelIdToName(CommChannelId id);        // 'OPTICAL' | 'ACOUSTIC' | 'VIBRATION'
String transferStateLabel(TransferState s);      // e.g. 'TESTING_CHANNELS'
```

All classes are immutable with `const` constructors and required named parameters (except where defaults are shown). Notes:

- `PacketType.fromValue` and `CommChannelId.fromValue` use `firstWhere` without a fallback, so an unknown value throws `StateError`.
- `ChannelMetrics` units: throughput in bits per second as used by the simulator and the normaliser (25 000 is "full marks"), latency in milliseconds, the other fields in 0..1.
- `TransmissionConfig.dataRate`, `redundancy`, `retryLimit` and `modulation` are not read by current code; only `packetSize` is used.
- `DashboardSnapshot.channelScores` is keyed by `channelIdToName`.

**Used by:** almost every module. `transferStateLabel` is used by `endpoint_panel.dart`.

---

## 19. application module (AppController)

Folder: `lib/application/`.

### 19.1 `lib/application/app_controller.dart`

The single hub between the UI and the core. It owns the hardware channels, the chat list, the send and receive flows, the 80 ms receive poll, the simulation runs and the performance comparison. It is a `ChangeNotifier` provided to the widget tree by `AppProvider` (section 20). The file re-exports `core/channels/hardware_channels.dart`.

```dart
class AppController extends ChangeNotifier {
  AppController();                        // sets onOpticalTransmitCancel = requestCancelTransfer
  final StructuredLogger logger;
}
```

Initial state: `mode` = `OperationMode.simulation`, `role` = `EndpointRole.sender`, `transferMode` = `TransferMode.broadcast`, `scenarioId` = `'optical-degrades'`, `statusMessage` = `'Ready'`, `opticalTxProfile` = `OpticalTxProfile.auto`, `acousticTxProfile` = `AcousticTxProfile.standard`.

**State getters:**

| Getter | Meaning |
|---|---|
| `mode`, `role`, `transferMode`, `scenarioId`, `running`, `statusMessage` | Current settings and the one-line status shown by screens. |
| `chatMessages` (unmodifiable), `latestIncomingMessage`, `incomingMessageCount`, `lastIncomingAt`, `lastReceivedData` | The chat store. |
| `senderSnapshot`, `receiverSnapshot`, `lastSimResult`, `comparisonResults`, `liveLogs`, `availableScenarios` | Simulation and dev-tool state. |
| `opticalChannel`, `acousticChannel`, `vibrationChannel`, `hardwareChannelsActive`, `hardwareAvailable` (`isPhysicalChannelSupported`), `cameraActive`, `selectedPhysicalChannel`, `cancelRequested`, `lastTransferSucceeded` | Hardware state. |
| `incomingBufferedPacketCount`, `incomingExpectedPacketCount` | Protocol-path receive progress. |
| `opticalQrChunkProgress`, `opticalTransferMetrics`, `opticalMetricsNotifier` | Light receive progress and the HUD notifier. |
| `acousticMicActive` | True while the microphone stream runs. |

**Send and receive (the Send/Receive screens):**

```dart
Future<void> configurePhysicalFlow({required EndpointRole role, required CommChannelId channel});
Future<bool> sendPhysicalMessage({required ComposePayload payload, required CommChannelId channel});
Future<void> startListening(CommChannelId channel);
Future<void> stopListening();
void prepareForNextMessage();
void requestCancelTransfer();
void resetCancelFlag();
void cancelAcousticTransmit();
Future<void> retryAcousticListening();

OpticalTxProfile get opticalTxProfile;
void setOpticalTxProfile(OpticalTxProfile profile);
AcousticTxProfile get acousticTxProfile;
void setAcousticTxProfile(AcousticTxProfile profile);
int acousticEtaSeconds(int bytes);
```

| Method | Behaviour |
|---|---|
| `configurePhysicalFlow` | Switches to hardware mode, sets role and selected channel. The transfer mode becomes unicast for vibration and broadcast otherwise. For receivers it starts the hardware channels (which starts the 80 ms poll). |
| `sendPhysicalMessage` | Returns `false` if already running or the payload is empty. Adds an outgoing `sending` message, builds the envelope (`_prepareEnvelope`: images go through `compressImageForTransfer` and are re-encoded as `image/jpeg`, default name `photo.jpg`; other types use `ComposePayload.toEnvelope`). Light envelopes above `FountainQrModem.maxEnvelopeBytes` fail. **Light**, and **Sound** up to `acousticChannel.maxEnvelopeBytes` (8192 in fountain mode), use the direct path; the message becomes `sent` (neither has a return path), or `failed`. Everything else (Vibration, larger Sound) uses `runHardwareTransfer` and becomes `delivered` or `failed`. Exceptions mark the message `failed` and return `false`. |
| Direct path | Starts channels for the sender role, then awaits `transmitEnvelope` on the optical or acoustic channel (this returns only when streaming stops). For Light the status is a summary from `lastTxEnd`, `lastTxFrames` and `lastTxDuration`, offering "Resume" after a stop or the 10-minute cap. Afterwards channels are restarted for the current role and that status is kept. |
| `startListening(ch)` / `stopListening()` | Configure the receiver flow; stop all hardware channels and clear the selection. |
| `prepareForNextMessage()` | "Clear & keep listening": clears protocol reassembly state and the idle timer, trims the delivered-transfer id set (above 32 it keeps 16), clears all physical receive caches **with** dedup reset (dropping Light partial sessions), restarts the camera stream if needed. |
| `requestCancelTransfer()` | Sets `cancelRequested`, clears the Light and Vibration transmitting flags and calls `cancelAcousticTransmit()`, which ends a Light or Sound stream and stops `TransferManager` loops. |
| `cancelAcousticTransmit()` | Stops a Sound stream immediately, cutting off the burst that is playing. |
| `retryAcousticListening()` | Only for the Sound channel: re-initialises (re-requesting the microphone) and restarts the receiver. |
| `setOpticalTxProfile` / `setAcousticTxProfile` | Store the profile and push it to the channel if it exists. |
| `acousticEtaSeconds(bytes)` | `ceil(expectedSymbols(max(1, ceil(bytes / blockLen))) × frameSeconds())` for the current Sound profile. |

**Hardware lifecycle:**

```dart
Future<void> initHardware();
Future<void> startHardwareChannels({EndpointRole? forRole});
Future<void> stopHardwareChannels();
Future<void> restartHardwareChannels();
```

- Channels are created lazily. Initialisation always covers optical (camera only for receivers), acoustic, and vibration on phones. `startHardwareChannels` sets an error status and returns on unsupported platforms.
- With a selected channel, the other two are **stopped** so they do not hold the camera, microphone or accelerometer, and only the selected one is started (receiver enabled for the receiver role). Without a selection, all are started.
- For the receiver role it starts the 80 ms poll timer; for the sender role it stops it.

**Receive pipeline (private, runs every 80 ms while receiving):**

1. `_pollHardwareReceiver` returns early if not receiving or if a transfer is running. It collects protocol packets from the selected channel (all channels if none is selected) and filters them by channel id.
2. `discovery` packets are answered in unicast mode. `data` packets are ACKed in unicast mode (never in broadcast, so receivers stay silent), ignored if their transfer was already delivered, and buffered by sequence. `transferComplete` packets set the expected total and force a delivery check. Replies to optical packets go out on acoustic when available.
3. Each data packet re-arms a **1800 ms** idle timer. Delivery requires every packet 1…total (or, with an unknown total, a contiguous run and either a single packet or the idle timeout), and an envelope that passes `ChatPayloadCodec.looksComplete`.
4. `_pollDirectEnvelopes` drains `receiveEnvelopes()` from the optical and acoustic channels.
5. `_addIncomingChat(raw)` decodes with `ChatPayloadCodec.decodeIncoming`, appends the message, sets a status, and auto-saves photos and videos with `GallerySaver`. An APCM envelope that fails validation sets an "Incomplete image/message" status instead.

**Simulation and developer tools:**

```dart
void setMode(OperationMode m);
void setTransferMode(TransferMode mode);
void setRole(EndpointRole r);
void setScenario(String id);
void clearLogs();
void clearChat();
Future<void> sendChat({required ChatMessageType type, required Uint8List payload,
                       String? text, String? fileName, String? mimeType});
Future<void> sendChatText(String text);
Future<void> sendHardwareHello();            // sendHardwareMessage('HELLO')
Future<void> sendHardwareMessage(String text);
Future<void> testOpticalFlash();             // transmits 'FLASH' on the optical channel
Future<void> testVibration();                // transmits 'VIB' on the vibration channel
Future<void> runSimulation({Uint8List? data});
Future<void> runHardwareTransfer(Uint8List data, {CommChannelId? forcedChannel});
Future<void> runPerformanceComparison();
Future<void> runAllScenarios();
```

| Method | Behaviour |
|---|---|
| `setMode` / `setRole` | Update the status text; in hardware mode (and not running) they start the hardware channels. |
| `sendChat` | Legacy Messages screen. Simulation mode runs the current scenario with the envelope and, on success, appends a simulated received copy. Hardware mode uses `runHardwareTransfer`. |
| `runSimulation` | Runs the current scenario (or `data`) through `SimulationOrchestrator`, streaming snapshots and logs into the controller. |
| `runHardwareTransfer` | Starts channels, builds a `ChannelManager` with `createChannelManagerForMode(hardware)`, and runs a `TransferManager` with `forcedChannel` (defaulting to the selected channel), `enableAdaptiveSwitching: false`, `peerDiscoveryTimeoutMs: 20000`, `peerInactivityTimeoutMs: 45000`, unicast for vibration, and `isCancelled` wired to `cancelRequested`. A receiver adds the result to the chat. Channels are restored afterwards. |
| `runAllScenarios` | Runs all nine scenarios and sets the status to `'N/9 scenarios passed'`. |
| `testOpticalFlash` / `testVibration` | Send a tiny raw payload through `CommChannel.transmit` (for Light this is a full fountain stream of those bytes, which stops when cancelled). |

`dispose()` stops the poll and idle timers and disposes all three channels.

**Used by:** every screen through `AppProvider.of(context)`.

---

## 20. App shell (main.dart)

### 20.1 `lib/main.dart`

The app entry point, theme, controller provider and the global Light overlay.

```dart
void main();

class AdaptiveCommApp extends StatelessWidget {
  const AdaptiveCommApp({super.key});
}

class AppProvider extends StatefulWidget {
  const AppProvider({super.key, required AppController Function() create, required Widget child});
  static AppController of(BuildContext context);
}
```

| Item | Behaviour |
|---|---|
| `main()` | `runApp(const AdaptiveCommApp())`. |
| `AdaptiveCommApp` | Wraps a `MaterialApp` in `AppProvider(create: () => AppController())`. Title `'Adaptive Physical Communication'`, no debug banner, Material 3 dark scheme from seed `0xFF3B82F6`, font `Roboto`, 12 px rounded filled buttons and inputs, 16 px rounded flat cards, home `HomeScreen`. The `builder` stacks `OpticalActiveOverlay` above every route, so the full-screen QR appears wherever the user is. |
| `AppProvider` | Creates the controller once in `initState`, disposes it in `dispose`, and rebuilds an inherited widget through `ListenableBuilder` on every controller notification. |
| `AppProvider.of(context)` | Returns the controller and registers a dependency, so the caller rebuilds on every `notifyListeners()`. It asserts `'AppProvider not found'` in debug builds. |
| `_InheritedApp.updateShouldNotify` | Always `true`. |

---

## 21. Threading and isolates

Dart runs all of this code on the main UI isolate except the QR decoder. Work is kept responsive by short async steps, timers and dropping work that cannot keep up.

### 21.1 The QR decode isolate

- `QrDecodeWorker` spawns one long-lived isolate named `qr-decode` when `FountainQrModem.startReceiver()` runs (not on web). It lives until `FountainQrModem.dispose()`.
- The camera callback (`onCameraFrame`) runs on the main isolate. It returns immediately if a decode is in flight; otherwise it copies the Y plane (`extractQrGrayFrame`, one `setRange` per row) and sends it as `TransferableTypedData`, which moves the buffer without copying it again.
- Only **one** decode is in flight. Frames that arrive meanwhile are dropped and counted. With a fountain code, the next frame is exactly as useful, so dropping costs nothing.
- Every request has a **2 second** timeout, so a lost reply can never block the receiver.
- On web (or if spawning fails) decoding runs inline on the main isolate after `await Future.delayed(Duration.zero)`. `QrDecodeIsolatePool` also decodes on the main isolate despite its name.

### 21.2 Main-isolate audio and sensor work

- The microphone stream callback in `HardwareAcousticChannel` runs on the main isolate and does all Sound DSP there: PCM conversion, marker search and Goertzel demodulation for up to six `AcousticFrameSync`s while hunting (one after locking; the two Silent ones also run a high-pass filter), Reed-Solomon and LT decoding. Each sample region is probed once and then discarded, so the cost follows the audio rate.
- UI level updates from the microphone are throttled to one per **80 ms**. The live-readout FFT (1024 points) runs only inside that throttle; between updates each chunk is just copied into the analyzer's ring.
- The accelerometer callback in `HardwareVibrationChannel` also runs on the main isolate.
- Sound transmission renders each burst (2 to 4 frames) synchronously before playing it, then awaits the player's completion event.

### 21.3 Timers and loops

| Where | Period | Purpose |
|---|---|---|
| `AppController._hardwareListenTimer` | **80 ms** periodic | Polls packets and envelopes while in the receiver role. Skips a tick while `running`. |
| `AppController._incomingIdleTimer` | **1800 ms** one-shot | Final delivery check for protocol-path messages with no packet for 1.8 s. |
| `FountainQrModem._metricsTimer` | **500 ms** periodic | Refreshes the capture/decode rates and the "stalled" hint while receiving. |
| `FountainQrModem.transmit` loop | `max(40, round(1000 / txFps))` ms per frame; first frame +250 ms | Paces the QR stream (83 ms at 12 fps). |
| `HardwareOpticalChannel._webSampleTimer` | **33 ms** periodic | Web-only preview sampling. |
| `CskOpticalModem.onCameraFrame` | at most one sample per **45 ms** | CSK camera sampling. |
| `LiveToneMeter` (sending) | **50 ms** periodic, only while a burst is playing | Repaints **Sending now** from `acousticSpectrumState.txNow()`. |
| `TransferManager._transferLoop` | 50 ms (hardware) / 5 ms (simulation) per iteration | Protocol loop; switch evaluation every 20 iterations. |
| `TransferManager._discoverPeer` | 300 ms between rounds | Unicast discovery beacons. |
| `SimulationOrchestrator.runTransfer` | 5 ms per iteration | Simulation loop. |
| Channel `discover` / `test` helpers | 50 ms / 30 ms polls | Hardware heuristics. |

### 21.4 ChangeNotifiers and who listens

| Notifier | Written by | Read by |
|---|---|---|
| `AppController` | itself | every screen, through `AppProvider` (rebuilds on any change) |
| `opticalTransmitterState` | `FountainQrModem`, `CskOpticalModem`, `HardwareOpticalChannel`, `AppController` | Light overlays, send, receive and hardware screens |
| `OpticalMetricsNotifier` (per modem) | `FountainQrModem`, `CskOpticalModem` | Light receive HUD |
| `acousticReceiverState` | `HardwareAcousticChannel` | receive screen, Sound HUD |
| `acousticTransmitterState` | `HardwareAcousticChannel` | send screen, Sound HUD |
| `acousticSpectrumState` | `HardwareAcousticChannel` | `LiveToneMeter` on the send and receive screens |
| `vibrationTransmitterState` | `HardwareVibrationChannel`, `AppController` | send, receive and hardware screens |
| `GallerySaver.instance` | itself | received content card (Save / Retry button) |

The Light and Sound notifiers are written from camera and microphone callbacks, so their setters skip notifications when nothing visible changed. `AppController.notifyListeners()` rebuilds the whole tree below `AppProvider`, so avoid calling it from high-frequency paths; the channel notifiers exist for that reason.

### 21.5 Concurrency rules to keep

- `AppController` uses the `_running` flag to allow one send, simulation or protocol transfer at a time; the receive poll skips while it is set.
- Light and Sound `transmit` calls return only when the stream ends. Do not `await` them from code that must stay responsive; stop them with `requestCancelTransfer()` (either) or `cancelAcousticTransmit()` (Sound only).
- Before transmitting sound, the acoustic channel stops the microphone; after any direct send, `AppController` restarts the channels for the current role.

---

## 22. Extension points

Each recipe lists the exact files to touch. Enum `switch` statements in Dart are exhaustive, so after adding an enum value, `flutter analyze` will point to most places you missed. Add tests as described in [Testing](./TESTING.md).

### 22.1 Adding a new channel that implements `CommChannel`

1. **Give it an id.** Add a value to `CommChannelId` in `lib/core/types/types.dart` with the next wire value (4), and a name in `channelIdToName`.
2. **Implement the interface.** Create `lib/core/channels/<name>_channel.dart` with a class that implements all members of `CommChannel` (`lib/core/channels/comm_channel.dart`). Follow the existing contract: throw `StateError` from `transmit` when not started, never hold the sensor when `start(enableReceiver: false)`, and return-and-clear from `receive()`. Decode incoming bytes with `packetCodec.decode` (`lib/core/protocol/packet_codec.dart`).
3. **Packet size.** Add a `hardware<Name>PacketSize` constant and a case in `hardwareTransmissionConfigFor` in `lib/core/physical/hardware_phy_config.dart`.
4. **Register it.** Add a `case` in `ChannelManager.startAll` (`lib/core/manager/channel_manager.dart`) and register it in `createChannelManagerForMode` (`lib/core/manager/transfer_manager.dart`). Decide whether it belongs in the unicast discovery beacon order in `TransferManager._discoverPeer` and whether it is broadcast-capable (the broadcast branch of `runTransfer` excludes only vibration).
5. **Wire the controller.** In `lib/application/app_controller.dart`: add a field and getter, and cases in `_ensureChannelInitialized`, `_initHardwareForRole`, `startHardwareChannels` (`startOne` and the stop loop), `stopHardwareChannels`, `_ensureChannelReady`, `_transmitOnChannel`, `_sendDirectEnvelope`, `_pollHardwareReceiver`, `_resetPhysicalReceiveCaches` and `dispose`. Decide its transfer mode in `configurePhysicalFlow` and `runHardwareTransfer`.
6. **Optional rateless path.** If the medium is broadcast-only, give the channel `transmitEnvelope` and `receiveEnvelopes` methods like the optical and acoustic channels, route it in `sendPhysicalMessage`, and drain it in `_pollDirectEnvelopes`.
7. **Platform support.** Add an `is<Name>Supported` getter in `lib/core/platform/platform_capabilities.dart` if it is not available everywhere, and a UI-state notifier in `lib/core/platform/` if the screens need live feedback.
8. **Simulation.** Add `create<Name>Channel` to `comm_channel.dart`, a `default<Name>Profile` in `lib/core/simulation/simulated_medium.dart`, and profile, degradation and recovery parameters plus registration and a `VirtualLink` in `createSimulationPair` (`lib/core/simulation/simulation_orchestrator.dart`).
9. **Policy and UI.** `test/physical_only_test.dart` asserts that exactly three physical channels exist, so update it deliberately. The mode picker and screens are covered in the [UI Guide](./UI_GUIDE.md).

### 22.2 Adding a new optical profile (or optical modem)

**A new density profile:**

1. Add a `static const` to `OpticalTxProfile` in `lib/core/physical/optical_tx_profile.dart` with a unique `id`, `txFps` (keep at most 12, see the class comment), `blockLen`, `errorCorrectLevel: 'L'` and a `decodeTargetPx` (720 for sparse codes, 800 for dense ones).
2. Add it to `OpticalTxProfile.values`. The density chips in `send_transmit_screen.dart` iterate `values`, and `test/fountain_qr_roundtrip_test.dart` checks every profile for decode loss.
3. Check the QR version: the framed size is `blockLen + qrFountainOverhead` (26). The README's QR version table shows which version each size needs; larger versions decode far less reliably with a hand-held camera.
4. If the block size falls in a new range, review `expectedCaptureYield` (the ETA) and `slower`.
5. To change what **Auto** chooses, edit `autoBlockLadder` or `autoTargetSymbols`; `test/optical_density_sweep_test.dart` covers the thresholds.

**A new optical modem:**

1. Implement `OpticalModem` (`lib/core/physical/optical_modem.dart`). Copy camera data synchronously in `onCameraFrame`, publish metrics through an `OpticalMetricsNotifier`, and return completed envelopes from `takeEnvelopes()`.
2. Add a value to `OpticalModemKind` and construct and select it in `HardwareOpticalChannel` (`lib/core/channels/hardware_optical_channel.dart`: constructor, `selectModem`, `metricsNotifier`, `chunkProgress`, `dispose`).
3. If it has its own screen rendering, add state to `OpticalTransmitterState` and an overlay in `lib/ui/widgets/`.

### 22.3 Adding a new acoustic profile

1. Add a `static const` to `AcousticTxProfile` in `lib/core/physical/acoustic/acoustic_tx_profile.dart`. Constraints from the code:
   - `id` must be unique (`==` compares only `id`).
   - Pick its `band`. Each audible group adds 16 tones above bin 40, so 8 groups reach bin 167 (about 7.2 kHz). Silent profiles should keep `groups: 1`: two simultaneous near-ultrasonic tones produce an audible difference tone.
   - `guardFrames` must be below `framesPerSymbol` (asserted by `MtFskCodec`).
   - `blockLen` must fit in one byte (the frame header field is 8 bits).
   - `11 + blockLen + parityBytes` must be at most 255 (the Reed-Solomon limit).
   - Leave `parityBytes > gmdReserve` (4) so GMD retries can run.
2. Insert it into `AcousticTxProfile.audibleValues` or `silentValues`, in order from slowest to fastest. `slower` walks its band's list, `test/acoustic_channel_test.dart` checks that each profile is faster than the previous one in its band, and the speed chips iterate the band's list. `values` concatenates both.
3. Automatic detection needs no change: `AcousticFountainModem` builds one `AcousticFrameSync` per entry in `values`, and a frame only counts if Reed-Solomon, the CRC-16 and the header `blockLen` all agree. Every extra profile adds CPU work while hunting.
4. Add a `conditionHint` case if the default text does not fit.
5. Verify it through the room model in `test/acoustic_channel_test.dart` and the loopback tests in `test/acoustic_modem_test.dart`; the rate table in the [Sound Channel](../channels/SOUND_CHANNEL.md) document should be updated from `frameSeconds()` and `netBytesPerSecond()`.

### 22.4 Adding a new simulation scenario

1. Add a `ScenarioDefinition` to the `scenarios` list in `lib/core/simulation/scenarios.dart` with a unique kebab-case `id`, a `name`, a `description`, a `dataSize` and a `createPair` closure.
2. In `createPair`, call `createSimulationPair` (`lib/core/simulation/simulation_orchestrator.dart`). Remember:
   - An override profile replaces **all** fields of the default, so write every field you care about.
   - `discoverable: false` hides a channel from discovery, but `testAll` still tests it and it can still be chosen.
   - Degradation and recovery apply to endpoint A only, after that endpoint has sent `afterPacket` packets on the channel. Both use full replacement; when both have triggered, recovery wins.
3. The new scenario appears automatically in `AppController.availableScenarios`, the Simulation Lab picker and `runAllScenarios` (whose status text uses `scenarios.length`).
4. Add an assertion to `test/simulation_integration_test.dart` if the scenario must pass.

### 22.5 Adding a new envelope content type

1. Add the value at the **end** of `ChatMessageType` in `lib/core/chat/chat_message.dart`. The enum index is the wire value, so never reorder existing values.
2. Update the exhaustive `switch` in `ChatPayloadCodec.looksComplete` (`lib/core/chat/chat_payload_codec.dart`) with a validation rule, and decide in `decodeIncoming` whether the content lives in `text` or `data`.
3. Update `ChatMessage.preview`.
4. If it is Gallery media, extend `GallerySaver.canSave` and `_extension` in `lib/core/media/gallery_saver.dart`. If it needs preprocessing before sending (like photo compression), add it to `AppController._prepareEnvelope`.
5. Update `ComposePayload` (`lib/ui/models/compose_payload.dart`) and the received-content view; see the [UI Guide](./UI_GUIDE.md).
6. Compatibility: older builds reject an unknown type index in `looksComplete`, so they will silently drop the new message. Install the same build on every phone.

---

## 23. Related documents

- [Architecture](../architecture/ARCHITECTURE.md): layers and end-to-end flows.
- [Data Formats](../architecture/DATA_FORMATS.md): APCM, APCF, acoustic frame and packet layouts with hex dumps.
- [Light Channel](../channels/LIGHT_CHANNEL.md), [Sound Channel](../channels/SOUND_CHANNEL.md), [Vibration Channel](../channels/VIBRATION_CHANNEL.md): per-channel design and numbers.
- [Fountain Code](../algorithms/FOUNTAIN_CODE.md), [Reed-Solomon](../algorithms/REED_SOLOMON.md), [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md): the algorithms behind sections 11, 12, 5 and 17.
- [Testing](./TESTING.md): which test covers which class.
- [UI Guide](./UI_GUIDE.md): screens and widgets that call this API.

Back to the [documentation index](../README.md).
