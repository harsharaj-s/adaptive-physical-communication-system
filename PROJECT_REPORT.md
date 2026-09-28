# Adaptive Physical Communication System
## Project Report

**Project Name:** Adaptive Physical Communication System (APCS)  
**Author:** Harsharaj S  
**Last updated:** 28 September 2026  
**Repository:** [github.com/harsharaj-s/adaptive-physical-communication-system](https://github.com/harsharaj-s/adaptive-physical-communication-system)  
**Platform:** Flutter (Android, iOS, Web/Chrome)  
**Language:** Dart 3.11+  
**Communication Policy:** Physical channels only — no Internet, Wi-Fi, Bluetooth, NFC, or cloud for the data path

---

## 1. Abstract

This project implements a **phone-to-phone communication system** that transfers messages using only **physical media**: **light (QR codes)** and **sound (FSK tones)**, plus an experimental **vibration (motor pulses)** channel that doesn't work reliably yet. The application is built with **Flutter** and runs on mobile devices and web browsers. Users can compose text, images, links, or files and send them through a selected physical channel. Receivers decode the signal using the camera, microphone, or accelerometer.

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
| 1 | Implement three physical channels (optical, acoustic, vibration) | ⚠️ Partial: optical and acoustic done; vibration is implemented but experimental and unreliable on real phones |
| 2 | Encode/decode messages without network stack | ✅ Done |
| 3 | Support broadcast (one sender, many receivers) | ✅ Done |
| 4 | Build intuitive Send/Receive UI | ✅ Done |
| 5 | Adaptive channel scoring and switching | ✅ Done (simulation) |
| 6 | Reliable transport with ACK/retry | ⚠️ Implemented; under packet loss the ACK handling can stall a transfer ([Known Issues §3.1](docs/project/KNOWN_ISSUES.md#31-acks-are-treated-as-cumulative-high-for-the-protocol-path)) |
| 7 | Image and video transfer via fountain-coded QR | ✅ Done |
| 8 | Live feedback (QR progress, mic levels, live kHz readout on sender and receiver) | ✅ Done |
| 9 | Inaudible near-ultrasonic sound mode (Silent band, 18.3–19.9 kHz) | ✅ Done |

"Done" means implemented and covered by the automated tests, which run headless simulations of a phone camera and a room. Performance on real phones varies by model and hasn't been measured systematically (see §17 and §18). Adaptive switching runs only in the Simulation Lab and developer tools; in the Send/Receive screens the user picks the channel.

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

**Overhead:** `7 + nameLen + mimeLen` bytes. Text and links leave the file name and MIME type empty, so their overhead is 7 bytes ("sos" is a 10-byte envelope) and short texts fit a single Sound frame. The byte-level layout with hex dumps is in [Data Formats](docs/architecture/DATA_FORMATS.md).

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

**Why M-ary FSK rather than ASK or PSK.** The three M-ary keying families carry data in amplitude (ASK), phase (PSK) or frequency (FSK).
- **Amplitude** changes with distance, volume, the user's hand and room echoes, which notch single frequencies by 10–20 dB.
- **Phase** needs a carrier reference the two phones don't share. Their sample clocks drift, multipath smears phase, and at 19 kHz moving the phone by 1 cm shifts the phase by about 200°.
- **Frequency** survives all of these. The receiver compares energies at known bins (Goertzel, non-coherent) and picks the loudest of 16. FSK also has a constant envelope, which suits small speakers, and trades bandwidth (plentiful) for power (scarce).

The price is lower spectral efficiency than PSK or QAM in a clean channel.

**Two bands, six profiles.** Each tone carries 4 bits for one symbol:

| Profile | Band | Tones × symbol | Raw ms/bit | Net rate |
|---|---|---|---|---|
| Rugged | Audible 1.2–7.2 kHz | 6 × 139 ms | 5.8 | 10.8 B/s |
| Safe | Audible | 6 × 93 ms | 3.9 | 18.1 B/s |
| Standard | Audible | 8 × 93 ms | 2.9 | 27.0 B/s (4.6 ms per payload bit) |
| Fast | Audible | 8 × 70 ms | 2.2 | 35.8 B/s |
| Silent Robust | Silent 18.3–19.9 kHz | 1 × 70 ms | 17.4 | 3.4 B/s |
| Silent | Silent | 1 × 46 ms | 11.6 | 5.0 B/s (25 ms per payload bit) |

The **Silent** band plays one tone at a time, because two simultaneous tones would create an audible difference tone in a small speaker. Tones sit two bins (86 Hz) apart to tolerate hand-held Doppler. A guard frame at the start of each symbol lets echoes decay, and a 16 kHz high-pass in front of the Silent receivers keeps voices out. The receiver listens for all six profiles at once, locks onto whichever produces a valid frame, and reopens after each message. Verified against a simulated room channel (multipath, reverb, high-frequency roll-off, clock drift, noise, plus hand wobble and talkers for the near-ultrasonic scenarios) in `test/acoustic_*_test.dart`.

**Live frequency readout.** The sender's **Sending now** shows the exact tones on air, in kHz. It reads them from a `ToneTimeline` that `MtFskCodec.describe` writes alongside the waveform. The receiver's **Hearing now** shows the strongest frequencies its microphone picks up: a 1 024-point Hann-windowed FFT with parabolic peak interpolation, run at most once per 80 ms UI tick. Side by side, the two phones show the same kHz when the sound is getting through. This matters most for the Silent band, where there's nothing to hear.

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

> **Status: experimental.** The design below is implemented and its bit codec passes unit tests, but real phone-to-phone vibration transfers usually fail or never finish. See [Known Issues §2.8](docs/project/KNOWN_ISSUES.md#28-vibration-transfers-are-unreliable-on-real-phones-high).

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
| `acousticReceiverState` | Mic phase, input level, tone strength, Silent-band level, blocks recovered |
| `acousticTransmitterState` | Sound playback progress, profile, estimate |
| `acousticSpectrumState` | Tones on air (sender) and microphone spectrum (receiver) for the live kHz readout |
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
  → UI shows sent/failed status (Light and Sound have no return path, so they never claim "delivered")
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
| Light | SCAN/LOCK/DONE HUD, capture and decode rates, symbols collected of K, camera preview |
| Sound | **Hearing now** kHz readout with a 0–22 kHz spectrum strip; mic input, tone signal and Silent-band bars; blocks recovered; mic active indicator |
| Sound (sender) | **Sending now** kHz readout of the exact tones on air, playback progress and **Stop** |
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
| `lt_codec_test.dart`, `lt_small_k_test.dart` | LT encoder/decoder, APCF v3 frames, decoder rank against an independent GF(2) rank, overhead for K = 1…600 |
| `fountain_qr_roundtrip_test.dart` | Real QR render → rasterise → zxing2 → LT for text, photo, video and hostile binary data |
| `optical_density_sweep_test.dart` | Auto density and decode rates through a simulated hand-held camera |
| `fountain_benchmark_test.dart` | 365 KB recovery with frame loss, decoder speed, profile ladder |
| `acoustic_channel_test.dart` | All six Sound profiles through the room simulator, Silent band plan and energy below 16 kHz, near-ultrasonic scenarios |
| `acoustic_modem_test.dart` | Full WAV → room → PCM16 loopback, rateless stop, profile auto-detection across both bands |
| `acoustic_live_tone_test.dart` | Tone schedule matches the generated audio sample for sample; FFT finds 18 906 Hz within 8 Hz and every tone of a chord |
| `reed_solomon_test.dart` | GF(256) errors-and-erasures decoding |
| `protocol_test.dart` | CRC-32, packet encode/decode, corruption rejection |
| `physical_codecs_test.dart` | Legacy FSK, Goertzel, vibration, FskStreamDecoder |
| `qr_optical_codec_test.dart` | Legacy single/multi-chunk QR roundtrip |
| `image_envelope_test.dart` | JPEG → QR → reassemble → decode |
| `adaptive_engine_test.dart` | Channel scoring, hysteresis, degradation |
| `broadcast_mode_test.dart` | Broadcast TX without ACK, dedup |
| `simulation_integration_test.dart` | End-to-end scenario runs |
| `state_machine_test.dart` | Transfer state machine transitions |
| `sample_media_test.dart`, `gallery_saver_test.dart` | Demo samples within budget; Gallery save rules |
| `physical_only_test.dart`, `platform_capabilities_test.dart` | Policy, channel constraints, platform flags |
| `widget_test.dart` | Home screen smoke test |

**Run:** `flutter test` (22 test files, 101 tests: 100 pass, 1 optional sweep skipped). Full details in [Testing](docs/development/TESTING.md).

---

## 17. Performance Characteristics

Rates marked *nominal* are calculated from each profile's timing; *estimated* rates combine the raw frame rate with decode rates measured in the camera simulator. Ranges are recommendations. Real phones differ, so treat these as planning figures, not guarantees.

| Channel | Throughput | Recommended range | Broadcast | Best Content |
|---------|-------------------|-------|-----------|--------------|
| Light (fountain QR) | ≈1.3–2.5 KB/s estimated (Auto density, 12 fps) | Line of sight, 15–25 cm | ✅ Yes | Text, images, video, files |
| Sound, Audible (MT-FSK fountain) | ~86–286 bps nominal net (10.8–35.8 B/s) | Across a table; Rugged profile for noisy rooms | ✅ Yes | Text, small files |
| Sound, Silent (18.3–19.9 kHz) | ~27–40 bps nominal net (3.4–5.0 B/s) | Within about half a metre; inaudible to most adults | ✅ Yes | Short texts |
| Vibrate (experimental) | ≈4–5 bps nominal raw (≈0.5 B/s; 80/180 ms pulses + 60 ms gaps) | Contact only | ❌ No | Not reliable yet |

---

## 18. Limitations

1. **No internet fallback** — devices must be physically near each other
2. **Image size** — photos are compressed to ≤ 120 KB, and larger files need more fountain QR frames (a 40 KB photo takes about 20 s on Light)
3. **Sound sensitivity** — ambient noise and device speaker quality affect reliability; the Silent band works only on phones whose speaker and microphone pass 19 kHz
4. **Vibration** — experimental: real phone-to-phone transfers usually fail; it also needs firm physical contact and has a very low bit rate
5. **Web platform** — no vibration channel; camera/mic permissions vary by browser
6. **Security** — physical signals can be intercepted by nearby observers/listeners
7. **Adaptive switching** — not active in main Send/Receive flow (user selects channel)

---

## 19. Future Work

- Machine learning-based channel prediction (Phase 9)
- Adaptive switching in live hardware Send/Receive
- OFDM for Sound (more tones with a cyclic prefix against echo) for 2–3× the rate in quiet rooms; the near-ultrasonic Silent band is now shipped
- Improved QR throughput with custom symbology
- End-to-end encryption over physical channels
- Make the vibration channel reliable on real phones (per-phone pulse calibration, airtime-aware ACK timeout), then optimise it for iOS

---

## 20. Conclusion

The Adaptive Physical Communication System demonstrates that **meaningful data exchange** — including text, links, and compressed images — is achievable using only a smartphone's built-in sensors and actuators, without any radio networking. Two physical channels work today: light, for broadcast to groups via QR, and sound, for proximity text via tones. A third, contact-only communication via vibration, is implemented but still experimental and unreliable on real phones. None of the channels is encrypted or authenticated (see §18). The layered architecture (UI → controller → transport → codecs) with adaptive decision engine and reliable protocol provides a foundation for further research in offline proximity communication.

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
│   │   ├── hardware_channels.dart     # Acoustic hardware (re-exports the others)
│   │   ├── hardware_optical_channel.dart # Camera, zoom/focus/exposure, fountain QR
│   │   └── vibration_channel.dart     # Vibration hardware
│   ├── engine/
│   │   └── adaptive_decision_engine.dart
│   ├── manager/
│   │   ├── channel_manager.dart
│   │   ├── transfer_manager.dart
│   │   └── transfer_state_machine.dart
│   ├── media/                         # image_compress, sample_media, gallery_saver
│   ├── physical/
│   │   ├── fountain/                  # LT codec, APCF v3 frames, QR bitmap, FountainQrModem
│   │   ├── acoustic/                  # MT-FSK codec, frame sync, Reed-Solomon, frames,
│   │   │                              # fountain modem, profiles, high-pass filter,
│   │   │                              # tone timeline, spectrum analyzer
│   │   ├── csk/                       # Legacy colour-shift-keying modem
│   │   ├── optical_tx_profile.dart    # Light profiles, Auto density, metrics
│   │   ├── qr_decode_worker.dart      # Background decode isolate
│   │   ├── hardware_phy_config.dart   # Timing constants
│   │   ├── physical_codecs.dart       # Legacy FSK, Goertzel, VibrationBitCodec, WAV
│   │   ├── qr_optical_codec.dart      # Legacy QR chunk encode/reassemble
│   │   └── qr_frame_decoder.dart      # Camera → QR bytes (zxing2 sequence)
│   ├── platform/
│   │   ├── platform_capabilities.dart # Physical-only policy, optical state
│   │   ├── acoustic_receiver_state.dart
│   │   ├── acoustic_transmitter_state.dart
│   │   ├── acoustic_spectrum_state.dart # Live kHz readout (sender and receiver)
│   │   └── vibration_transmitter_state.dart
│   ├── protocol/
│   │   └── packet_codec.dart          # 24-byte header + CRC-32
│   ├── simulation/                    # Virtual endpoints, 9 scenarios
│   ├── transport/
│   │   └── reliable_transport.dart    # ACK, retry, sliding window
│   └── types/types.dart               # Enums, configs, metrics
└── ui/
    ├── screens/                       # Home, Send, Receive, Dev tools
    └── widgets/                       # QR overlay, camera preview, HUDs, live tone meter, content view
```

## Appendix B: Key Algorithms Summary

| Algorithm | Used In | Purpose |
|-----------|---------|---------|
| **LT fountain code (GF(2), incremental Gauss–Jordan)** | Light and Sound | Rateless: any ≈K frames rebuild the message, lost frames never resent |
| **Raw-byte fountain QR (APCF v3) + Auto density** | Light TX | Sparse QR versions 8–12 that a hand-held camera reads reliably |
| **zxing2 QR decode (GlobalHistogram → pureBarcode → Hybrid)** | Light RX | Extract the APCF frame from a camera frame, in a background isolate |
| **16-ary multi-tone FSK** | Sound TX/RX | 4 bits per tone; 6–8 tones at once (Audible) or one tone (Silent, 18.3–19.9 kHz) |
| **Goertzel detector (soft decisions)** | Sound RX | Tone energy per bin, plus per-byte confidence |
| **Reed-Solomon GF(256) + GMD erasures** | Sound RX | Repair damaged bytes in each frame |
| **4th-order Butterworth high-pass (16 kHz)** | Sound RX (Silent) | Keep voices out of the near-ultrasonic receiver |
| **Hann-windowed FFT + parabolic peak interpolation** | Sound RX UI | Live **Hearing now** frequency readout |
| **FSK (1800/3200 Hz), QR chunking + Base64URL** | Legacy modems | Kept for reuse, not selectable in the main UI |
| **Pulse-width modulation** | Vibrate TX/RX | Encode bits as short/long vibration pulses |
| **CRC-32** | Protocol | Packet integrity verification |
| **Sliding window + ACK/NACK** | Transport | Reliable delivery with retry |
| **Weighted channel scoring** | Adaptive engine | Select best channel by metrics |
| **Hysteresis switching** | Adaptive engine | Prevent channel flapping |
| **JPEG compression** | Image send | Reduce payload size for QR transfer |
| **Viterbi-style recovery** | Literature (RescQR) | Inspiration for QR error recovery |

---

*Report generated for the Adaptive Physical Communication System project.*
