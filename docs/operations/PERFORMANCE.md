# Performance

How fast each channel is, where the time goes, and how the app keeps the UI smooth while it decodes camera frames or audio in real time. All the numbers come from the formulas in the code or from the test suite's measurements. The derivations are in [Calculations](../algorithms/CALCULATIONS.md).

Back to the [documentation index](../README.md).

---

## Contents

1. [Channel speeds](#1-channel-speeds)
2. [Transfer time tables](#2-transfer-time-tables)
3. [Where Light time goes](#3-where-light-time-goes)
4. [Where Sound time goes](#4-where-sound-time-goes)
5. [CPU and threading](#5-cpu-and-threading)
6. [Memory](#6-memory)
7. [Battery and heat](#7-battery-and-heat)
8. [App size](#8-app-size)
9. [Measured results](#9-measured-results)
10. [Tuning for speed](#10-tuning-for-speed)

---

## 1. Channel speeds

| Channel | Nominal | Typical goodput | Range |
|---|---|---|---|
| Light, Auto (v8–v12, 12 fps) | 1.9–4.0 KB/s | ≈1.3–2.5 KB/s | 15–40 cm |
| Light, Safe (v8, 8 fps) | 1.28 KB/s | ≈0.9 KB/s | Weak cameras |
| Light, Fast (v17, 12 fps) | 7.2 KB/s | ≈2.5 KB/s *if* the camera keeps up | Good cameras only |
| Sound, Rugged / Safe / Standard / Fast | 10.8 / 18.1 / 27.0 / 35.8 B/s | ≈80% of nominal after fountain overhead | 0.3–2 m |
| Vibration | ≈0.52 B/s raw | Less, after packet overhead | Touching |

Light is about 35–70× faster than the fastest Sound profile. That's why photos and videos go by Light.

---

## 2. Transfer time tables

**Light (Auto, typical camera):**

| Payload | ETA |
|---|---|
| Text message | ≈1 s |
| 2 KB photo sample (3.4 KB envelope after re-encode) | ≈3 s |
| 5 KB photo sample (8.6 KB) | ≈5 s |
| 20 KB photo sample (33 KB) | ≈16–17 s |
| 80 KB video | ≈38 s |
| 140 KB video | ≈65 s |
| 120 KiB photo (compression cap) | ≈57 s |

**Sound:**

| Payload | Rugged | Safe | Standard | Fast |
|---|---|---|---|---|
| "sos" (31 B) | 11.9 s | 10.6 s | 9.5 s | 7.2 s |
| 100-character text (≈128 B) | 20.8 s | 15.9 s | 11.8 s | 8.9 s |
| 500 B | 65 s | 42 s | 28 s | 21 s |
| 2 KB photo sample (3.4 KB) | ≈6.7 min | ≈4.0 min | ≈2.8 min | ≈2.1 min |

**Vibration:** "hi" ≈113 s, "hello" ≈119 s, a full 48-byte packet ≈148 s.

---

## 3. Where Light time goes

```
per displayed frame (83 ms at 12 fps):
  sender:   LT symbol (XOR of up to ~21 blocks) + APCF header + CRC-32   < 1 ms
            QR matrix with fixed mask 0                                  ≈ 4 ms   (15–40 ms with mask search)
            paint (merged dark runs, no anti-aliasing)                   ≈ 1 frame
  receiver: camera capture (30 fps)                                      33 ms apart
            Y-plane copy of a 706×706 crop                               ≈ 0.5 MB memmove
            zxing2 decode in the isolate                                  tens of ms
            LT ingest (incremental Gauss-Jordan)                          < 1 ms (K = 422)
```

**The bottleneck is the camera's decode rate, not the CPU.** A frame is lost when:
- the capture straddles a display refresh (half old QR, half new),
- motion blur or defocus smears modules (worse at higher QR versions),
- the decoder is still busy with the previous frame (counted as DROP).

The fountain code turns all of these into "a bit more time" instead of failure. Auto density keeps the QR version where the decode rate stays high: v8 about 70%, v12 about 55%, v17 about 31%, v20 about 13% in the camera simulator.

---

## 4. Where Sound time goes

```
per frame (Standard, 2.368 s):
  2 048-sample sync marker            46 ms
  25 data symbols × 4 096 samples     2.32 s
per burst: 120 ms of lead silence, then 2–4 frames back-to-back
```

- **Airtime dominates.** Generating the WAV and decoding take a small fraction of real time on a phone.
- **Fountain overhead.** The receiver needs about `1.25·K + 2` frames in expectation, so at least 25% extra airtime for frame loss.
- **Reed-Solomon.** It repairs up to 12 bad bytes per 99-byte frame (24 with erasures), so a frame with a few damaged symbols isn't wasted.

---

## 5. CPU and threading

| Work | Thread | Why it stays smooth |
|---|---|---|
| QR rendering | UI thread | Fixed mask (≈4 ms), integer module sizes, merged rectangles, repaint only when the bitmap changes |
| Camera frame extraction | Camera callback (UI isolate) | Y-plane row copies only; skipped entirely when the decoder is busy |
| QR decoding | **One long-lived background isolate** | `TransferableTypedData` (no copy), at most one frame in flight, 2 s reply timeout |
| LT decoding | UI isolate | Incremental: each symbol costs at most about K × K/32 word XORs (≈41 000 for K = 422), well under a millisecond |
| Audio capture and conversion | Plugin thread → Dart | PCM16 converted straight into a `Float32List` (no per-sample boxing) |
| Tone detection and RS decoding | Dart isolate (UI) | Goertzel on the needed bins only; RS is `O(n·P)` per frame |
| Timers | UI isolate | 80 ms receive poll, 500 ms metrics tick, 1 800 ms idle timer |

Frames are **dropped, not queued**, when the decoder is busy. Queueing would add latency and memory without adding information, because the fountain only needs *some* frames, not *all* frames.

---

## 6. Memory

| Item | Size |
|---|---|
| One camera luminance crop | ≈0.5 MB (706 × 706) |
| LT decoder, K = 422, 330-byte blocks | ≈163 KB (coefficient rows + payload rows) |
| LT decoder, K = 1 133 | ≈0.5 MB |
| Up to 3 concurrent Light sessions | 3 × the above, worst case |
| Sound burst WAV (4 Standard frames) | ≈0.8 MB PCM16 |
| Largest envelope accepted by Light | 8 MiB (soft cap); practical < 200 KB |

---

## 7. Battery and heat

- **Light sending** keeps the screen at full brightness with a wakelock. That's the biggest drain in the app. Brightness is restored and the wakelock released when streaming stops.
- **Light receiving** runs the camera at 720p with continuous decoding. Phones warm up after several minutes; if CAP drops below about 15 fps, the phone is throttling.
- **Sound** is light on both sides (speaker or microphone plus modest DSP).
- **Vibration** runs the motor for minutes for even short messages.
- The 10-minute Light safety cap prevents a forgotten sender from draining the battery.

---

## 8. App size

| Component | Size |
|---|---|
| Universal release APK | ≈58 MB |
| Bundled samples (16 photos + 9 videos) | 1 238 839 B ≈ 1.2 MB |
| Branding assets (logo + mark) | 103 925 B ≈ 100 KB |

`flutter build apk --split-per-abi` produces much smaller per-architecture APKs; most of the universal size is the Flutter engine and native plugin libraries for every CPU architecture.

---

## 9. Measured results

From the test suite ([Testing](../development/TESTING.md)):

| Measurement | Result |
|---|---|
| 2 KB file, Auto, typical camera, 30% frame loss | Completes after 22 frames shown (13 decoded), ≈1.8 s |
| 2 KB file, hard camera at 1.5× zoom | Completes after 23 frames shown (14 decoded), ≈1.9 s |
| Old 800-byte density, hard camera | 0 frames decoded in 20 s |
| 40 KB photo / 30 KB video through real QR + zxing2 + LT at 30% loss | Byte-exact |
| Fountain overhead (measured mean) | 0–2.2 symbols |
| Full test suite | 88 tests, ≈38 s |
| Full optical density sweep (`OPTICAL_SWEEP=1`) | ≈3 min 16 s |

---

## 10. Tuning for speed

| Situation | Setting | Gain |
|---|---|---|
| Good receiver camera, steady hands | Light **Standard** or **Fast** | Up to 2× on large files |
| Weak camera | Light **Safe** + 2× zoom at 25 cm | Completes instead of stalling |
| Quiet room, phones close | Sound **Fast** | 1.3× over Standard |
| Big file | Always Light | 35–70× over Sound Fast |
| Many receivers | Light Auto (sparse codes) | Every camera decodes independently; no extra time |

More in [Light Channel](../channels/LIGHT_CHANNEL.md) and [Sound Channel](../channels/SOUND_CHANNEL.md).
