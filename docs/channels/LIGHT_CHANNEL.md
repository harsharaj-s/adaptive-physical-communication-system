# Light Channel: Animated Fountain QR

The Light channel sends data from a phone's **screen** to another phone's **camera** as an animated stream of QR codes. Each code carries one symbol of a rateless fountain code, so the receiver doesn't need to catch every code. It completes as soon as it has caught about K good ones. This document covers the whole pipeline, from bytes to pixels and back, with the numbers behind every choice.

Back to the [documentation index](../README.md).

---

## Contents

1. [Overview](#1-overview)
2. [Source files](#2-source-files)
3. [Transmit pipeline](#3-transmit-pipeline)
4. [QR generation and rendering](#4-qr-generation-and-rendering)
5. [Density profiles and the Auto rule](#5-density-profiles-and-the-auto-rule)
6. [Why sparse codes win: optics](#6-why-sparse-codes-win-optics)
7. [Receive pipeline](#7-receive-pipeline)
8. [Session handling on the receiver](#8-session-handling-on-the-receiver)
9. [HUD metrics](#9-hud-metrics)
10. [Timing and throughput](#10-timing-and-throughput)
11. [Measured results](#11-measured-results)
12. [Web receiver](#12-web-receiver)
13. [Tuning guide](#13-tuning-guide)
14. [Failure modes](#14-failure-modes)

---

## 1. Overview

```
 SENDER                                                         RECEIVER
 APCM envelope                                                  APCM envelope ─► display + Gallery
   │                                                                ▲
   ▼ LtEncoder (blockLen from profile)                              │ LtDecoder per session (rank = K)
 symbol i ─► APCF v3 frame (22 B hdr + symbol + CRC-32)             │ APCF parse + CRC-32
   │                                                                │
   ▼ QrCode.fromUint8List, EC-L, mask 0                             │ zxing2 (isolate): GlobalHist → pure → Hybrid
 QR bitmap ─► QrBitmapView, pixel-snapped, full-screen white        │ Y-plane centre crop (706×706 at 720p)
   │          screen brightness forced to max                       │
   ▼ 12 frames/s (Safe: 8)                                          │ camera 1280×720, 1.5× zoom, −0.7 EV
 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ light, 15–25 cm ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

| Property | Value |
|---|---|
| Topology | One-to-many broadcast; no return path |
| Range | 15–25 cm (receiver at 1.5× zoom) |
| Frame rate | 12 fps (Safe 8 fps) |
| Payload per frame | 160 / 240 / 330 B (Auto), 600 B (Fast) |
| Frame overhead | 26 B |
| Practical goodput | ≈1.3–2.5 KB/s |
| Maximum envelope | 8 MiB (soft); practical < 200 KB |

---

## 2. Source files

| Area | File |
|---|---|
| Modem (TX loop, RX ingest, metrics) | `lib/core/physical/fountain/fountain_qr_modem.dart` |
| Fountain code | `lib/core/physical/fountain/lt_codec.dart` |
| Frame format | `lib/core/physical/fountain/qr_fountain_frame.dart` |
| QR matrix | `lib/core/physical/fountain/qr_bitmap.dart` |
| Profiles, Auto rule, ETA, metrics model | `lib/core/physical/optical_tx_profile.dart` |
| Camera frame → luminance | `lib/core/physical/qr_gray_frame.dart` |
| Decode isolate | `lib/core/physical/qr_decode_worker.dart` |
| zxing2 decode strategies | `lib/core/physical/qr_frame_decoder.dart` |
| Web preview decode | `lib/core/physical/qr_decode_isolate_pool.dart`, `lib/core/channels/optical_web_*` |
| Camera channel (zoom, focus, exposure) | `lib/core/channels/hardware_optical_channel.dart` |
| Brightness | `lib/core/platform/optical_display_control.dart`, `android/.../MainActivity.kt` |
| UI | `lib/ui/widgets/qr_bitmap_view.dart`, `optical_fountain_qr_overlay.dart`, `optical_transfer_hud.dart`, `optical_aim_guide.dart`, `optical_transfer_complete_card.dart` |

---

## 3. Transmit pipeline

`FountainQrModem.transmit(envelope)`:

1. **Size check.** Envelopes over `maxEnvelopeBytes = 8 × 1024 × 1024` throw.
2. **Resolve the profile.** `profile.resolveFor(envelope.length)`: Auto picks 160, 240 or 330 B (see [§5](#5-density-profiles-and-the-auto-rule)).
3. **Session ID.** `sessionIdFor(envelope, blockLen) = (CRC32(envelope) ^ (blockLen × 0x9E3779B1)) & 0xFFFFFFFF`, with 0 mapped to 1.
4. **Encoder.** `LtEncoder(data: envelope, blockLen, sessionId)` splits the envelope into K = ⌈len / blockLen⌉ zero-padded blocks.
5. **Frame period.** `frameMs = max(40, round(1000 / txFps))`: **83 ms** at 12 fps, **125 ms** at 8 fps.
6. **Prepare the screen.** Enable the wakelock; `OpticalDisplayControl.setMaxBrightness()` (Android sets `WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL` on the window).
7. **Resume point.** `firstIndex = _txResumeIndex[sessionId] ?? 0`.
8. **Loop** while the modem is active, the transmitter state says transmitting, and elapsed < **10 minutes**:
   - Publish the current bitmap to `opticalTransmitterState` (the overlay repaints).
   - Build the **next** symbol's QR while the current one is on screen.
   - Hold the **first** frame for `frameMs + 250 ms` (receiver autofocus); others for `frameMs`.
   - Sleep only the remainder of the period (build time is subtracted).
9. **Finally:**
   - Record `lastTxEnd` (`stopped` or `safetyCap`), `lastTxFrames` and `lastTxDuration`.
   - Store the next index in `_txResumeIndex` (the last 16 sessions are kept).
   - Clear the overlay, restore brightness, and release the wakelock unless the receiver is active.

**Symbol order.** Indices 0…K−1 are the original blocks (systematic). From K onwards every symbol is a fresh XOR mixture, and **no index is ever repeated** within a session, even across Resume.

**Safety cap.** 10 minutes × 12 fps ≈ 7 200 frames. On hitting it, the result text tells the user to tap Resume if the receiver hasn't shown DONE.

---

## 4. QR generation and rendering

### 4.1 Matrix

`buildQrBitmap(frameBytes, errorCorrectLevel: L, maskPattern: 0)` uses `package:qr`'s `QrCode.fromUint8List`, which produces a genuine **8-bit byte-mode** segment (no base64).

| Choice | Value | Reason |
|---|---|---|
| Error correction | **L** (≈7%) | The CRC-32 guarantees integrity and the fountain covers lost frames. Higher EC makes the code denser, which lowers the decode rate |
| Mask | **0, fixed** | The full mask search costs 15–40 ms on dense codes (visible stutter at 12 fps) against about 4 ms fixed. Random payloads score alike under every mask |
| Version | Smallest that fits `blockLen + 26` at EC-L | See the table below |

| blockLen | Framed bytes | Version | Modules per side (4v + 17) | EC-L byte capacity |
|---|---|---|---|---|
| 160 | 186 | 8 | 49 | 192 |
| 240 | 266 | 10 | 57 | 271 |
| 330 | 356 | 12 | 65 | 367 |
| 600 | 626 | 17 | 85 | 644 |
| 800 (old default) | 826 | 20 | 97 | 858 |

### 4.2 Rendering (`QrBitmapView`)

- White background with a **4-module quiet zone** on each side, as required by ISO/IEC 18004.
- **Module size** = `floor(shortestSide × devicePixelRatio / (modules + 8))` physical pixels, so every module is a whole number of device pixels. Nothing is blurred across a pixel boundary.
- Anti-aliasing **off**; horizontal runs of dark modules are merged into single rectangles, which reduces draw calls.
- Repaints **only when the bitmap object changes** (`shouldRepaint` compares bitmaps).
- The overlay sits above every route (`MaterialApp.builder` → `OpticalActiveOverlay`), full-screen white, with a **Stop** button.

**Example.** A phone with a 1 080-pixel short side showing QR v8 (49 + 8 = 57 modules): floor(1080 / 57) = **18 px per module**, and the code spans 57 × 18 = 1 026 px.

---

## 5. Density profiles and the Auto rule

### 5.1 Profiles (`OpticalTxProfile`)

| Profile | `id` | fps | blockLen | QR | `decodeTargetPx` | Nominal rate (blockLen × fps) |
|---|---|---|---|---|---|---|
| **Auto** (default) | `auto` | 12 | 160 / 240 / 330 | v8 / v10 / v12 | 720 | 1.92–3.96 KB/s |
| Safe | `safe` | 8 | 160 | v8 | 720 | 1.28 KB/s |
| Standard | `standard` | 12 | 330 | v12 | 720 | 3.96 KB/s |
| Fast | `fast` | 12 | 600 | v17 | 800 | 7.20 KB/s |

`slower` steps Fast → Standard and anything else → Safe (a hook for auto-backoff).

### 5.2 The Auto rule (`resolveFor`)

```
autoBlockLadder   = [160, 240, 330]
autoTargetSymbols = 48

for b in ladder:
    if ceil(envelopeBytes / b) ≤ 48: use b
otherwise: use 330
```

Equivalent thresholds:

| Envelope size | Block | QR |
|---|---|---|
| ≤ 7 680 B (48 × 160) | 160 | v8 |
| 7 681 – 11 520 B (48 × 240) | 240 | v10 |
| > 11 520 B | 330 | v12 |

**Rationale.** 48 symbols is about a 5-second transfer at a typical decode rate. Below that, the sparsest (most robust) code costs almost nothing extra in time. Above it, densifying keeps big files from dragging, but never past v12, because the "typical" decode rate falls off a cliff beyond that (v17: 31%, v20: 13%).

### 5.3 Why at most 12 fps

The camera captures at about 30 fps (33 ms per frame). A code must stay on screen for at least **two** exposures so that at least one capture sees it whole rather than mid-swap. 1000 / 12 = 83 ms ≈ 2.5 captures, which is safe. At 20 fps (50 ms) many captures would straddle a transition and decode as nothing. Because camera and screen aren't synchronised, the ETA model discounts decode rates for these straddled captures (the *yield* factor, [§10](#10-timing-and-throughput)).

---

## 6. Why sparse codes win: optics

### 6.1 Pixels per module

The receiver's frame is 1280×720, and the decoder uses a centred square of `0.98 × 720 = 706` px. Suppose the QR (with its quiet zone) fills about half of that square, the typical hand-held case, so about 353 px:

| QR | Modules incl. quiet zone | Pixels per module | Reads? |
|---|---|---|---|
| v8 | 49 + 8 = 57 | 353 / 57 ≈ **6.2** | Reliably |
| v10 | 57 + 8 = 65 | ≈ 5.4 | Almost always |
| v12 | 65 + 8 = 73 | ≈ **4.8** | Usually |
| v17 | 85 + 8 = 93 | ≈ 3.8 | Sometimes |
| v20 | 97 + 8 = 105 | ≈ **3.4** | Rarely |

A binarizer must decide each module from its centre pixels. With about 1 px of defocus blur (σ) plus about 1 px of hand-shake motion, the point-spread function is roughly 2–3 px wide. At 3.4 px per module neighbouring modules bleed into each other and become a grey smear. At 6 px the module centres stay clean.

### 6.2 Why zoom helps

Digital zoom on phones crops the **full-resolution sensor** (typically 12 MP or more) before scaling to the 720p stream. At 1.5× the same QR covers 1.5× more stream pixels per module, **real** resolution rather than interpolation. It also lets the user hold the phone at 15–25 cm, which every phone can focus on; many can't focus at 8–10 cm.

### 6.3 Why −0.7 EV

A screen at full brightness is the brightest object in view. Auto-exposure would otherwise choose a long exposure (motion blur) and could bloom the white modules into the black ones. Under-exposing by 0.7 EV shortens the exposure. Contrast barely matters to the decoder, but sharpness does (see [§11](#11-measured-results)).

---

## 7. Receive pipeline

### 7.1 Camera setup (`HardwareOpticalChannel`)

| Setting | Value |
|---|---|
| Camera | Back camera |
| Resolution | `ResolutionPreset.high` (1280×720) |
| Format | `ImageFormatGroup.yuv420` (web: `bgra8888`) |
| Audio | Off |
| Focus / exposure mode | `FocusMode.auto`, `ExposureMode.auto`, with focus and exposure points at the centre (0.5, 0.5) |
| Default zoom | `defaultReceiveZoom = 1.5`, clamped to the device's range; UI chips 1×/1.5×/2×/3× |
| Exposure offset | `receiveExposureOffsetEv = −0.7`, clamped to the device's range |
| Tap to focus | `focusAt(point)` re-runs autofocus and metering at the tapped point |

### 7.2 Luminance extraction (`extractQrGrayFrame`)

Runs **synchronously in the camera callback**, because the plugin recycles plane buffers as soon as the callback returns.

```
shortSide = min(width, height)                 → 720
cropSide  = round(shortSide × 0.98)            → 706
step      = clamp(round(cropSide / targetPx), 1, 8)   → round(706/720) = 1
outSide   = cropSide ÷ step                    → 706
```

- **YUV420 (Android):** plane 0 is luminance, so each row is a straight `setRange` copy (a `memmove`). 706 rows × 706 bytes ≈ 0.5 MB per frame.
- **BGRA (iOS / web):** `lum = (r + 2g + b) >> 2`, a green-weighted average like zxing's own.
- The square crop discards about 40% of a 16:9 frame for free and matches the on-screen aim brackets.

### 7.3 The decode isolate (`QrDecodeWorker`)

- One **long-lived** background isolate, started with the receiver.
- Frames are sent as `TransferableTypedData` (no copy across the isolate boundary).
- **At most one decode in flight.** `onCameraFrame` checks `_worker.isBusy` *before* extracting the frame, so a busy worker costs no copy at all. Dropped frames are counted in `DROP`.
- A **2-second reply timeout** means a lost reply can never freeze the receiver.

### 7.4 zxing2 decode sequence (`decodeQrBytesFromLuminance`)

The luminance buffer is wrapped as `RGBLuminanceSource.crop(lum, …)`, which takes bytes verbatim. Three attempts are made, and the first success wins:

| # | Binarizer | Hints | Why |
|---|---|---|---|
| 1 | `GlobalHistogramBinarizer` | QR only | A screen QR is high-contrast and evenly lit; the global threshold is fastest and won almost every sweep cell |
| 2 | Same bitmap | QR + `pureBarcode` | Random payload bytes can form fake 1:1:3:1:1 finder runs that outrank the real corners. `pureBarcode` reads the grid from the black bounding box instead; it rescued 100% of those frames (3–8% of dense codes) |
| 3 | `HybridBinarizer` | QR only | Uneven lighting or glare gradients |

`tryHarder` is off: at streaming rates, dropping a frame and taking the next symbol is cheaper. Every result is protected by the QR's own Reed-Solomon check, so no attempt can return wrong data silently. The bytes are taken from zxing's **byte segments** (falling back to raw bytes, then text).

### 7.5 Frame parse and fountain ingest

1. `qrFountainFrameCodec.decodeFromQrBytes(bytes)` checks the magic `APCF`, version 3 and the CRC-32 (with text fallbacks).
2. `_ingestFrame(frame)`:
   - **Ignore** frames of sessions already completed (the sender keeps streaming after we finish).
   - Find or create the `LtDecoder` for `frame.sessionId`. If K, `blockLen` or `fileLen` disagree with an existing decoder, replace it.
   - Keep at most **3** partial sessions (the oldest is evicted).
   - `decoder.addSymbol(symbolIndex, payload)` returns whether it added rank (NEW), and updates the DUP and RED counters.
   - When complete: `takeBytes()` → must start with `APCM` → mark the session completed → **de-duplicate** by CRC-32 against the last delivered envelope → push to the envelope buffer.
3. `AppController` polls `receiveEnvelopes()` every 80 ms and shows the message.

---

## 8. Session handling on the receiver

| Behaviour | Implementation | Benefit |
|---|---|---|
| Survives re-aiming, leaving the screen, camera restarts | `startReceiver` keeps `_decoders`; only an explicit clear drops them | Progress is never lost by accident |
| Several senders or densities | Up to `_maxRxSessions = 3` decoders keyed by session ID | A stray frame from another sender doesn't wipe progress |
| Sender's tail after DONE | `_completedSessions` set | No duplicate deliveries, no re-lock |
| Same file sent twice | `_lastDeliveredCrc` | Delivered once |
| Resume on the sender | Same session ID (content + density), new indices | The receiver continues seamlessly |

---

## 9. HUD metrics

Published through `OpticalMetricsNotifier` as `OpticalTransferMetrics`:

| Field | Meaning | Computation |
|---|---|---|
| SCAN / LOCK / DONE | No session / decoding a session / complete | `locked = sessionId != null`, `complete` |
| **CAP** | Camera frames per second | captures ÷ window seconds |
| **DEC** | Successful QR reads per second | decodes ÷ window seconds |
| **DROP** | Frames skipped because the worker was busy | worker + pool counters |
| **GOOD** | Goodput (KB/s) | useful symbols × blockLen ÷ elapsed; on completion fileLen ÷ elapsed |
| **NEW / DUP / RED** | Rank-adding / repeated index / linearly dependent symbols | `LtDecoder` counters |
| *x / K symbols* | Progress | `rank / K` |
| `K=…` label | Block count of the locked session | shown instead of the profile label |
| Amber hint | "No codes readable…" | `!complete && CAP > 2 && staleSeconds ≥ 4` |

**Windowing.** A window closes after ≥ 1 000 ms on the capture path, or on the 500 ms timer tick (minimum 400 ms). Each window with captures but zero decodes increments `staleSeconds`, and any decode resets it. With the 500 ms timer, four stale windows is about 2 s of nothing readable.

The receiving phone's `opticalTransmitterState.setConfidence(progress)` also drives the progress indicator.

---

## 10. Timing and throughput

### 10.1 ETA formula (`estimatedSeconds`)

```
p      = profile.resolveFor(bytes)
K      = ceil(bytes / p.blockLen)
yield  = 0.70 if blockLen ≤ 160
         0.65 if blockLen ≤ 240
         0.55 if blockLen ≤ 330
         0.35 otherwise
ETA    = ceil( (K + 2) / (p.txFps × yield) )     seconds
```

`yield` is the simulated "typical" decode rate discounted for captures that straddle a display refresh. The `+2` covers the fountain's average overhead.

### 10.2 Worked examples

| Payload | Block | K | Symbols/s | ETA |
|---|---|---|---|---|
| "sos" (31 B) | 160 | 1 | 12 × 0.70 = 8.4 | ⌈3 / 8.4⌉ = **1 s** |
| 2 000 B | 160 | 13 | 8.4 | ⌈15 / 8.4⌉ = **2 s** |
| 5 130 B photo | 160 | 33 | 8.4 | ⌈35 / 8.4⌉ = **5 s** |
| 10 300 B photo | 240 | 43 | 12 × 0.65 = 7.8 | ⌈45 / 7.8⌉ = **6 s** |
| 20 290 B photo | 330 | 62 | 12 × 0.55 = 6.6 | ⌈64 / 6.6⌉ = **10 s** |
| 80 055 B video | 330 | 243 | 6.6 | ⌈245 / 6.6⌉ = **38 s** |
| 139 222 B video | 330 | 422 | 6.6 | ⌈424 / 6.6⌉ = **65 s** |
| 122 880 B photo (cap) | 330 | 373 | 6.6 | ⌈375 / 6.6⌉ = **57 s** |
| Same 80 KB on **Safe** | 160 | 501 | 8 × 0.70 = 5.6 | ⌈503 / 5.6⌉ = **90 s** |
| Same 80 KB on **Fast** | 600 | 134 | 12 × 0.35 = 4.2 | ⌈136 / 4.2⌉ = **33 s** (only if the camera keeps up) |

### 10.3 Effective goodput

```
goodput ≈ blockLen × txFps × yield
Auto 160: 160 × 12 × 0.70 = 1 344 B/s ≈ 1.3 KB/s
Auto 240: 240 × 12 × 0.65 = 1 872 B/s ≈ 1.9 KB/s
Auto 330: 330 × 12 × 0.55 = 2 178 B/s ≈ 2.2 KB/s
Fast 600: 600 × 12 × 0.35 = 2 520 B/s ≈ 2.5 KB/s  (good conditions only)
```

---

## 11. Measured results

### 11.1 Camera simulator tiers (`test/optical_camera_sim.dart`)

| Tier | QR share of view | Rotation | Skew | Blur σ | Motion blur | Black / white level | Gamma | Noise σ | Glare |
|---|---|---|---|---|---|---|---|---|---|
| good | 62% | ±4° | 3% | 0.7 px | 0 | 35 / 220 | 0.9 | 3 | 0 |
| typical | 50% | ±8° | 6% | 1.1 px | 1 px | 60 / 205 | 0.8 | 6 | 0.1 |
| hard | 42% | ±12° | 8% | 1.5 px | 2 px | 80 / 195 | 0.7 | 8 | 0.2 |

### 11.2 Decode rate per frame (production decoder)

| Block | QR | good | typical | hard |
|---|---|---|---|---|
| 160 B | v8 | 100% | **100%** | 63% |
| 240 B | v10 | 100% | **94%** | 13% |
| 330 B | v12 | 100% | **81%** | 0% |
| 600 B | v17 | 100% | 31% | 0% |
| 800 B | v20 | 100% | **13%** | 0% |
| 1 200 B | v25 | 81% | 0% | 0% |

One-factor-at-a-time sweeps ranked the factors: **sharpness** (focus and shake) matters most, then **how much of the frame the code fills**, then **noise**. Contrast barely matters.

### 11.3 End-to-end (simulation)

| Test | Result |
|---|---|
| 2 KB, Auto, typical camera, 30% of frames lost | Completes after ≈22 frames shown (≈1.8–2.3 s) |
| 2 KB, hard camera at 1.5× zoom | Completes after ≈23 frames (≈1.9–3.7 s) |
| Old 800 B density, hard camera | 0 frames decoded in 20 s |
| 40 KB photo / 30 KB video through real QR, zxing2 and LT at 30% loss | Byte-exact |
| Production decoder on perfect renders | < 1% frame loss per profile |

---

## 12. Web receiver

- The browser camera is sampled by `optical_web_sampler_web.dart`: a **640×640 centre patch** drawn to a canvas at about 30 Hz (`Duration(milliseconds: 33)` tick).
- Decoding goes through `QrDecodeIsolatePool.submitWebPreview()` and returns **text**. That's why APCF has the `FQR3:` base64url fallback and the receiver tries code units and UTF-8 on text results.
- Brightness control and wakelock handling are skipped on the web.

---

## 13. Tuning guide

| Situation | Change |
|---|---|
| Receiver phone has a weak camera or no autofocus | Sender: **Safe**. Receiver: 2× zoom, hold at about 25 cm |
| Bright room, reflections | Tilt the sender 10–20°; move away from lamps; the receiver taps to refocus |
| Long file, steady tripod, good light | **Standard** or **Fast** |
| Many receivers at once | Keep **Auto** or **Safe**; receivers at different distances benefit from sparse codes |
| DEC is high but progress is slow | That's normal near the end of a small-K transfer; wait for the last 1–2 repair symbols |
| CAP below 15 fps | The receiver phone is throttling (heat, battery saver); close other apps |

---

## 14. Failure modes

| Symptom | Likely cause | Mechanism that protects you |
|---|---|---|
| SCAN forever | QR not fully inside the crop, out of focus, glare | Amber hint after about 2 s; tap-to-focus; zoom chips |
| LOCK, but DEC stays low | Hand shake, small code, washed-out screen | Fountain: any frames count; switch to Safe |
| Stuck one symbol short | The needed repair symbol hasn't been caught yet | Keep streaming; K+2 symbols complete with ≥ 75% probability, K+7 with ≥ 99% (dense regime) |
| Sender stopped early | User tapped Stop | **Resume streaming** continues the same session with new symbols |
| Two senders in view | Mixed frames | Per-session decoders (up to 3); CRC-32 per frame |
| Different app builds | Frame version mismatch | v2 frames are rejected rather than mis-decoded |
| Receiver screen left mid-transfer | Navigation | Partial decoders survive `startReceiver` |

See also [Troubleshooting](../operations/TROUBLESHOOTING.md) and the math in [Fountain Code](../algorithms/FOUNTAIN_CODE.md).
