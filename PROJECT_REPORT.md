# Adaptive Physical Communication System
## Project Report

**Project Name:** Adaptive Physical Communication System (APCS)  
**Platform:** Flutter (Android, iOS, Web/Chrome)  
**Language:** Dart 3.11+  
**Communication Policy:** Physical channels only — no Internet, Wi-Fi, Bluetooth, NFC, or cloud for the data path

---

## 1. Abstract

This project implements a **phone-to-phone communication system** that transfers messages using only **physical media**: **light (QR codes)**, **sound (FSK tones)**, and **vibration (motor pulses)**. The application is built with **Flutter** and runs on mobile devices and web browsers. Users can compose text, images, links, or files and send them through a selected physical channel. Receivers decode the signal using the camera, microphone, or accelerometer.

The system includes an **adaptive decision engine** that scores channel quality (throughput, latency, reliability, confidence, stability) and can switch channels mid-transfer in simulation mode. A **reliable transport layer** provides packet sequencing, CRC-32 integrity checks, ACK/NACK, and retransmission for legacy protocol transfers. For real-time hardware use, a **direct envelope path** bypasses fragmentation for faster optical and acoustic delivery.

---

## 2. Introduction

Modern smartphones rely heavily on radio-based networking (Wi-Fi, Bluetooth, cellular). This project explores an alternative: **near-field physical communication** using hardware already present on every phone — screen, camera, speaker, microphone, vibration motor, and accelerometer.

The application supports:
- **One-to-many broadcast** (Light and Sound) — one sender, multiple receivers
- **One-to-one unicast** (Vibration and optional ACK mode)
- **Adaptive channel selection** (simulation and dev tools)
- **Rich content** — text, links, compressed images, video, files

---

## 3. Problem Statement

Traditional wireless protocols require shared spectrum, pairing, and network infrastructure. In environments where radio is unavailable, undesirable, or insecure, there is a need for **offline, proximity-based communication** using physical signals. Challenges include:

- Low bandwidth on acoustic and vibration channels
- Motion blur and rolling shutter in screen-camera links
- Ambient noise affecting microphone decoding
- Physical contact requirement for vibration
- Reliable reassembly of multi-chunk payloads (especially images via QR)

---

## 4. Objectives

| # | Objective | Status |
|---|-----------|--------|
| 1 | Implement three physical channels (optical, acoustic, vibration) | ✅ Done |
| 2 | Encode/decode messages without network stack | ✅ Done |
| 3 | Support broadcast (one sender, many receivers) | ✅ Done |
| 4 | Build intuitive Send/Receive UI | ✅ Done |
| 5 | Adaptive channel scoring and switching | ✅ Done (simulation) |
| 6 | Reliable transport with ACK/retry | ✅ Done |
| 7 | Image transfer via optical QR chunking | ✅ Done |
| 8 | Live feedback on receive (QR progress, mic levels) | ✅ Done |

---

## 5. Literature Survey

| Channel | IEEE Paper | Key Idea |
|---------|-----------|----------|
| **Light** | *RescQR: Enabling Reliable Data Recovery in Screen-Camera Communication System* (Han et al., IEEE TMC, 2023) | Dynamic QR on screen → camera decode; Viterbi recovery for blurred frames |
| **Sound** | *Ultrasonic Communication Using Consumer Hardware* (Getreuer et al., IEEE TMM, 2017) | FSK modulation over speaker/mic on commodity phones |
| **Vibrate** | *Privacy-Aware Communication for Smartphones Using Vibration* (Hwang et al., IEEE RTCSA, 2012) | Vibrator TX + accelerometer RX through shared physical medium |

---

## 6. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter UI Layer                         │
│  Home → Send Compose → Mode Picker → Transmit Screen         │
│  Home → Receive → Mode Picker → Listen + Content View        │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│              AppController (ChangeNotifier)                  │
│  • Mode: simulation / hardware                               │
│  • Role: sender / receiver                                   │
│  • Channel lock: optical / acoustic / vibration              │
│  • 80 ms hardware poll timer                                 │
│  • Chat message store + status                               │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
┌────────▼────────┐ ┌──────▼──────┐ ┌───────▼────────┐
│ Direct Envelope │ │ TransferMgr │ │  Simulation    │
│ (fast path)     │ │ + Reliable  │ │  Orchestrator  │
│ Optical/Acoustic│ │ Transport   │ │  (9 scenarios) │
└────────┬────────┘ └──────┬──────┘ └───────┬────────┘
         │                 │                 │
