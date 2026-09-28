# System Architecture

This document explains how the app is put together. It covers the layers, the responsibility of each module, the two data paths (direct fountain and packet protocol), the exact send and receive sequences, timers and threading, and the extension points.

Back to the [documentation index](../README.md).

---

## Contents

1. [Design goals](#1-design-goals)
2. [Layered view](#2-layered-view)
3. [Module responsibilities](#3-module-responsibilities)
4. [The two data paths](#4-the-two-data-paths)
5. [Send sequence in detail](#5-send-sequence-in-detail)
6. [Receive sequence in detail](#6-receive-sequence-in-detail)
7. [Concurrency, timers and isolates](#7-concurrency-timers-and-isolates)
8. [Source tree](#8-source-tree)
9. [State management](#9-state-management)
10. [Extension points](#10-extension-points)
11. [Cross-cutting concerns](#11-cross-cutting-concerns)

---

## 1. Design goals

| Goal | How the architecture meets it |
|---|---|
| **Physical only** | Every `CommChannel` implementation is optical, acoustic or vibration. The capability registry lists excluded transports, and a test enforces exactly three channels. |
| **Works without a return path** | Light and Sound use a rateless fountain code, so the sender never needs ACKs. This also gives one-to-many broadcast for free. |
| **Reusable, UI-free core** | Codecs (`LtEncoder`, `ReedSolomon`, `MtFskCodec`, `ChatPayloadCodec`, `PacketCodec`) are pure Dart with no Flutter imports. They run unchanged in tests, isolates and on the web. |
| **Smooth UI** | QR decoding runs in a background isolate; only one decode is in flight; the QR painter repaints only when the bitmap changes; the next QR is built while the current one is on screen. |
| **Testable without phones** | Channels share an interface, so simulated channels (`SimulatedCommChannel`) and a medium model stand in for hardware. Headless camera and room simulators drive the real decoders. |
| **Extend, don't overwrite** | Older modems (CSK light, APCS1 text QR, two-tone FSK) stay in the codebase with their tests, and new modems are added alongside them. |

---

## 2. Layered view

```
┌────────────────────────────────────── Presentation ─────────────────────────────────────┐
│ main.dart (MaterialApp, theme, AppProvider, full-screen QR overlay above every route)   │
│ ui/screens: Home · SendCompose · SendTransmit · Receive · Dev menu · Simulation ·       │
│             Hardware · Transfer (legacy chat) · Performance                             │
│ ui/widgets: QrBitmapView · Optical/Acoustic HUDs · aim guide · received content · …     │
└──────────────────────────────────────────┬──────────────────────────────────────────────┘
                                           │ ListenableBuilder(AppController / notifiers)
┌──────────────────────────────────────────▼──────────────────────────────────────────────┐
│ Application:  AppController (ChangeNotifier)                                             │
│   mode (simulation / hardware) · role (sender / receiver) · selected channel ·          │
│   chat list · send/receive flows · 80 ms receive poll · Gallery auto-save              │
└───────┬──────────────────────────────┬──────────────────────────────┬───────────────────┘
        │ direct envelope path         │ protocol path                │ simulation
┌───────▼──────────────┐   ┌───────────▼───────────────┐   ┌──────────▼─────────────────┐
│ FountainQrModem      │   │ TransferManager           │   │ SimulationOrchestrator     │
│ AcousticFountainModem│   │  + TransferStateMachine   │   │  + scenarios               │
│ (rateless, no ACK)   │   │  + ReliableTransport      │   │  + AdaptiveDecisionEngine  │
│                      │   │  + ChannelManager         │   │  + PerformanceComparator   │
└───────┬──────────────┘   └───────────┬───────────────┘   └──────────┬─────────────────┘
        │                              │                              │
┌───────▼──────────────────────────────▼──────────────────────────────▼──────────────────┐
│ Channels (CommChannel):                                                                  │
│   HardwareOpticalChannel · HardwareAcousticChannel · HardwareVibrationChannel           │
│   SimulatedCommChannel ×3 over VirtualLink / SimulatedMedium                            │
└───────┬──────────────────────────────┬──────────────────────────────┬──────────────────┘
┌───────▼──────────────────────────────▼──────────────────────────────▼──────────────────┐
│ Physical codecs (pure Dart):                                                             │
│   LT fountain · APCF frame · QR bitmap · QR gray frame · decode worker/isolate ·        │
│   MT-FSK · frame sync · acoustic frame · Reed-Solomon · CRC-16/32 · legacy codecs       │
└───────┬──────────────────────────────┬──────────────────────────────┬──────────────────┘
   screen / camera               speaker / microphone          motor / accelerometer
   (camera, qr, zxing2,          (audioplayers, record)        (vibration, sensors_plus)
    brightness MethodChannel)
```

**Dependency rule:** arrows point downwards only. Codecs know nothing about channels, channels know nothing about the controller, and the controller knows nothing about widgets. UI state that must update at frame rate (QR bitmap, HUD metrics, audio meters) flows through small dedicated `ChangeNotifier`s in `lib/core/platform/`, so a meter update doesn't rebuild the whole app.

---

## 3. Module responsibilities

| Folder | Key types | Responsibility |
|---|---|---|
| `lib/main.dart` | `AdaptiveCommApp`, `AppProvider` | App shell, dark Material 3 theme (seed `#3B82F6`), provides the single `AppController`, stacks the full-screen fountain QR overlay above all routes |
| `lib/application/` | `AppController` | Orchestrates everything. Starts and stops hardware per role and channel, prepares envelopes (image compression), picks the direct or protocol path, polls receivers, keeps the chat list, triggers Gallery saves |
| `lib/core/chat/` | `ChatMessage`, `ChatPayloadCodec` | Message model and the APCM envelope (type + name + MIME + bytes), including completeness checks |
| `lib/core/channels/` | `CommChannel`, `HardwareOpticalChannel`, `HardwareAcousticChannel`, `HardwareVibrationChannel`, web helpers | Uniform channel interface: `initialize`, `start`, `stop`, `discover`, `test`, `transmit`, `receive`, `getMetrics`, `isAvailable`. Hardware channels additionally expose `transmitEnvelope` / `receiveEnvelopes` for the fountain path |
| `lib/core/physical/fountain/` | `LtEncoder`, `LtDecoder`, `QrFountainFrameCodec`, `buildQrBitmap`, `FountainQrModem` | Light modem: fountain symbols → APCF frames → QR bitmaps; camera frames → decoded envelopes |
| `lib/core/physical/acoustic/` | `MtFskCodec`, `AcousticFrameSync`, `AcousticFrameCodec`, `ReedSolomon`, `AcousticFountainModem`, `AcousticTxProfile`, `HighPassFilter`, `ToneTimeline`, `SpectrumAnalyzer` | Sound modem: fountain symbols → RS-protected frames → multi-tone audio; microphone PCM → frames → envelopes. Also the tone schedule and FFT behind the live kHz readout |
| `lib/core/physical/` (root) | `OpticalTxProfile`, `extractQrGrayFrame`, `QrDecodeWorker`, `QrDecodeIsolatePool`, `decodeQrFrame…`, `physical_codecs.dart` | Light profiles and metrics, camera frame extraction, the decode isolate, the zxing2 decode sequence, legacy FSK / vibration codecs, WAV writer |
| `lib/core/physical/csk/` | `CskOpticalModem` | Legacy colour-shift keying modem |
| `lib/core/protocol/` | `PacketCodec`, `computeCrc32` | 24-byte packet header + CRC-32 |
| `lib/core/transport/` | `ReliableTransport` | Fragmentation, sliding window, ACK/NACK, retransmission, broadcast |
| `lib/core/manager/` | `TransferManager`, `TransferStateMachine`, `ChannelManager` | Runs a packet transfer end to end with validated state transitions; owns the channel set |
| `lib/core/engine/` | `AdaptiveDecisionEngine` | Normalises metrics, scores channels, decides degradation and switching |
| `lib/core/simulation/` | `SimulatedMedium`, `VirtualLink`, `SimulatedCommChannel`, scenarios, `SimulationOrchestrator` | Two virtual phones with configurable loss, corruption, latency and degradation schedules |
| `lib/core/performance/` | `PerformanceComparator` | Adaptive against fixed-channel strategy runs |
| `lib/core/media/` | `compressImageForTransfer`, `SampleMedia`, `GallerySaver` | Photo compression, bundled demo samples, saving to the Gallery |
| `lib/core/platform/` | `PlatformCapabilities`, `opticalTransmitterState`, `acousticReceiverState`, `OpticalDisplayControl`, … | Capability detection, UI-facing notifiers, brightness MethodChannel |
| `lib/core/logging/` | `StructuredLogger` | Categorised log entries shown in the dev screens |
| `lib/core/types/` | Enums, configs, metrics | `CommChannelId`, `PacketType`, `TransferState`, `ChannelMetrics`, `TransmissionConfig`, constants |

Full class-level detail: [API Reference](../development/API_REFERENCE.md).

---

## 4. The two data paths

### 4.1 Direct envelope path (normal for Light and Sound)

```
envelope ──► FountainQrModem.transmit / AcousticFountainModem.transmit
              (LT symbols, each self-describing; no packets, no ACKs)
receiver  ──► modem.receiveEnvelopes()  ──► AppController._addIncomingChat
```

- Used for **every Light message** (up to 8 MiB) and for **Sound messages up to the acoustic channel's `maxEnvelopeBytes`** (8 KiB).
- Every frame carries the session ID, K, block length and file length, so a receiver can **join mid-stream**.
- Many receivers can listen to one sender.
- The sender can't know when a receiver has finished, so it streams until stopped.

### 4.2 Protocol path (Vibration, oversized Sound, simulation)

```
envelope ──► TransferManager ──► ReliableTransport (fragment, window, ACK/NACK, retry)
         ──► PacketCodec (24-byte header + CRC-32) ──► CommChannel.transmit
receiver ──► CommChannel.receive ──► AppController reassembly buffer ──► envelope
```

- Packets are reassembled in `AppController` by sequence number. Delivery waits until every packet `1…N` is present when `totalPackets` is known; otherwise it waits for a contiguous run and a **1 800 ms idle timer**.
- `ChatPayloadCodec.looksComplete` rejects truncated envelopes (e.g. the first chunk of an image).
- In **unicast** mode the receiver ACKs each data packet. If an ACK would go back over Light, it is sent over Sound when that channel is available, because a phone's screen can't be seen by the sender's camera.
- In **broadcast** mode receivers stay silent.

---

## 5. Send sequence in detail

```
User taps "Show QR & send" / "Play & send" / "Start vibration"
 │
 ▼
SendTransmitScreen ──► AppController.sendPhysicalMessage(payload, channel)
 │  1. refuse if a transfer is running or the payload is empty
 │  2. configurePhysicalFlow(role: sender, channel)       (hardware mode, stop other channels)
 │  3. add an outgoing ChatMessage with status "sending"
 │  4. envelope = _prepareEnvelope(payload)
 │        image → compressImageForTransfer (≤ 960 px, ≤ 120 KB JPEG) → APCM(image/jpeg)
 │        other → payload.toEnvelope()
 │  5. Light and envelope > 8 MiB → status "failed"
 │  6. Light, or Sound with envelope ≤ acoustic maxEnvelopeBytes:
 │        _sendDirectEnvelope
 │          startHardwareChannels(sender)
 │          Light → HardwareOpticalChannel.transmitEnvelope → FountainQrModem.transmit
 │                  (brightness max, wakelock, 12 fps loop until Stop / 10 min cap)
 │          Sound → HardwareAcousticChannel.transmitEnvelope → AcousticFountainModem.transmit
 │                  (mic off, bursts of 2–4 frames as WAV until Stop / symbol budget)
 │        status → "sent" (no return path), or "failed"
 │  7. otherwise (Vibration, big Sound): runHardwareTransfer → TransferManager
 │        status → "delivered" if the transfer succeeded, else "failed"
 ▼
_restoreHardwareAfterTransfer, keep the outcome text for the result screen
```

The optical result text comes from `_opticalStreamSummary`, e.g. *"Streaming stopped (57 QR frames in 5s). If the receiver shows DONE, the file arrived; otherwise tap Resume — it keeps its progress."*

---

## 6. Receive sequence in detail

```
ReceiveScreen ──► AppController.startListening(channel)
                    configurePhysicalFlow(role: receiver, channel)
                    → only that channel's sensor is started (camera OR mic OR accelerometer)
                    → Timer.periodic(80 ms, _pollHardwareReceiver)

every 80 ms:
  _pollHardwareReceiver
   ├─ collect DecodedPackets from the selected channel only
   │    discovery → reply (unicast only)
   │    data → ACK (unicast) → buffer by sequence → arm 1 800 ms idle timer → try deliver
   │    transferComplete → learn totalPackets → try deliver
   └─ _pollDirectEnvelopes
        envelopes = optical.receiveEnvelopes() + acoustic.receiveEnvelopes()
        for each: _addIncomingChat(env)
                    ChatPayloadCodec.decodeIncoming → ChatMessage
                    image/video → GallerySaver.save (auto)
                  keep the camera streaming for the next message

Inside the Light modem (camera callback, ~30 fps):
  CameraImage → worker busy? drop : extractQrGrayFrame (Y plane crop)
             → QrDecodeWorker (isolate): zxing2 GlobalHistogram → pureBarcode → Hybrid
             → APCF parse + CRC-32 → LtDecoder(session).addSymbol
             → complete → APCM check → de-dup by CRC-32 → envelope buffer

Inside the Sound modem (mic callback, PCM16 44.1 kHz):
  PCM16 → float → AcousticFrameSync per profile (all 6 until locked; Silent ones high-pass at 16 kHz first)
        → marker search (64-sample steps, leading edge) → fine alignment
        → Goertzel soft demod → RS decode (+GMD) → CRC-16 → LtDecoder(session)
        → complete → de-dup by CRC-32 → envelope buffer → reopen to all profiles
  PCM16 → float → SpectrumAnalyzer ring ──(every 80 ms UI tick)──► FFT → acousticSpectrumState.rx → Hearing now

Sender readout:
  _renderBurst → MtFskCodec.describe → ToneTimeline ─► onBurst ─► _playWav: play() returns
        → acousticSpectrumState.startTxBurst → LiveToneMeter polls txNow() every 50 ms → Sending now
```

---

## 7. Concurrency, timers and isolates

| Mechanism | Where | Period / limit | Purpose |
|---|---|---|---|
| Receive poll | `AppController._startHardwareReceiverListener` | 80 ms `Timer.periodic` | Drain packets and envelopes from channels |
| Reassembly idle timer | `AppController._armIncomingIdleTimer` | 1 800 ms one-shot | Deliver multi-packet messages without a known total |
| Light metrics timer | `FountainQrModem.startReceiver` | 500 ms `Timer.periodic` | Keep the HUD alive (CAP/DEC windows, stall detection) even when nothing decodes |
| QR decode isolate | `QrDecodeWorker` | 1 in flight, 2 s reply timeout | Run zxing2 off the UI thread; frames arriving while busy are dropped |
| Light TX loop | `FountainQrModem.transmit` | `max(40, round(1000/fps))` ms per frame | Show a symbol, build the next, sleep the remainder |
| Sound TX loop | `AcousticFountainModem.transmit` | bursts of `max(2, min(4, K))` frames | Hand WAV clips to the player; `await play()` paces the loop |
| Microphone stream | `HardwareAcousticChannel` (`record`) | continuous PCM16 | Fed straight into frame sync; buffers are compacted after each probe |
| Receiver UI throttle | `HardwareAcousticChannel._updateRxUi` | at most one update per 80 ms | Meters, phase, and the one FFT behind **Hearing now** |
| Sender readout tick | `LiveToneMeter` | 50 ms `Timer.periodic`, only while a burst plays | Looks up the tone on air in the burst's `ToneTimeline` |
| Accelerometer stream | `HardwareVibrationChannel` | platform rate | Pulse timing |

**Why dropping frames is safe.** With a fountain code every symbol is equally valuable, so skipping a camera frame while the isolate is busy costs nothing but a moment. The alternative, queuing, would add latency and memory with no gain.

**Web.** Isolates for camera frames aren't used on the web. A canvas sampler (`optical_web_sampler_web.dart`) grabs a 640×640 centre patch and decodes it through `QrDecodeIsolatePool.submitWebPreview`.

---

## 8. Source tree

```
lib/
├── main.dart                               App shell, theme, provider, overlay
├── application/app_controller.dart         Central controller
├── core/
│   ├── channels/
│   │   ├── comm_channel.dart               CommChannel interface, capabilities
│   │   ├── hardware_channels.dart          HardwareAcousticChannel (+ shared helpers)
│   │   ├── hardware_optical_channel.dart   Camera setup, zoom/focus/exposure, fountain modem
│   │   ├── vibration_channel.dart          Motor TX, accelerometer RX
│   │   └── optical_web_*                   Conditional web/stub sampler and decoder
│   ├── chat/                               chat_message.dart, chat_payload_codec.dart
│   ├── engine/adaptive_decision_engine.dart
│   ├── logging/structured_logger.dart
│   ├── manager/                            channel_manager, transfer_manager, transfer_state_machine
│   ├── media/                              gallery_saver, image_compress, sample_media
│   ├── performance/performance_comparator.dart
│   ├── physical/
│   │   ├── fountain/                       lt_codec, qr_fountain_frame, qr_bitmap, fountain_qr_modem
│   │   ├── acoustic/                       mt_fsk_codec, acoustic_frame_sync, acoustic_fountain_frame,
│   │   │                                   reed_solomon, acoustic_fountain_modem, acoustic_tx_profile,
│   │   │                                   biquad_filter, tone_timeline, spectrum_analyzer
│   │   ├── csk/csk_optical_modem.dart      Legacy CSK modem
│   │   ├── optical_tx_profile.dart         Light profiles, Auto rule, metrics
│   │   ├── qr_gray_frame.dart              Y-plane crop
│   │   ├── qr_decode_worker.dart           Long-lived decode isolate
│   │   ├── qr_decode_isolate_pool.dart     Web preview decode path
│   │   ├── qr_frame_decoder.dart           zxing2 decode sequence
│   │   ├── qr_optical_codec.dart           Legacy APCS1 text QR
│   │   ├── optical_csk_codec.dart / optical_csk_sampler.dart / optical_modem.dart
│   │   ├── hardware_phy_config.dart        Hardware MTUs and direct-send limits
│   │   └── physical_codecs.dart            Legacy FSK, Goertzel, vibration codec, WAV
│   ├── platform/                           capabilities, notifiers, brightness control
│   ├── protocol/packet_codec.dart
│   ├── simulation/                         scenarios, simulated_medium, simulation_orchestrator
│   ├── transport/reliable_transport.dart
│   └── types/types.dart
└── ui/
    ├── models/                             compose_payload, physical_channel_mode
    ├── screens/                            home, send_compose, send_transmit, receive, dev_menu,
    │                                       simulation, hardware, transfer, performance
    ├── theme/app_layout.dart               Responsive layout helpers
    └── widgets/                            qr_bitmap_view, HUDs, live_tone_meter, overlays, content view, panels
```

---

## 9. State management

- **One controller.** `AppController extends ChangeNotifier` is created once by `AppProvider` in `main.dart`. `AppProvider` is a `StatefulWidget` that owns the controller, wraps a `ListenableBuilder` around it, and republishes it through a private `InheritedWidget` (`_InheritedApp`, `updateShouldNotify → true`) on every `notifyListeners()`. Screens read it with `AppProvider.of(context)`.
- **High-frequency notifiers.** Values that change many times per second live in singletons such as `opticalTransmitterState` (current QR bitmap, fountain session), the optical metrics notifier (HUD), `acousticReceiverState` / `acousticTransmitterState` (levels, phases, progress), `acousticSpectrumState` (the tones on air and the microphone spectrum for the live kHz readout) and `vibrationTransmitterState`. Only the widgets that display them listen.
- **Gallery state.** `GallerySaver.instance` is its own `ChangeNotifier`. The Save button listens only to it.
- **Full-screen QR overlay.** `MaterialApp.builder` in `main.dart` stacks `OpticalActiveOverlay` above the navigator. While a Light transmission is active it shows the full-screen fountain QR (`OpticalFountainQrOverlay`), so the code stays visible no matter which route started the transmission.

More in the [UI Guide](../development/UI_GUIDE.md).

---

## 10. Extension points

| To add… | Touch these | Notes |
|---|---|---|
| A new physical channel | Implement `CommChannel` (`lib/core/channels/comm_channel.dart`); add an id to `CommChannelId` (`types.dart`); register in `ChannelManager` and `AppController`; add a `PhysicalChannelMode` entry for the UI; update `platform_capabilities.dart` and `test/physical_only_test.dart` | Keep the physical-only policy: no radio transports |
| A new Light density profile | Add an `OpticalTxProfile` constant and include it in `values` | The picker reads `values`; keep `txFps ≤ 12` |
| A new Sound profile | Add an `AcousticTxProfile` to `values` (ordered slowest → fastest) | Auto-detection covers it automatically; check `codewordLength ≤ 255` |
| A new message type | Extend `ChatMessageType`, the envelope validation in `ChatPayloadCodec.looksComplete`, and `ReceivedContentView` | The type byte is the enum index, so append rather than insert |
| A new simulation scenario | Add to `scenarios.dart` | Appears in the Simulation Lab and in *Run All* |
| A new modem for an existing channel | Add alongside the old one (e.g. `physical/<name>/`) and select it in the hardware channel | Follows the extend-not-overwrite rule |

Step-by-step recipes are in [Contributing](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/docs/development/CONTRIBUTING.md).

---

## 11. Cross-cutting concerns

| Concern | Approach |
|---|---|
| **Integrity** | CRC-32 on Light frames and packets; CRC-16 plus Reed-Solomon on Sound frames; the APCM envelope is validated before display |
| **De-duplication** | Envelopes are de-duplicated by CRC-32; completed session IDs are remembered so the sender's "tail" is ignored |
| **Resilience** | Receivers keep partial decoders (Light: 3 sessions) across re-aim, screen exits and camera restarts |
| **Power** | Wakelock only while streaming or capturing; brightness restored after sending; 10-minute Light cap; Sound symbol budget `max(6K, K+24)` |
| **Logging** | `StructuredLogger` with categories (info, warning, error, discovery…) shown in the dev screens |
| **Platform differences** | Conditional imports (`*_web.dart` / `*_stub.dart`) for the web camera path; brightness control is Android-only; vibration is excluded on the web |
