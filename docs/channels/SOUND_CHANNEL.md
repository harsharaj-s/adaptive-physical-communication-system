# Sound Channel: Multi-Tone FSK + Reed-Solomon + Fountain

The Sound channel sends data from a phone's **speaker** to another phone's **microphone**. It uses three layers, each solving a different problem:

1. **Multi-tone FSK (MT-FSK)** turns bytes into chords of audible tones: 4 bits per tone, 6–8 tones at once.
2. **Reed-Solomon** repairs the bytes a single frame loses to echoes and noise, using soft-decision erasures.
3. The **LT fountain code**, the same one the Light channel uses, makes whole lost frames irrelevant, so no return path is needed.

Back to the [documentation index](../README.md).

---

## Contents

1. [Overview](#1-overview)
2. [Source files](#2-source-files)
3. [Waveform: tones, bins and the band plan](#3-waveform-tones-bins-and-the-band-plan)
4. [Demodulation with soft decisions](#4-demodulation-with-soft-decisions)
5. [Frame synchronisation](#5-frame-synchronisation)
6. [Frame format and error correction](#6-frame-format-and-error-correction)
7. [Profiles](#7-profiles)
8. [Automatic profile detection](#8-automatic-profile-detection)
9. [Transmitter](#9-transmitter)
10. [Receiver](#10-receiver)
11. [Room simulator and results](#11-room-simulator-and-results)
12. [Timing tables](#12-timing-tables)
13. [Tuning guide and failure modes](#13-tuning-guide-and-failure-modes)

---

## 1. Overview

```
TX  APCM envelope
     └─► LtEncoder(blockLen = L)             symbols 0,1,2,… (rateless)
          └─► AcousticFrameCodec              9 B header + L payload + CRC-16 → + P RS parity
               └─► MtFskCodec.encode          2-frame sync marker + ⌈(11+L+P)/(G/2)⌉ data symbols
                    └─► bursts of 2–4 frames + 120 ms lead silence → PCM16 WAV → speaker

RX  microphone PCM16 mono 44.1 kHz → float
     └─► AcousticFrameSync × 4 profiles (until locked)
          ├─ marker hunt (64-sample steps, two-half score ≥ 8, leading edge)
          ├─ fine alignment (±min(symbol/8, 512) samples)
          ├─ Goertzel demod → bytes + per-byte reliability
          └─ RS decode → GMD erasure retries → CRC-16 → blockLen check
               └─► LtDecoder(session) → complete → APCM envelope (de-dup by CRC-32)
```

| Property | Value |
|---|---|
| Topology | One-to-many broadcast; no return path |
| Range | Across a table (≈0.3–2 m, room-dependent) |
| Band | ≈1.2–7.2 kHz (audible) |
| Net rates | Rugged 10.8, Safe 18.1, Standard 27.0, Fast 35.8 B/s |
| Maximum message (fountain path) | 8 192 B (`acousticFountainMaxBytes`) |
| Practical size | ≤ 2 KB |

---

## 2. Source files

| Area | File |
|---|---|
| MT-FSK modulator/demodulator | `lib/core/physical/acoustic/mt_fsk_codec.dart` |
| Streaming frame sync | `lib/core/physical/acoustic/acoustic_frame_sync.dart` |
| Frame codec (header, CRC-16, RS, GMD) | `lib/core/physical/acoustic/acoustic_fountain_frame.dart` |
| Reed-Solomon GF(256) | `lib/core/physical/acoustic/reed_solomon.dart` |
| Profiles | `lib/core/physical/acoustic/acoustic_tx_profile.dart` |
| Modem (TX bursts, RX auto-detect, progress) | `lib/core/physical/acoustic/acoustic_fountain_modem.dart` |
| Hardware channel (mic, audio session, playback) | `lib/core/channels/hardware_channels.dart` |
| Limits | `lib/core/physical/hardware_phy_config.dart` |
| UI state and HUD | `lib/core/platform/acoustic_receiver_state.dart`, `acoustic_transmitter_state.dart`, `lib/ui/widgets/acoustic_transfer_hud.dart` |
| WAV writer, PCM helpers | `lib/core/physical/physical_codecs.dart` (`pcmToWav`), `pcm16ToFloat32` |

---

## 3. Waveform: tones, bins and the band plan

### 3.1 Constants (`MtFskCodec` defaults)

| Constant | Value | Meaning |
|---|---|---|
| `sampleRate` | 44 100 Hz | Audio sample rate |
| `frameSamples` (N) | 1 024 | Analysis frame (23.22 ms) |
| Bin spacing | f_s / N = **43.066 Hz** | One tone step |
| `baseBin` | 40 | Lowest data tone (1 722.7 Hz) |
| Tones per group | 16 | 4 bits per group |
| `groups` (G) | 6 or 8 (must be even) | Simultaneous data tones |
| `framesPerSymbol` (F) | 3–6 | Symbol length = F × 1 024 samples |
| `markerFrames` | 2 | Sync burst length (2 048 samples = 46.4 ms) |
| Sync bins | `baseBin − 12` = **28** (1 205.9 Hz), `baseBin − 4` = **36** (1 550.4 Hz) | |

### 3.2 Tone mapping

```
bin(g, v)       = 40 + 16·g + v          (group g = 0…G−1, value v = 0…15)
frequency(g, v) = bin × 44 100 / 1 024
```

| Group | Bins | Frequency range |
|---|---|---|
| 0 | 40–55 | 1 722.7 – 2 368.7 Hz |
| 1 | 56–71 | 2 411.7 – 3 057.7 Hz |
| 2 | 72–87 | 3 100.8 – 3 746.8 Hz |
| 3 | 88–103 | 3 789.8 – 4 435.8 Hz |
| 4 | 104–119 | 4 478.9 – 5 124.9 Hz |
| 5 | 120–135 | 5 168.0 – 5 814.0 Hz |
| 6 (G = 8 only) | 136–151 | 5 857.0 – 6 503.0 Hz |
| 7 (G = 8 only) | 152–167 | 6 546.1 – 7 192.1 Hz |

### 3.3 Why exact bins

A tone at bin *k* completes exactly *k* cycles in every 1 024-sample frame. So:

- **Orthogonality.** Over any whole number of frames, the inner product of two different bin tones is zero, and one tone contributes no energy to another tone's detector. (Proof in [Signal Processing](../algorithms/SIGNAL_PROCESSING.md#2-tone-orthogonality).)
- **Phase continuity.** Each symbol restarts the phase at n = 0, and because every tone ends a frame at phase 2πk ≡ 0, consecutive symbols join without a jump. No clicks, so no energy splattered across the band.

### 3.4 Amplitude and clipping

Each tone gets amplitude `0.98 / (number of tones sounding)`:

| Moment | Tones | Amplitude each | Worst-case peak |
|---|---|---|---|
| Sync marker | 2 | 0.49 | 0.98 |
| Data, G = 6 | 6 | 0.1633 | 0.98 |
| Data, G = 8 | 8 | 0.1225 | 0.98 |

Even if every tone peaks at once, the sum stays below full scale (1.0), so PCM16 conversion never clips.

### 3.5 Nibble order

Group *g* of symbol *s* carries nibble index `s·G + g`. Even indices are the high nibble of byte `index / 2`, odd indices the low nibble. Each byte therefore occupies two adjacent groups, and one symbol carries G/2 bytes (3 or 4). A frame shorter than a whole number of symbols is padded with zero nibbles.

---

## 4. Demodulation with soft decisions

For every candidate tone the demodulator runs the **Goertzel algorithm** over one whole symbol (F × 1 024 samples):

```
coeff  = 2·cos(2π·bin / N)
s[n]   = x[n] + coeff·s[n−1] − s[n−2]
power  = (s1² + s2² − coeff·s1·s2) / length          (s1 = s[last], s2 = s[last−1])
```

With 16 tones × G groups that's 96 or 128 Goertzel runs per symbol. That's cheaper than an FFT when only 96–128 of the 512 bins matter.

**Per group:**
- *Hard decision:* the value v with the largest power, giving 4 bits.
- *Margin:* `1 − second / best` (0 = a tie, 1 = a single clean tone).
- *Confidence:* `best / total` over the group's 16 tones.

**Per byte:** `reliability = min(margin(high nibble), margin(low nibble))`. This ranks bytes for erasure decoding.

**Per frame:** the mean confidence over groups and symbols (`lastConfidence`, used for diagnostics).

---

## 5. Frame synchronisation

Microphone chunks arrive at arbitrary offsets, so every frame starts with its own **marker** and alignment is re-acquired from scratch for each frame.

### 5.1 Marker score (`MtFskCodec.markerScore`)

Split the 2 048-sample window at `start` into two halves of 1 024 samples. For each half:

```
E      = mean square energy of the half
P28    = Goertzel power at bin 28 over the half
P36    = Goertzel power at bin 36 over the half
score  = 2 · min(P28, P36) / E
```

The marker score is the **minimum over the two halves** (0 if E ≤ 1e-12).

**Ideal value.** For an aligned marker with two tones of amplitude A over N = 1 024 samples:

```
Goertzel power of one tone  P = (A·N/2)² / N = A²·N/4
Energy of two tones         E = A²/2 + A²/2 = A²
score = 2 · (A²·N/4) / A² = N/2 = 512
```

Unrelated audio (speech, music, noise) scores in the tens, so the lock threshold **8.0** sits well clear of both.

**Why two halves.** With a single full-window score normalised by its own energy, a window containing only the *back half* of the marker plus silence is still pure tone relative to its energy and scores just as high. That locked every frame one frame early. Requiring *both* halves to be tone means only the true onset fills the window.

**Why score on the weaker tone.** Both tones must be present. The sync tones are deliberately low (1.2 and 1.55 kHz), because speaker roll-off starves the top of the band exactly when conditions are worst.

### 5.2 Finding the frame (`AcousticFrameSync._process`)

1. **Hunt:** from the cursor, probe `markerScore` every **64 samples** (1.45 ms, under 2% of a symbol) until it reaches 8.0.
2. **Leading edge:** over the next 2 048 samples, find the peak score, then return the **first** probe scoring at least **50% of that peak**. Reflections can be louder than the direct sound, but the direct path always arrives first. Locking onto a later peak would put every symbol window more than a thousand samples late.
3. **Wait for the whole frame:** `coarseStart = marker + 2 048`; the frame needs `dataSymbols × symbolSamples + refineSpan` more samples. If they haven't arrived, resume from this marker next time.
4. **Refine:** `refineSpan = min(symbolSamples / 8, 512)`. Try offsets −span…+span in 64-sample steps and keep the one maximising `symbolConfidence` over the first 3 groups. A wider search could peak on the wrong symbol boundary.
5. **Demodulate** `codewordLength` bytes with soft reliability.
6. **Decode** (RS → GMD → CRC-16 → blockLen check). Count `framesRepaired` or `framesRejected`.
7. **Advance** the cursor to `marker + frameSamples` and compact the buffer. Each sample region is probed once, so CPU cost scales with the audio arriving rather than with the buffer length.

---

## 6. Frame format and error correction

### 6.1 Codeword

```
┌──────── 9 B header ────────┬──── L B payload ────┬ 2 B CRC-16 ┬──── P B RS parity ────┐
│ sym(2) K(2) L(1) len(3) sid(1) │ LT symbol          │ CCITT-FALSE │ GF(256), poly 0x11D   │
└────────────────────────────┴─────────────────────┴────────────┴────────────────────────┘
                        n = 11 + L + P  ≤ 255
```

A real example with hex dump is in [Data Formats §4](../architecture/DATA_FORMATS.md#4-acoustic-fountain-frame).

### 6.2 Decoding order

```
plain = RS.decode(word)                        → parse (CRC-16, blockLen, K ≥ 1)
if failed and reliability available:
   order bytes by reliability (least sure first)
   for erased in 4, 8, 12, … ≤ P − 4:
       RS.decode(word, erasures = first `erased` bytes)  → parse
return first success, else reject
```

- `gmdStep = 4`, `gmdReserve = 4`: at least 4 parity bytes are never spent on erasures, so every retry can still detect that a word is beyond repair.
- The CRC-16 then vets whatever RS accepts. RS can occasionally "correct" badly damaged input into a *different* valid codeword.
- The `blockLen` byte must equal the profile's L. This is what makes profile auto-detection trustworthy.

### 6.3 Capability per profile

| Profile | n | k (data) | P | Errors only (P/2) | Erasures only | GMD erasure steps |
|---|---|---|---|---|---|---|
| Rugged | 63 | 43 | 20 | 10 | 20 | 4, 8, 12, 16 |
| Safe | 83 | 59 | 24 | 12 | 24 | 4, 8, 12, 16, 20 |
| Standard | 99 | 75 | 24 | 12 | 24 | 4, 8, 12, 16, 20 |
| Fast | 99 | 75 | 24 | 12 | 24 | 4, 8, 12, 16, 20 |

With e unknown errors and f erasures, decoding succeeds when **2e + f ≤ P**. Measured on a real Standard codeword: 12 random errors are repaired, and 13 are rejected without hints but **repaired with GMD** when the demodulator marks them unreliable.

Mathematics: [Reed-Solomon](../algorithms/REED_SOLOMON.md).

---

## 7. Profiles

### 7.1 Definitions (`AcousticTxProfile`)

| | Rugged | Safe | Standard | Fast |
|---|---|---|---|---|
| `id` | `rugged` | `safe` | `standard` | `fast` |
| Groups G | 6 | 6 | 8 | 8 |
| Frames per symbol F | 6 | 4 | 4 | 3 |
| Symbol length | 6 144 samples = 139.3 ms | 4 096 = 92.9 ms | 4 096 = 92.9 ms | 3 072 = 69.7 ms |
| Bytes per symbol | 3 | 3 | 4 | 4 |
| Raw bit rate | 172 b/s | 258 b/s | 345 b/s | 459 b/s |
| Block L | 32 | 48 | 64 | 64 |
| Parity P | 20 | 24 | 24 | 24 |
| Codeword 11 + L + P | 63 | 83 | 99 | 99 |
| Data symbols | 21 | 28 | 25 | 25 |
| Frame samples | 2 048 + 21 × 6 144 = 131 072 | 2 048 + 28 × 4 096 = 116 736 | 2 048 + 25 × 4 096 = 104 448 | 2 048 + 25 × 3 072 = 78 848 |
| **Frame time** | **2.972 s** | **2.647 s** | **2.368 s** | **1.788 s** |
| **Net rate** L / frame time | **10.8 B/s** | **18.1 B/s** | **27.0 B/s** | **35.8 B/s** |
| Hint (`conditionHint`) | Loud room, phones metres apart | Background noise or chatter | Normal room, across a table | Quiet room, phones touching |

### 7.2 Formulas

```
R_raw  = 4·G·f_s / (N·F)                  raw bits per second
C      = 11 + L + P                       codeword bytes
S_d    = ceil(C / (G/2))                  data symbols per frame
T_f    = (2·N + S_d·N·F) / f_s            seconds per frame
R_net  = L / T_f                          payload bytes per second
```

Worked out for Standard: R_raw = 4·8·44 100 / 4 096 = 344.5 b/s; C = 99; S_d = 25; T_f = 104 448 / 44 100 = 2.3684 s; R_net = 64 / 2.3684 = **27.02 B/s**. The efficiency R_net·8 / R_raw = 62.8%. The rest goes to the marker (2%), the header and CRC (11%) and parity (24%).

### 7.3 Why Rugged is robust

- **Longer symbols** (139 ms) give each decision more energy and let reverberation (tails of 100–200 ms in rooms) decay inside the window.
- **Only 6 groups**, so no tones above 5.8 kHz, where small speakers roll off hardest.
- **More parity relative to data** (P/L = 0.63 against 0.375).
- **Fewer tones share the amplitude**, so each tone is 0.163 instead of 0.1225 (+2.5 dB per tone).

`slower` walks the ladder Fast → Standard → Safe → Rugged.

---

## 8. Automatic profile detection

`AcousticFountainModem` with `autoDetectProfile = true` (the default):

1. **Hunting:** one `AcousticFrameSync` per profile (4 in parallel) receives every audio chunk.
2. **Lock:** the first profile to produce a frame that isn't from an already-finished session becomes `_rxLocked`. The other syncs are dropped.
3. **Stale lock:** if the locked sync finds `staleLockMarkers = 4` markers after the last good frame without a new good frame, the receiver returns to hunting on all profiles. The locked sync is kept, so a half-heard frame isn't lost.
4. **After each message** (no decoders left), the receiver goes back to hunting, because the next sender may use a different speed.
5. **Damage counter:** `framesRejected` counts only while locked, because during hunting every wrong profile "rejects" every frame.

With `autoDetectProfile = false` the receiver listens only to the selected profile and restarts when it changes.

---

## 9. Transmitter

`AcousticFountainModem.transmit(envelope, play, shouldContinue, onProgress, maxSymbols)`:

| Step | Detail |
|---|---|
| Session | `(millisecondsSinceEpoch ~/ 97) & 0xFF` (8-bit) |
| Encoder | `LtEncoder(blockLen: profile.blockLen)` → K |
| Progress target | `expectedSymbols(K) = ⌈1.25·K⌉ + 2` |
| Safety budget | `symbolBudget(K) = max(6·K, K + 24)` |
| Burst size | `max(2, min(4, K))` frames per WAV |
| Burst audio | 120 ms of silence (5 292 samples), then the frames back to back |
| Output | Mono PCM16 44.1 kHz WAV via `pcmToWav`, played by `audioplayers` |
| Loop | While active and `index < budget` and `shouldContinue()`: render burst → `await play(wav)` → index += count → `onProgress(index, needed)` |
| Stop | `cancelTransmit()` stops after the current burst |

**Hardware channel extras (`HardwareAcousticChannel`):**
- The microphone is stopped before playing, because voice-mode recording would duck the playback.
- The audio session is configured for speakerphone output (Android: speakerphone on, stay awake, voice-communication usage; iOS: play-and-record with the loudspeaker as default output).

**Estimate shown to the user:** `estimateSeconds(bytes) = expectedSymbols(⌈bytes / L⌉) × frameSeconds()`.

---

## 10. Receiver

| Stage | Detail |
|---|---|
| Capture | `record` streams PCM16 mono at 44.1 kHz from the voice-communication source |
| Conversion | `pcm16ToFloat32`: little-endian int16 / 32 768 into a `Float32List` (no per-chunk `List<double>` allocation) |
| Sync | `addSamples` fans each chunk out to the active frame-syncs |
| Fountain | One `LtDecoder` per 8-bit session; `_done` holds finished sessions so the sender's tail is ignored |
| Delivery | On completion the bytes are de-duplicated by CRC-32 against the last delivered envelope, then queued for `takeEnvelopes()` |
| Progress | `AcousticRxProgress(collected, needed, framesRepaired, framesRejected, complete)`. `collected` is the number of **solved blocks** of the leading session, `needed` its K |

**UI meters (`acousticReceiverState`):**
- *Input level* = clamp(RMS × 12, 0, 1).
- *Tone signal* rises during a transfer.
- *Phases:* listening → tones detected (tone > 0.12) → decoding → decoded.
- The card shows "*x* of *K* blocks · *n* frames read · *m* too damaged".

---

## 11. Room simulator and results

`test/acoustic_channel_sim.dart` passes transmitted audio through:

1. **Clock drift:** linear resampling by (1 + ppm·10⁻⁶).
2. **Multipath:** extra delayed, attenuated copies.
3. **Reverb tail:** 6 echoes spaced 35 ms apart, scaled by the reverb factor.
4. **Speaker roll-off:** cascaded one-pole low-pass stages, each about −3 dB at 3.1 kHz.
5. **Noise:** Gaussian at the target SNR.

| Scenario | SNR | Reverb | Roll-off stages | Clock drift | Multipath taps |
|---|---|---|---|---|---|
| easy | 20 dB | 0.15 | 0 | 0 ppm | 0 |
| room | 12 dB | 0.35 | 2 | 50 ppm | 3 |
| noisy room | 6 dB | 0.45 | 4 | 200 ppm | 5 |
| hostile | 2 dB | 0.55 | 6 (≈ −47 dB at 7.2 kHz) | 400 ppm | 7 |

Verified by the test suite:
- Every profile delivers a 415-byte file through **room**.
- Safe delivers a text through **noisy room**.
- **Rugged delivers "sos" through hostile** (41.6 s of audio, 14 frames).
- A 1.2 KB file (K = 25) completes through noisy room in close to the minimum number of frames.
- One receiver auto-detects Rugged, Standard and Safe senders in turn.

---

## 12. Timing tables

Expected frames = `⌈1.25·K⌉ + 2`; time = frames × frame time.

| Content | Envelope | Rugged (L = 32) | Safe (L = 48) | Standard (L = 64) | Fast (L = 64) |
|---|---|---|---|---|---|
| "sos" | 31 B | K=1 → 4 fr → 11.9 s | K=1 → 4 fr → 10.6 s | K=1 → 4 fr → 9.5 s | K=1 → 4 fr → 7.2 s |
| "Hello from sound!" | 45 B | K=2 → 5 fr → 14.9 s | K=1 → 4 fr → 10.6 s | K=1 → 4 fr → 9.5 s | K=1 → 4 fr → 7.2 s |
| 100-char text | ≈128 B | K=4 → 7 fr → 20.8 s | K=3 → 6 fr → 15.9 s | K=2 → 5 fr → 11.8 s | K=2 → 5 fr → 8.9 s |
| 500 B | 500 B | K=16 → 22 fr → 65 s | K=11 → 16 fr → 42 s | K=8 → 12 fr → 28 s | K=8 → 12 fr → 21 s |
| 2 KB photo | ≈2.1 KB | K=66 → 85 fr → 4.2 min | K=44 → 57 fr → 2.5 min | K=33 → 44 fr → 1.7 min | K=33 → 44 fr → 1.3 min |

In a quiet room, receivers often finish nearer K + 1 or K + 2 frames than the 1.25·K target.

---

## 13. Tuning guide and failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Tone meter doesn't move | Mic permission, wrong screen, sender volume low | **Enable microphone**; volume to max; speaker facing the mic |
| Tones detected, blocks don't climb, "too damaged" rises | SNR too low, heavy echo | Move closer (20–50 cm), or use **Rugged**; the receiver follows automatically |
| Works close, fails at 2 m | High-band roll-off, reverberation | Safe or Rugged (6 groups, longer symbols) |
| Stops one block short | Sender reached Stop too early | Play again. A new session starts, so keep the sender playing until DONE |
| Two senders at once | Overlapping frames | Per-session decoders keep them apart; expect more damage |
| Message over 8 KiB | Falls back to the legacy packet path | Keep sound messages small; see [Known Issues](../project/KNOWN_ISSUES.md) |

**Design reasoning** is summarised in [Design Decisions](../architecture/DESIGN_DECISIONS.md) (ADR-10 to ADR-13). **DSP details** are in [Signal Processing](../algorithms/SIGNAL_PROCESSING.md).