┌────────▼─────────────────▼─────────────────▼────────┐
│              ChannelManager + Codecs                   │
│  HardwareOptical │ HardwareAcoustic │ HardwareVibration│
│  QrOpticalCodec  │ FskCodec/Goertzel│ VibrationBitCodec│
└──────────────────────────────────────────────────────┘
```

### 6.1 Layer Breakdown

| Layer | Path | Responsibility |
|-------|------|----------------|
| **UI** | `lib/ui/screens/`, `lib/ui/widgets/` | User interaction, mode selection, content display |
| **Application** | `lib/application/app_controller.dart` | Orchestration, timers, state, send/receive flow |
| **Manager** | `lib/core/manager/` | Transfer lifecycle, discovery, channel registration |
| **Transport** | `lib/core/transport/reliable_transport.dart` | Sliding window, ACK/NACK, retry, broadcast mode |
| **Engine** | `lib/core/engine/adaptive_decision_engine.dart` | Channel scoring, degradation, hysteresis switching |
| **Channels** | `lib/core/channels/` | Hardware + simulated channel implementations |
| **Physical** | `lib/core/physical/` | QR, FSK, vibration, Goertzel algorithms |
| **Protocol** | `lib/core/protocol/` | 24-byte packet header + CRC-32 |
| **Chat** | `lib/core/chat/` | APCM message envelope encoding/decoding |

---

## 7. Message Format (APCM Envelope)

All user content is packed into a binary **APCM envelope** before physical encoding:

```
┌──────────┬──────────┬─────────┬──────────┬─────────┬──────────┬─────────────┐
│ "APCM"   │ type (1) │ nameLen │ fileName │ mimeLen │ mimeType │ raw payload │
│ 4 bytes  │ byte     │ 1 byte  │ UTF-8    │ 1 byte  │ UTF-8    │ bytes       │
└──────────┴──────────┴─────────┴──────────┴─────────┴──────────┴─────────────┘
```

**Message types:** text, link, image, video, file

**Image handling:** Photos are compressed to JPEG (max ~120 KB, 960×960) before envelope creation (`lib/core/media/image_compress.dart`).

**Validation:** `looksComplete()` checks envelope structure and image magic bytes (JPEG SOI, PNG, GIF, WebP).

---

## 8. Physical Channels — Algorithms & Implementation

### 8.1 Light Channel (Optical / Fountain QR)

**Physical medium:** Light from sender screen → receiver camera

**Default modem — Fountain QR (APCF):**
1. APCM envelope split into K equal blocks; block length chosen by the **Auto** profile from the payload size
2. Systematic fountain symbols: first K are source blocks, then XOR repair symbols (random subsets for K ≤ 256, fixed-weight random rows above; a keyed cycle through all non-empty subsets for K ≤ 8)
3. Each symbol packed as binary `APCF` v3 frame (session, index, K, blockLen, fileLen, payload, CRC-32)
4. Sender displays the animated QR at full brightness, 12 FPS, until the user taps **Stop** (10-minute safety cap)
5. Receiver decodes QR via camera (1.5x zoom, busy workers drop frames; fountain absorbs loss)
6. Exact incremental GF(2) Gauss-Jordan decoder completes as soon as the symbols reach rank K (measured mean overhead 0–2.2 symbols for K = 1…600) → APCM delivered

**Also available (reusable, not deleted):**
- **CSK modem** — Color Shift Keying for short text (≤180 B), kept as `CskOpticalModem`
- **Sequential APCS1 QR codec** — library + tests in `qr_optical_codec.dart`

**Key files:**
- `lib/core/physical/fountain/` (LT codec, APCF frames, FountainQrModem)
- `lib/core/physical/csk/csk_optical_modem.dart`
- `lib/core/channels/hardware_optical_channel.dart`
- `lib/ui/widgets/optical_fountain_qr_overlay.dart`, `optical_transfer_hud.dart`

**Profiles:**

| Profile | FPS | Block len | QR version | Notes |
|---------|-----|-----------|-----------|-------|
| Auto | 12 | 160 / 240 / 330 B | v8 / v10 / v12 | Default: sparsest code needing ≤ 48 symbols |
| Safe | 8 | 160 B | v8 (49 modules) | Too far, shaky, washed out |
| Standard | 12 | 330 B | v12 (65 modules) | |
| Fast | 12 | 600 B | v17 (85 modules) | Steady hand, close range, good light |

**Why these densities.** `test/optical_camera_sim.dart` renders each QR the
way a phone camera sees another phone: perspective and rotation, sub-pixel
optical integration, Gaussian and motion blur, washed-out contrast and gamma,
glare, noise, the code at 40–62% of the frame with a dark bezel around it.
Decode rate per captured frame (`test/optical_density_sweep_test.dart`):

| Block | QR | good | typical | hard |
|-------|----|------|---------|------|
| 160 B | v8 | 100% | 100% | 63% |
| 240 B | v10 | 100% | 94% | 13% |
| 330 B | v12 | 100% | 81% | 0% |
| 600 B | v17 | 100% | 31% | 0% |
| 800 B | v20 | 100% | 13% | 0% |
| 1200 B | v25 | 81% | 0% | 0% |

"typical" (code at half the view, hand-held) matches the field report of the
old 800 B default: DEC 2.0/s out of CAP 18 fps ≈ 11%. One-factor-at-a-time
runs showed sharpness (focus, shake) dominates, then how much of the frame the
code fills, then noise; contrast barely matters. Hence sparse codes, 1.5x
sensor zoom (the receiver can stand back to 15–25 cm, where every phone can
focus), centre focus/metering with tap-to-refocus, and −0.7 EV exposure
(shorter exposures blur less across QR swaps). End to end, a 2 KB file with
30% of frames lost completes after ~1.9–2.3 s of streaming in "typical" and
~2.3–3.7 s in "hard"; at the old density "hard" never decoded a frame.

**Why the old fountain stalled at "1 / 3 symbols".** The robust soliton
distribution puts ~47% of symbols at degree K when K is small, so for K = 3
most repair symbols were the same all-blocks equation. Only 56% of random
K+2 symbol sets (K = 1…10) were full rank and K = 3 finished with five
distinct repair symbols 69% of the time, while the HUD counted every such
symbol as "new". The replacement code design and exact decoder fix both, and
`test/lt_small_k_test.dart` checks the decoder against an independent rank
computation.

Frame rates are capped so every QR stays on screen for at least two camera
exposures; displaying faster only guarantees the receiver catches codes
mid-swap, which decode as nothing.

**Wire format.** Frames travel as raw QR **byte mode** (`APCF` v3, 22-byte
header + 4-byte CRC-32). Byte mode carries bytes verbatim, so the earlier
base64url armouring — which cost 33% of every frame — is gone. Encoding uses
a fixed mask pattern: searching all eight costs ~15 ms per frame versus ~4 ms
and measures no more reliable, because fountain payloads are already random.

**Transmit is rateless.** The sender mints an endless series of brand-new
symbols and never repeats an index, so every frame the receiver manages to
read makes progress. Reassembly therefore depends on decode *throughput*, not
on the sender guessing how many symbols to send. There is no back-channel, so
the sender streams until the user stops it once the receiver shows DONE, and
never claims success on its own. The session id is derived from the content,
so **Resume streaming** continues the same session with fresh symbols; the
receiver keeps up to three partial sessions across re-aiming, screen
re-entry and receiver restarts, so a failed attempt is simply continued.

**Receive path.** The camera's Y plane *is* luminance, so a centre-square crop
is handed to zxing with no colour conversion, then decoded in a long-lived
background isolate. Frames arriving while a decode is in flight are dropped
untouched — the next symbol is worth as much as the current one.

Finder-pattern detection loses 3–8% of frames at every QR version, because
random payload bytes can form 1:1:3:1:1 runs that outrank the real corners.
A `pureBarcode` second pass reads the grid off the black bounding box instead
and recovers **all** of them; `test/fountain_qr_roundtrip_test.dart` guards
this by rendering real QR bitmaps, rasterising them and decoding with real
zxing2 end to end. On camera frames the global-histogram binariser beat the
hybrid one in almost every cell of the sweep, and cropping to the code's
region halved decode time without changing the success rate, so the decoder
order stays global → pure → hybrid without ROI tracking.

**Recommended next step (not shipped).** A native decoder (ML Kit barcode
scanning) as primary with zxing2 as fallback, carrying frames as base45
(RFC 9285) in QR alphanumeric mode: the base45 alphabet is exactly the QR
alphanumeric set, costs ~3% capacity versus byte mode, and survives any
decoder that only returns a string, sidestepping ML Kit's inconsistent
`rawBytes` for binary QR. It was not shipped because a native decoder cannot
be exercised by the headless harness and needs on-device verification.

**Best for:** Text, images, video, files, **one-to-many broadcast**

---

### 8.2 Sound Channel (Acoustic / FSK)

**Physical medium:** Sound waves from speaker → receiver microphone

**Default modem — fountain over multi-tone FSK** (`lib/core/physical/acoustic/`):

| Layer | Technique | Why |
|-------|-----------|-----|
| Waveform | Multi-tone FSK: 6–8 tones at once, each picks 1 of 16 FFT-bin frequencies (4 bits); ~1.2–7 kHz | Several bits per symbol instead of one; orthogonal, click-free tones |
| Sync | Two-tone burst before every frame, earliest-onset lock, then fine alignment on tone separation | Survives reflections that arrive louder than the direct path |
| Per frame | Reed-Solomon GF(256) with errors-and-erasures decoding + CRC-16 | Repairs bytes lost to multipath nulls and speaker roll-off |
| Soft decode | Per-byte confidence (winning vs runner-up tone); failed frames retried with the weakest bytes declared erasures (GMD) | An erasure costs half the parity of an unknown error |
| Across frames | LT fountain code (shared with the QR channel) | Rateless — lost frames never need resending |

Profiles: Rugged ~11 B/s, Safe ~18 B/s, Standard ~27 B/s, Fast ~36 B/s. The receiver listens for all profiles, locks onto whichever produces a valid frame, and reopens after each message. Verified against a simulated room channel (multipath, reverb, high-frequency roll-off, clock drift, noise) in `test/acoustic_*_test.dart`.

**Legacy modem — two-tone FSK** (`AcousticModemKind.legacyFsk`):
- **Bit 0:** 1800 Hz tone (F0)
- **Bit 1:** 3200 Hz tone (F1)
- **Preamble:** `[1,0,1,0,1,0,1,0]` (8 bits)
- **Symbol duration:** 18 ms
- **Sample rate:** 44100 Hz

**TX flow:**
1. Frame envelope: `[2-byte LE length][APCM payload]`
2. `FskCodec.encodeBytes()` → PCM tone samples
3. Prepend 180 ms silence (AGC settle)
4. Convert to WAV, play via speaker (3× repeat, 350 ms gap)

**RX flow:**
1. Microphone PCM16 stream @ 44100 Hz
2. **Goertzel algorithm** detects F0/F1 energy per symbol window
3. `FskStreamDecoder` accumulates samples, finds preamble, decodes length-framed envelope
4. Valid APCM → message delivered

**Key files:**
- `lib/core/physical/acoustic/` (MtFskCodec, AcousticFrameSync, ReedSolomon, AcousticFrameCodec, AcousticFountainModem, AcousticTxProfile)
- `lib/core/physical/physical_codecs.dart` (Goertzel, FskCodec, FskStreamDecoder — legacy)
- `lib/core/channels/hardware_channels.dart` (HardwareAcousticChannel)
- `lib/core/platform/acoustic_receiver_state.dart` (live mic/tone UI feedback)

**Parameters:**

| Parameter | Value |
|-----------|-------|
| F0 / F1 | 1800 / 3200 Hz |
| Symbol duration | 18 ms |
| Max direct envelope | 900 bytes |
| TX repeat count | 3 |
| Lead silence | 180 ms |

**Best for:** Short text, ~30 cm range, quiet room

---

### 8.3 Vibrate Channel

**Physical medium:** Mechanical vibration through phone contact / shared surface

**Algorithm — Pulse-Width Modulation:**
- **Bit 0:** Short pulse (80 ms)
- **Bit 1:** Long pulse (180 ms)
- **Gap between bits:** 60 ms
- **Preamble:** `[0,1,0,1,0,1,1,0]`

**TX:** Vibration motor pulses per bit (`Vibration.vibrate`)

**RX:** Accelerometer magnitude vs adaptive baseline; pulse duration → bit; preamble search → packet assembly

**Key files:**
- `lib/core/physical/physical_codecs.dart` (VibrationBitCodec)
- `lib/core/channels/vibration_channel.dart`

**Parameters:**

| Parameter | Value |
|-----------|-------|
| Short / long pulse | 80 / 180 ms |
| Inter-bit gap | 60 ms |
| Max packet size | 48 bytes (protocol path) |

**Best for:** Very short text, phones pressed together, **1-to-1 only**

---

## 9. Protocol Layer (Legacy / Large Payloads)

When direct envelope is not used (vibration, large acoustic payloads), data flows through the **reliable transport protocol**:

### 9.1 Packet Structure

```
┌──────────────── 24-byte Header ────────────────┬──────── Payload ────────┬── CRC-32 ──┐
│ version, sessionId, transferId, type, channel, │ variable length (≤8192) │ 4 bytes    │
│ sequence, totalPackets, payloadLength           │                         │            │
└─────────────────────────────────────────────────┴─────────────────────────┴────────────┘
```

### 9.2 Reliable Transport Features

| Feature | Implementation |
|---------|----------------|
| Integrity | CRC-32 (`computeCrc32`) |
| Acknowledgment | ACK/NACK packets (unicast mode) |
| Retransmission | Up to 8 retries, 20 s ACK timeout |
| Sequencing | Sequence numbers + sliding window (size 4) |
| Discovery | Discovery/discovery-response handshake |
| Broadcast | No ACKs — sender completes after TX |
| Deduplication | Transfer ID + sequence tracking |

**File:** `lib/core/transport/reliable_transport.dart`

---

## 10. Adaptive Decision Engine

**Purpose:** Automatically select and switch between channels based on measured quality.

### 10.1 Scoring Formula

```
score = 0.35 × throughput_norm
      + 0.25 × reliability_norm
      + 0.15 × (1 - latency_norm)
      + 0.15 × confidence_norm
      + 0.10 × stability_norm
