# Sound Channel: Multi-Tone FSK + Reed-Solomon + Fountain

The Sound channel sends data from a phone's **speaker** to another phone's **microphone**. It uses three layers, each solving a different problem:

1. **Multi-tone FSK (MT-FSK)** turns bytes into chords of audible tones: 4 bits per tone, 6–8 tones at once.
2. **Reed-Solomon** repairs the bytes a single frame loses to echoes and noise, using soft-decision erasures.
3. The **LT fountain code**, the same one the Light channel uses, makes whole lost frames irrelevant, so no return path is needed.

The same stack runs in two **bands**. **Audible** (1.2–7.2 kHz) plays chords of 6–8 tones and is the fastest. **Silent** (18.3–19.9 kHz) plays one tone at a time, above most adults' hearing and above nearly all room noise. See [section 14](#14-silent-band-near-ultrasonic). A receiver listens for both bands at once.

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
14. [Silent band (near-ultrasonic)](#14-silent-band-near-ultrasonic)

---

## 1. Overview

```
TX  APCM envelope
     └─► LtEncoder(blockLen = L)             symbols 0,1,2,… (rateless)
          └─► AcousticFrameCodec              9 B header + L payload + CRC-16 → + P RS parity
               └─► MtFskCodec.encode          2-frame sync marker + ⌈(11+L+P)/(G/2)⌉ data symbols
                    └─► bursts of 2–4 frames + 120 ms lead silence → PCM16 WAV → speaker

RX  microphone PCM16 mono 44.1 kHz → float
     └─► AcousticFrameSync × 6 profiles (until locked; Silent ones high-pass at 16 kHz first)
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
| Band | Audible ≈1.2–7.2 kHz, or Silent 18.3–19.9 kHz |
| Net rates | Rugged 10.8, Safe 18.1, Standard 27.0, Fast 35.8 B/s; Silent Robust 3.4, Silent 5.0 B/s |
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
| Profiles and bands (`AcousticBand`) | `lib/core/physical/acoustic/acoustic_tx_profile.dart` |
| High-pass filter (Silent receive, high-band meter) | `lib/core/physical/acoustic/biquad_filter.dart` |
| Modem (TX bursts, RX auto-detect, progress) | `lib/core/physical/acoustic/acoustic_fountain_modem.dart` |
| Hardware channel (mic, audio session, playback) | `lib/core/channels/hardware_channels.dart` |
| Limits | `lib/core/physical/hardware_phy_config.dart` |
| UI state and HUD | `lib/core/platform/acoustic_receiver_state.dart`, `acoustic_transmitter_state.dart`, `lib/ui/widgets/acoustic_transfer_hud.dart` |
| Live frequency readout | `lib/core/physical/acoustic/tone_timeline.dart` (sender), `spectrum_analyzer.dart` (receiver), `lib/core/platform/acoustic_spectrum_state.dart`, `lib/ui/widgets/live_tone_meter.dart` |
| WAV writer, PCM helpers | `lib/core/physical/physical_codecs.dart` (`pcmToWav`), `pcm16ToFloat32` |

---

## 3. Waveform: tones, bins and the band plan

### 3.1 Constants (`MtFskCodec` defaults, used by the audible band)

The Silent band overrides `baseBin`, `toneSpacing`, the sync bins, the marker style and the peak level; see [section 14](#14-silent-band-near-ultrasonic).

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

`slower` walks the ladder Fast → Standard → Safe → Rugged. It never crosses bands: Silent's ladder is Silent → Silent Robust, because a phone that can't hear 19 kHz isn't helped by a slower 19 kHz.

### 7.4 Silent profiles

| | Silent Robust | Silent |
|---|---|---|
| `id` | `silent_robust` | `silent` |
| Band | 18.3–19.9 kHz | 18.3–19.9 kHz |
| Tones at once G | 1 | 1 |
| Frames per symbol F (guard) | 3 (1) | 2 (1) |
| Symbol length | 3 072 samples = 69.7 ms | 2 048 = 46.4 ms |
| Analysis window | last 2 048 samples | last 1 024 samples |
| Raw bit rate | 57.4 b/s | 86.1 b/s |
| Block L / parity P / codeword | 24 / 16 / 51 | 24 / 16 / 51 |
| Data symbols | 102 | 102 |
| **Frame time** | **7.152 s** | **4.783 s** |
| **Net rate** | **3.4 B/s** | **5.0 B/s** |
| Hint | Weak speaker or a loud crowd | Phones within arm's reach |

Details and measurements are in [section 14](#14-silent-band-near-ultrasonic).

---

## 8. Automatic profile detection

`AcousticFountainModem` with `autoDetectProfile = true` (the default):

1. **Hunting:** one `AcousticFrameSync` per profile (6 in parallel: four audible, two Silent) receives every audio chunk. The two bands use different sync tones, so a Silent sync never locks onto an audible frame or the other way round.
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
| Burst audio | 120 ms of silence (5 292 samples), the frames back to back, then 40 ms of silence. A 256-sample (5.8 ms) raised-cosine fade at each edge of the frames (`applyEdgeFades`) prevents a click. |
| Output | Mono PCM16 44.1 kHz WAV via `pcmToWav`, played by `audioplayers` |
| Loop | While active and `index < budget` and `shouldContinue()`: render burst → `await play(wav)` → index += count → `onProgress(index, needed)` |
| Stop | `AcousticFountainModem.cancelTransmit()` ends the loop after the current burst. `HardwareAcousticChannel.cancelTransmit()` also stops the player mid-burst, so **Stop**, **Cancel transmission** and back all silence the speaker at once. |

**Hardware channel extras (`HardwareAcousticChannel`):**
- The microphone is stopped before playing, so recording can't duck the playback.
- The audio session is chosen per band before each send:

| Band | Android | iOS |
|---|---|---|
| Audible | Speakerphone on, stay awake, speech content, voice-communication usage | Play-and-record, loudspeaker default, Bluetooth allowed |
| Silent | Plain media playback (normal mode, music content, media usage), stay awake | Play-and-record, loudspeaker default, no Bluetooth |

Silent can't use the voice-call path: it applies speech EQ and on many phones low-passes well below 18 kHz. Bluetooth hands-free audio also stops at 8 kHz.

**Estimate shown to the user:** `estimateSeconds(bytes) = expectedSymbols(⌈bytes / L⌉) × frameSeconds()`.

---

## 10. Receiver

| Stage | Detail |
|---|---|
| Capture | `record` streams PCM16 mono at 44.1 kHz from `AndroidAudioSource.voiceRecognition`. Android's CDD requires this source to run with noise suppression and AGC off and a flat response, and the near-ultrasound guarantee covers it. The voice-communication source used before has a noise suppressor that treats steady data tones as noise, and it often band-limits to 8 kHz. |
| Conversion | `pcm16ToFloat32`: little-endian int16 / 32 768 into a `Float32List` (no per-chunk `List<double>` allocation) |
| Sync | `addSamples` fans each chunk out to the active frame-syncs |
| Fountain | One `LtDecoder` per 8-bit session; `_done` holds finished sessions so the sender's tail is ignored |
| Delivery | On completion the bytes are de-duplicated by CRC-32 against the last delivered envelope, then queued for `takeEnvelopes()` |
| Progress | `AcousticRxProgress(collected, needed, framesRepaired, framesRejected, complete)`. `collected` is the number of **solved blocks** of the leading session, `needed` its K |

**UI meters (`acousticReceiverState`):**
- *Input level* = clamp(RMS × 12, 0, 1).
- *Tone signal* rises during a transfer. When idle it is the larger of the input level and the high-band level.
- *Silent band 18–20 kHz* = RMS above 16 kHz (4th-order high-pass), mapped from −70…−20 dBFS onto 0…1. Silent tones barely move the full-band input meter, so this is the only live sign they are arriving before the first frame decodes.
- *Phases:* listening → tones detected (tone > 0.12) → decoding → decoded.
- The card shows "*x* of *K* blocks · *n* frames read · *m* too damaged".

**Live frequency readout (`acousticSpectrumState`):**
- *Sending now* (sender). While the modem renders a burst, `MtFskCodec.describe` writes a `ToneTimeline` of the same segments `encode` writes: lead silence, sync marker, data symbols, tail. `_playWav` starts the clock when `play()` returns, and the widget looks up the segment at the elapsed time every 50 ms. The readout shows exactly what is on air, not a re-analysis of the speaker output.
- *Hearing now* (receiver). `SpectrumAnalyzer` keeps the last 1024 mic samples in a ring and runs a Hann-windowed FFT only when the 80 ms UI throttle fires. It reports 96 display bands over 0–22 kHz and up to 8 peaks between 500 Hz and 21 kHz. A peak must stand 18 dB above the median bin and above −85 dBFS. Peaks within 4 bins of a stronger one, or more than 35 dB below the strongest, are treated as window leakage. Parabolic interpolation places each peak to a few hertz.
- When the sound is getting through, both phones show the same kHz. Audible chords show up to 8 tones at once; Silent shows one tone between 18.3 and 19.9 kHz.

---

## 11. Room simulator and results

`test/acoustic_channel_sim.dart` passes transmitted audio through:

1. **Clock drift:** cubic resampling by (1 + ppm·10⁻⁶).
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

Clock drift and hand wobble are applied by Catmull-Rom (cubic) resampling. Linear interpolation is itself a low-pass that knocks about 6 dB off a 19 kHz tone, which would have made the Silent band look worse than it is.

Two optional effects model what the high band is really up against:

- **Chatter:** three simulated talkers, each a harmonic series on a gliding 100–250 Hz fundamental with energy up to 5 kHz, gated at a syllable rate. It is scaled to a signal-to-babble ratio.
- **Hand wobble:** a time-varying clock ratio at about 1 Hz, standing in for the Doppler of a moving hand.

A `micGain` below 1 gives loud chatter headroom so it doesn't clip, as a real microphone with AGC off wouldn't.

| Near-ultrasonic scenario | SNR | Chatter | Reverb | Clock drift | Wobble | Multipath taps |
|---|---|---|---|---|---|---|
| ultra desk | 10 dB | — | 0.2 | 80 ppm | — | 3 |
| ultra hand | 4 dB | — | 0.35 | 200 ppm | 500 ppm | 5 |
| chatter | 10 dB | voices +6 dB | 0.3 | 100 ppm | — | 3 |
| crowd | 10 dB | voices +15 dB | 0.3 | 100 ppm | — | 3 |

Verified by the test suite:
- Every audible profile delivers a 415-byte file through **room**: Rugged 41.6 s, Safe 26.5 s, Standard 18.9 s, Fast 14.3 s.
- Safe delivers a text through **noisy room**.
- **Rugged delivers "sos" through hostile** (10 B, one burst of 2 frames, 5.9 s).
- A 1.2 KB file (K = 25) completes through noisy room in close to the minimum number of frames.
- One receiver auto-detects Rugged, Silent, Standard and Safe senders in turn.
- **Silent delivers "Meet at gate 3"** (21 B, one frame) through every near-ultrasonic scenario, crowd included.
- **Silent Robust delivers a 59-byte text through crowd** (K = 3, 4 frames, 28.6 s).
- A Silent burst puts **−59.9 dB** of its energy below 16 kHz, fades included (Hann-windowed DFT with windows deliberately misaligned with the symbols).

---

## 12. Timing tables

Expected frames = `⌈1.25·K⌉ + 2`; time = frames × frame time. Text and links carry a 7-byte envelope overhead (no name or MIME type), so a text of *n* UTF-8 bytes is an *n* + 7 byte envelope.

| Content | Envelope | Rugged (L = 32) | Safe (L = 48) | Standard (L = 64) | Fast (L = 64) | Silent (L = 24) |
|---|---|---|---|---|---|---|
| "sos" | 10 B | K=1 → 4 fr → 11.9 s | K=1 → 4 fr → 10.6 s | K=1 → 4 fr → 9.5 s | K=1 → 4 fr → 7.2 s | K=1 → 4 fr → 19.1 s |
| "Hello from sound!" | 24 B | K=1 → 4 fr → 11.9 s | K=1 → 4 fr → 10.6 s | K=1 → 4 fr → 9.5 s | K=1 → 4 fr → 7.2 s | K=1 → 4 fr → 19.1 s |
| 100-char text | 107 B | K=4 → 7 fr → 20.8 s | K=3 → 6 fr → 15.9 s | K=2 → 5 fr → 11.8 s | K=2 → 5 fr → 8.9 s | K=5 → 9 fr → 43 s |
| 500 B | 500 B | K=16 → 22 fr → 65 s | K=11 → 16 fr → 42 s | K=8 → 12 fr → 28 s | K=8 → 12 fr → 21 s | K=21 → 29 fr → 2.3 min |
| 2 KB photo | ≈2.1 KB | K=66 → 85 fr → 4.2 min | K=44 → 57 fr → 2.5 min | K=33 → 44 fr → 1.7 min | K=33 → 44 fr → 1.3 min | K=88 → 112 fr → 8.9 min |

The expected column is deliberately pessimistic. The fountain code is systematic, so when every frame lands a receiver finishes after exactly K frames: "sos" takes one frame, which is 2.4 s on Standard and 4.8 s on Silent. In a quiet room, receivers often finish nearer K + 1 or K + 2 frames than the 1.25·K target. Silent Robust takes 1.5× Silent's times.

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
| Silent: *Silent band* meter stays near zero | Sender's speaker or receiver's mic can't reproduce 18–20 kHz, or media volume is low | Media volume to max; swap the phones' roles; otherwise use **Audible** |
| Silent: meter moves, no frames decode | Too far, or phones moving | 10–50 cm apart, hold still, or use **Silent Robust** |
| Silent: faint ticking at start and stop | Speaker distortion at maximum volume | Lower the volume one step; the fades already remove the waveform's own clicks |

**Design reasoning** is summarised in [Design Decisions](../architecture/DESIGN_DECISIONS.md) (ADR-10 to ADR-13). **DSP details** are in [Signal Processing](../algorithms/SIGNAL_PROCESSING.md).

---

## 14. Silent band (near-ultrasonic)

### 14.1 Why 18–20 kHz

- **People don't hear it.** Hearing above about 17 kHz fades through the teens and twenties, so most adults hear nothing. Children, some young adults and pets may still hear a faint whine.
- **Rooms are quiet up there.** Speech, music, fans and traffic put almost all their energy below 8 kHz, so the microphone hears the data tones against little more than its own noise floor.
- **Android specifies it.** The Compatibility Definition Document (CDD) defines near-ultrasound support around 18.5–20 kHz. When a device reports `PROPERTY_SUPPORT_MIC_NEAR_ULTRASOUND`, the voice-recognition and unprocessed sources must hold their response there within 15 dB of 2 kHz. The speaker property allows up to 40 dB down. Phones without it simply never hear these profiles, and the audible band still works.

The same frame format, Reed-Solomon code, CRC and fountain code carry over unchanged. Only the tone plan differs.

### 14.2 Band plan (`AcousticBand.nearUltrasonic`)

| Item | Bin(s) | Frequency |
|---|---|---|
| Sync tone A | 424 | 18 260 Hz |
| Sync tone B | 427 | 18 390 Hz |
| Data tones, 16 values, `toneSpacing = 2` | 431, 433, … 461 | 18 562 – 19 854 Hz, 86.1 Hz apart |

Every tone is still an exact bin of the 1 024-sample frame, so the tones stay orthogonal and phase-continuous. Tones sit two bins apart because a hand moving at 0.3 m/s shifts 19 kHz by about 17 Hz, most of one 43 Hz bin. The sync tones sit below the data band, with a two-bin gap below the lowest data tone, so data can never imitate a marker.

### 14.3 One tone at a time

Audible profiles play 6–8 tones at once. Near-ultrasound can't, because any non-linearity in a small speaker turns two tones f₁ and f₂ into a difference tone at f₁ − f₂. Two data tones 1 kHz apart at 19 kHz would produce an audible 1 kHz buzz. Silent profiles therefore use `groups = 1`: one 16-ary tone per symbol, 4 bits, and a byte spans two symbols. The codec's nibble packing handles an odd number of groups for exactly this reason. A single tone also gets the whole output level: 0.8 against 0.12 per tone for Standard, about 16 dB more per tone.

### 14.4 Sequential marker

The marker plays tone A for the first 1 024 samples, then tone B (`sequentialMarker`). The output stays a single sinusoid, and the ordering is itself a signature. `markerScore` scores each half on the tone expected in it:

```
score(half) = (tones in half) · min(Goertzel power of those tones) / mean-square energy
marker      = min(score(first half), score(second half))
```

An aligned marker scores 512 whether a half holds one tone or two, so the same threshold of 8.0 serves both bands.

### 14.5 Echo guard

Each Silent symbol begins with a **guard frame** that the demodulator ignores (`guardFrames = 1`). The decision uses only the later frames, after reflections of the previous tone have died away. Since tones are exact bins of one frame, any whole number of frames remains orthogonal. The guard was the single biggest improvement in the parameter sweep:

| 46 ms symbols (Silent), frames recovered | ultra desk | ultra hand | chatter |
|---|---|---|---|
| No guard | 13/18 | 2/18 | 5/18 |
| 23 ms guard | 18/18 | 16/18 | 11/18 |

23 ms symbols without a guard were too fragile to ship: 6/18, 0/18 and 1/18 in the same scenarios.

### 14.6 High-pass before sync

The marker score divides tone power by the whole window's energy, so loud voices at 0–5 kHz inflate the denominator and bury an 18 kHz marker they never overlap. `AcousticFrameSync` therefore runs Silent profiles' audio through a 4th-order Butterworth high-pass at 16 kHz first (`HighPassFilter`: two biquads, Q = 0.5412 and 1.3066). Speech harmonics at 5 kHz lose about 40 dB, while 18.3 kHz loses about 1.3 dB. The filter keeps its state across microphone chunks. In the crowd scenario it raised Silent's frame recovery from 4/18 to 15/18.

### 14.7 Output level and fades

- The peak level is 0.8, not 0.98. The headroom covers the platform's 44.1 → 48 kHz resampler. Clipping a 19 kHz tone creates harmonics that fold back into the audible band on a 48 kHz output.
- Each burst's edges get a 5.8 ms raised-cosine fade. A hard start or stop is a broadband click, audible even when the tone that caused it is not. Inside a burst the tones are phase-continuous, so no other point can click.

### 14.8 Measured frame recovery

Frames recovered out of 18 (3 seeds × 6 frames) per scenario, from the parameter sweep:

| Profile | Frame | ultra desk | ultra hand | chatter | crowd | room | noisy room |
|---|---|---|---|---|---|---|---|
| Silent | 4.78 s | 18 | 17 | 15 | 15 | 14 | 15 |
| Silent Robust | 7.15 s | 17 | 13 | 16 | 17 | 17 | 18 |
| Rugged (audible) | 2.97 s | 17 | 18 | 18 | 16 | 17 | 18 |
| Standard (audible) | 2.37 s | 16 | 12 | 16 | 1 | 12 | 1 |

Silent is about as robust as Rugged at half its speed, and it can't be heard. Standard collapses in a crowd; Silent doesn't. These are simulations: real phones vary most in how much 19 kHz their speaker and microphone pass, so test on the actual devices before a showcase.

### 14.9 Compared with a simple two-tone design

A common near-ultrasonic messenger design uses binary FSK: 19 kHz for 0, 20 kHz for 1, one bit per 40–60 ms, then an XOR checksum. A 3-character message at 60 ms per bit becomes 72 bits: marker 8, sync 16, length 8, payload 24, checksum 8, end marker 8. That is 4.32 s.

| | Two-tone FSK at 60 ms/bit | Silent |
|---|---|---|
| Bits per symbol | 1 | 4 (16 tones) |
| Raw rate | 16.7 b/s | 86.1 b/s |
| "SOS" | 4.3 s | 4.8 s (one frame) |
| 100-character text | 52 s, and must arrive in one clean pass | 24 s if every frame lands (K = 5), 43 s expected |
| One bit wrong | Checksum fails, the whole message is lost | Reed-Solomon repairs up to 8 bad bytes per frame |
| A frame lost | Start again | Any later frame replaces it (fountain) |
| Longest message | 255 B | 8 KiB |

For a three-letter message the simpler design is half a second quicker, because a Silent frame always carries a 24-byte block. From about five characters on, Silent is faster: a 17-character text still fits one 4.8 s frame, while two-tone FSK needs 11 s. Its lead grows with message length, because nothing has to be resent.

### 14.10 Limits

- Phones differ. Some speakers are 30–40 dB down at 19 kHz, and some microphone paths filter it out. The *Silent band* meter shows this within a second.
- Bluetooth hands-free audio and the voice-call output path can't carry it; the channel uses media playback for Silent for this reason.
- Web browsers resample and process microphone audio unpredictably; Silent is intended for the Android and iOS apps.
- Keep the phones 10–50 cm apart. High frequencies are more directional and fade faster with distance than the audible band does.