```

### 10.2 Switching Logic

| Condition | Action |
|-----------|--------|
| Current score < 0.65 (degradation threshold) | Mark channel degraded |
| Alternative score > current + 0.15 (hysteresis) | Switch channel |
| Mid-transfer evaluation | Every 20 loop iterations (simulation) |

**Components:**
- `MetricNormalizer` — scales metrics to 0–1
- `ChannelScorer` — weighted composite score
- `AdaptiveDecisionEngine` — selection, degradation, switch evaluation

**File:** `lib/core/engine/adaptive_decision_engine.dart`

**Note:** Main Send/Receive UI uses **fixed channel selection** (user picks Light/Sound/Vibrate). Adaptive switching is active in **Simulation Lab** and **Performance Comparison** screens.

---

## 11. Eventing & State Management

### 11.1 Central Controller

`AppController extends ChangeNotifier` is the single source of truth:

| State | Description |
|-------|-------------|
| `_mode` | `simulation` or `hardware` |
| `_role` | `sender` or `receiver` |
| `_selectedPhysicalChannel` | Locked channel (optical/acoustic/vibration) |
| `_transferMode` | `broadcast` or `unicast` |
| `_chatMessages` | Sent/received message list |
| `_statusMessage` | User-facing status string |
| `_hardwareChannelsActive` | Channels running flag |
| `_running` | Transfer in progress flag |

### 11.2 Timers & Polling

| Timer | Interval | Purpose |
|-------|----------|---------|
| `_hardwareListenTimer` | 80 ms | Poll optical/acoustic/vibration for incoming data |
| `_incomingIdleTimer` | 1800 ms | Deliver incomplete multi-packet assemblies |
| QR scan throttle | 40 ms | Limit camera decode attempts |
| Web QR sample | 40 ms | Web platform QR polling |

### 11.3 UI State Notifiers (ChangeNotifier)

| Notifier | Purpose |
|----------|---------|
| `opticalTransmitterState` | QR TX frame index/total, scan confidence, chunk progress |
| `acousticReceiverState` | Mic phase, input level, tone strength, decode status |
| `vibrationTransmitterState` | Vibrating flag, accelerometer magnitude |

### 11.4 Event Flow — Send

```
User taps Send
  → SendComposeScreen (pick content)
  → ModePickerSheet (Light / Sound / Vibrate)
  → SendTransmitScreen
  → AppController.sendPhysicalMessage()
      → _prepareEnvelope() [compress image if needed]
      → configurePhysicalFlow(role: sender, channel)
      → IF optical OR small acoustic:
            _sendDirectEnvelope() → transmitEnvelope()
         ELSE:
            runHardwareTransfer() → TransferManager → ReliableTransport
      → _restoreHardwareAfterTransfer()
  → UI shows delivered/failed status
```

### 11.5 Event Flow — Receive

```
User taps Receive
  → ModePickerSheet (Light / Sound / Vibrate)
  → ReceiveScreen
  → AppController.startListening(channel)
      → configurePhysicalFlow(role: receiver, channel)
      → startHardwareChannels(enableReceiver: true)
      → _startHardwareReceiverListener() [80 ms timer]
  → Every 80 ms: _pollHardwareReceiver()
      → channel.receive() [protocol packets]
      → _pollDirectEnvelopes() [APCM envelopes]
      → ChatPayloadCodec.decodeIncoming()
      → notifyListeners()
  → ReceiveScreen shows ReceivedContentView
  → User can "Clear & keep listening" for next message
```

### 11.6 Broadcast vs Unicast Events

| Event | Broadcast | Unicast |
|-------|-----------|---------|
| Discovery | Skipped | Sender broadcasts discovery packet |
| ACK on receive | **Disabled** (prevents acoustic feedback loop) | Receiver sends ACK |
| Transfer complete | Sender finishes after all packets TX | Waits for ACKs |
| Multiple receivers | Supported (optical, acoustic) | One paired receiver |
| Vibration | N/A (forced unicast) | Contact-only 1:1 |

---

## 12. User Interface

### 12.1 Production Screens

| Screen | File | Purpose |
|--------|------|---------|
| Home | `home_screen.dart` | Send / Receive entry, physical-only policy banner |
| Send Compose | `send_compose_screen.dart` | Text, image, video, link picker |
| Mode Picker | `mode_picker_sheet.dart` | Light / Sound / Vibrate selection |
| Send Transmit | `send_transmit_screen.dart` | Channel-specific TX UI with progress |
| Receive | `receive_screen.dart` | Listen UI, live feedback, received content card |
| Received Content | `received_content_view.dart` | Text/image/video/link display |

### 12.2 Developer Screens

| Screen | Purpose |
|--------|---------|
| Simulation Lab | 9 scenarios, live metrics, adaptive switching |
| Hardware Channels | Direct channel test (flash, mic, vibration) |
| Legacy Transfer | Role picker, broadcast/unicast, detailed logs |
| Performance Comparison | Fixed optical vs acoustic vs adaptive baselines |

### 12.3 Receive UI Feedback

| Channel | Live Feedback |
|---------|---------------|
| Light | QR chunk progress (X/Y), scan confidence bar, camera preview |
| Sound | Mic input level bar, tone signal bar, mic active indicator |
| Vibrate | Accelerometer magnitude percentage |

---

## 13. Technology Stack

| Category | Technology |
|----------|-----------|
| Framework | Flutter 3.x (Dart SDK ^3.11.0) |
| Camera | `camera` + `zxing2` (QR decode) |
| QR encoding | `qr` (byte mode), painted by `QrBitmapView` |
| Audio TX | `audioplayers` (WAV playback) |
| Audio RX | `record` (PCM16 mic stream) |
| Vibration | `vibration` + `sensors_plus` (accelerometer) |
| Permissions | `permission_handler` |
| Image processing | `image` (compress/resize) |
| File picking | `file_picker` |
| State | `ChangeNotifier` + `ListenableBuilder` |
| Platforms | Android, iOS, Chrome (Web) |

---

## 14. Simulation Mode

Simulation runs two virtual endpoints in one process with configurable channel profiles:

**Scenarios (9):**
- `optical-always-good`, `acoustic-always-good`
- `optical-degrades`, `both-degrade`, `acoustic-recovers`
- `random-loss`, `burst-loss`, `repeated-degradation`
- `vibration-coupled`

Each scenario defines packet loss, latency, throughput, confidence, stability, and optional degradation/recovery schedules. The adaptive engine can switch channels mid-transfer based on live metrics.

**Files:** `lib/core/simulation/scenarios.dart`, `simulation_orchestrator.dart`

---

## 15. Physical-Only Policy

Enforced at design level — no network transports in the data path:

**Excluded:** Internet/IP, Wi-Fi, Bluetooth, NFC, cellular/SMS, cloud servers

**Allowed channels:** Optical (screen/camera), Acoustic (speaker/mic), Vibration (motor/accelerometer)

**File:** `lib/core/platform/platform_capabilities.dart`

---

## 16. Testing

| Test File | Coverage |
|-----------|----------|
| `protocol_test.dart` | CRC-32, packet encode/decode, corruption rejection |
| `physical_codecs_test.dart` | FSK, Goertzel, vibration, FskStreamDecoder |
| `qr_optical_codec_test.dart` | Single/multi-chunk QR roundtrip |
| `image_envelope_test.dart` | JPEG → QR → reassemble → decode |
| `adaptive_engine_test.dart` | Channel scoring, hysteresis, degradation |
| `broadcast_mode_test.dart` | Broadcast TX without ACK, dedup |
| `simulation_integration_test.dart` | End-to-end scenario runs |
| `physical_only_test.dart` | Policy and channel constraints |
| `widget_test.dart` | Home screen smoke test |

**Run:** `flutter test` (35 tests)

---

## 17. Performance Characteristics

| Channel | Typical Throughput | Range | Broadcast | Best Content |
|---------|-------------------|-------|-----------|--------------|
| Light (QR) | 400+ kbps goodput (literature); app uses chunked QR | Line of sight, 5–30 cm | ✅ Yes | Text, images, links |
| Sound (MT-FSK fountain) | ~90–290 bps net (11–36 B/s) | Across a table; Rugged profile for noisy rooms | ✅ Yes | Text, small files |
| Vibrate | ~5–80 bps | Contact only | ❌ No | Very short text |

---

## 18. Limitations

1. **No internet fallback** — devices must be physically near each other
2. **Image size** — large photos require many QR frames (30–60+ chunks)
3. **Sound sensitivity** — ambient noise and device speaker quality affect reliability
4. **Vibration** — requires firm physical contact; very low bit rate
5. **Web platform** — no vibration channel; camera/mic permissions vary by browser
6. **Security** — physical signals can be intercepted by nearby observers/listeners
7. **Adaptive switching** — not active in main Send/Receive flow (user selects channel)

---

## 19. Future Work

- Machine learning-based channel prediction (Phase 9)
- Adaptive switching in live hardware Send/Receive
- Near-ultrasonic (17–22 kHz) inaudible acoustic mode
- Improved QR throughput with custom symbology
- End-to-end encryption over physical channels
- iOS vibration/accelerometer optimization

---

## 20. Conclusion

The Adaptive Physical Communication System demonstrates that **meaningful data exchange** — including text, links, and compressed images — is achievable using only a smartphone's built-in sensors and actuators, without any radio networking. Three complementary physical channels (light, sound, vibration) cover different use cases: broadcast groups via QR, proximity text via tones, and secure contact-only via vibration. The layered architecture (UI → controller → transport → codecs) with adaptive decision engine and reliable protocol provides a foundation for further research in offline proximity communication.

---

## 21. References

1. H. Han et al., "RescQR: Enabling Reliable Data Recovery in Screen-Camera Communication System," *IEEE Transactions on Mobile Computing*, 2023. DOI: [10.1109/TMC.2023.3277212](https://doi.org/10.1109/tmc.2023.3277212)

2. P. Getreuer et al., "Ultrasonic Communication Using Consumer Hardware," *IEEE Transactions on Multimedia*, vol. 20, no. 6, 2018. DOI: [10.1109/TMM.2017.2766049](https://doi.org/10.1109/tmm.2017.2766049)

3. I. Hwang, J. Cho, and S. Oh, "Privacy-Aware Communication for Smartphones Using Vibration," *IEEE RTCSA*, 2012. DOI: [10.1109/RTCSA.2012.43](https://doi.org/10.1109/rtcsa.2012.43)

4. T. Wang et al., "Streaming QR Codes–A Survey," *IEEE Access*, 2024. DOI: [10.1109/access.2024.3461970](https://doi.org/10.1109/access.2024.3461970)

---

## Appendix A: Project File Structure

```
lib/
├── main.dart                          # App entry, AppProvider, OpticalQrOverlay
├── application/
│   └── app_controller.dart            # Central orchestrator, timers, send/receive
├── core/
│   ├── chat/
│   │   ├── chat_message.dart          # Message model (type, status, data)
│   │   └── chat_payload_codec.dart    # APCM envelope encode/decode
│   ├── channels/
│   │   ├── comm_channel.dart          # Channel interface + simulated channels
│   │   ├── hardware_channels.dart     # Optical + Acoustic hardware
│   │   └── vibration_channel.dart     # Vibration hardware
│   ├── engine/
│   │   └── adaptive_decision_engine.dart
│   ├── manager/
│   │   ├── channel_manager.dart
│   │   ├── transfer_manager.dart
│   │   └── transfer_state_machine.dart
│   ├── media/
│   │   └── image_compress.dart        # JPEG compression for transfer
│   ├── physical/
│   │   ├── hardware_phy_config.dart   # Timing constants
│   │   ├── physical_codecs.dart       # FSK, Goertzel, VibrationBitCodec
│   │   ├── qr_optical_codec.dart      # QR chunk encode/reassemble
│   │   └── qr_frame_decoder.dart      # Camera → QR string
│   ├── platform/
│   │   ├── platform_capabilities.dart # Physical-only policy
│   │   ├── acoustic_receiver_state.dart
│   │   └── vibration_transmitter_state.dart
│   ├── protocol/
│   │   └── packet_codec.dart          # 24-byte header + CRC-32
│   ├── simulation/                    # Virtual endpoints, 9 scenarios
│   ├── transport/
│   │   └── reliable_transport.dart    # ACK, retry, sliding window
│   └── types/types.dart               # Enums, configs, metrics
└── ui/
    ├── screens/                       # Home, Send, Receive, Dev tools
    └── widgets/                       # QR overlay, camera preview, content view
```

## Appendix B: Key Algorithms Summary

| Algorithm | Used In | Purpose |
|-----------|---------|---------|
| **QR chunking + Base64URL** | Light TX/RX | Split large payloads into scannable frames |
| **zxing2 QR decode** | Light RX | Extract chunk string from camera frame |
| **FSK (1800/3200 Hz)** | Sound TX/RX | Encode bits as frequency tones |
| **Goertzel detector** | Sound RX | Detect F0/F1 energy per symbol |
| **Pulse-width modulation** | Vibrate TX/RX | Encode bits as short/long vibration pulses |
| **CRC-32** | Protocol | Packet integrity verification |
| **Sliding window + ACK/NACK** | Transport | Reliable delivery with retry |
| **Weighted channel scoring** | Adaptive engine | Select best channel by metrics |
| **Hysteresis switching** | Adaptive engine | Prevent channel flapping |
| **JPEG compression** | Image send | Reduce payload size for QR transfer |
| **Viterbi-style recovery** | Literature (RescQR) | Inspiration for QR error recovery |

---

*Report generated for the Adaptive Physical Communication System project.*
