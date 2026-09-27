# Calculations Reference

Every formula the system uses, in one place, each with a worked example. The channel and algorithm documents explain *why* each formula looks the way it does; this page is the quick lookup.

Back to the [documentation index](../README.md).

---

## Contents

1. [Message envelope](#1-message-envelope)
2. [Light: blocks, QR version and timing](#2-light-blocks-qr-version-and-timing)
3. [Light: optics](#3-light-optics)
4. [Fountain code](#4-fountain-code)
5. [Sound: tones and rates](#5-sound-tones-and-rates)
6. [Sound: frame and transfer time](#6-sound-frame-and-transfer-time)
7. [Sound: error correction](#7-sound-error-correction)
8. [Sound: synchronisation](#8-sound-synchronisation)
9. [Vibration](#9-vibration)
10. [Protocol packets](#10-protocol-packets)
11. [Adaptive scoring](#11-adaptive-scoring)
12. [Checksums and identifiers](#12-checksums-and-identifiers)
13. [Media budgets](#13-media-budgets)
14. [Quick comparison](#14-quick-comparison)

---

## 1. Message envelope

```
envelope = "APCM"(4) + type(1) + nameLen(1) + name + mimeLen(1) + mime + data
overhead = 7 + len(name) + len(mime)
```

| Content | Name | MIME | Data | Envelope |
|---|---|---|---|---|
| Text "sos" | `message.txt` (11) | `text/plain` (10) | 3 | 7 + 11 + 10 + 3 = **31 B** |
| Text "Hello from sound!" | 11 | 10 | 17 | **45 B** |
| JPEG 5 100 B | e.g. `photo.jpg` (9) | `image/jpeg` (10) | 5 100 | **5 126 B** |

Details: [Data Formats §2](../architecture/DATA_FORMATS.md).

---

## 2. Light: blocks, QR version and timing

### 2.1 Block size (Auto)

```
blockLen = first b in [160, 240, 330] with ceil(envelope / b) ≤ 48, otherwise 330
K        = ceil(envelope / blockLen)
```

| Envelope | Test | blockLen | K |
|---|---|---|---|
| 5 130 B | ⌈5130/160⌉ = 33 ≤ 48 | 160 | 33 |
| 10 300 B | ⌈10300/160⌉ = 65 > 48; ⌈10300/240⌉ = 43 ≤ 48 | 240 | 43 |
| 80 055 B | 501, 334, 243: all > 48 | 330 | 243 |

The thresholds are 48 × 160 = **7 680 B** and 48 × 240 = **11 520 B**.

### 2.2 Frame size and QR version

```
frameBytes = 22 (header) + blockLen + 4 (CRC-32) = blockLen + 26
version    = smallest v whose EC-L byte capacity ≥ frameBytes
modules    = 4v + 17
```

| blockLen | frameBytes | Version | Capacity | Modules | Fill |
|---|---|---|---|---|---|
| 160 | 186 | 8 | 192 | 49 | 97% |
| 240 | 266 | 10 | 271 | 57 | 98% |
| 330 | 356 | 12 | 367 | 65 | 97% |
| 600 | 626 | 17 | 644 | 85 | 97% |

Framing efficiency = blockLen / frameBytes: 160/186 = **86%**, 330/356 = **93%**.

### 2.3 Transmit rate and safety cap

```
frame period  = 1000 / fps               12 fps → 83.3 ms ;  8 fps → 125 ms
nominal rate  = blockLen × fps           330 × 12 = 3 960 B/s
cap frames    = 600 s × fps              12 fps → 7 200 frames ;  8 fps → 4 800
```

### 2.4 ETA

```
yield = 0.70 (≤160) | 0.65 (≤240) | 0.55 (≤330) | 0.35 (larger)
ETA   = ceil( (K + 2) / (fps × yield) )
```

| Payload | K | fps × yield | ETA |
|---|---|---|---|
| 31 B | 1 | 8.4 | ⌈3/8.4⌉ = 1 s |
| 5 130 B | 33 | 8.4 | ⌈35/8.4⌉ = 5 s |
| 10 300 B | 43 | 7.8 | ⌈45/7.8⌉ = 6 s |
| 80 055 B | 243 | 6.6 | ⌈245/6.6⌉ = 38 s |
| 80 055 B, Safe | 501 | 5.6 | ⌈503/5.6⌉ = 90 s |

Full table: [Light Channel §10](../channels/LIGHT_CHANNEL.md#10-timing-and-throughput).

### 2.5 Goodput

```
goodput ≈ blockLen × fps × decodeRate × K / (K + overhead)
```

For v12 at 12 fps with a 55% decode rate and K = 243: 330 × 12 × 0.55 × 243/245 ≈ **2.16 KB/s**.

---

## 3. Light: optics

```
receiver crop     = 0.98 × 720 = 706 px
pixels per module = (QR share of crop) / (modules + 8 quiet-zone modules)
screen module     = floor(shortSide × dpr / (modules + 8))
```

| QR | Modules + 8 | px/module at 353 px | Screen px/module at 1 080 px |
|---|---|---|---|
| v8 | 57 | 6.2 | floor(1080/57) = 18 |
| v12 | 73 | 4.8 | floor(1080/73) = 14 |
| v17 | 93 | 3.8 | floor(1080/93) = 11 |
| v20 | 105 | 3.4 | floor(1080/105) = 10 |

Frame hold versus camera: 83 ms / 33 ms ≈ **2.5 captures per code** at 12 fps. Blur analysis (erf tables): [Signal Processing](SIGNAL_PROCESSING.md).

---

## 4. Fountain code

### 4.1 Degree of each repair symbol

```
K ≤ 8        : cycle through all 2^K − 1 non-empty subsets (shuffled)
9 ≤ K ≤ 256  : each source block included with p = ½  (mean degree K/2)
K > 256      : degree d = min(K/2, ceil(2 ln K) + 8)
```

Example, K = 422: ⌈2 ln 422⌉ + 8 = ⌈12.09⌉ + 8 = **21** blocks per repair symbol.

### 4.2 Decoding probability

```
Dense (p = ½), after K + m symbols: P(failure) ≤ 2^−m
    m = 2 → ≤ 25%   m = 5 → ≤ 3.1%   m = 10 → ≤ 0.1%
Small K: all 2^K − 1 subsets are cycled, so full rank arrives within one pass
Sparse:   P(a block is never covered by n symbols of degree d) ≈ e^(−n·d/K)
```

### 4.3 Fountain versus carousel under loss

With a carousel of K frames and loss rate q, you need every *specific* frame, so the expected number of passes grows with ln K. With a fountain you need *any* K + ε frames:

```
fountain frames ≈ (K + 2) / (1 − q)
```

For K = 13 at q = 30%: fountain ≈ 15 / 0.7 ≈ **21–22 frames**. A carousel needs ≈3.9 passes ≈ **49 frames**. Derivation: [Fountain Code](FOUNTAIN_CODE.md).

### 4.4 Decoder cost

```
memory ≈ K × (4·⌈K/32⌉ + blockLen) bytes      (32-bit coefficient words + payload per row)
```

For K = 422, blockLen = 330: 422 × (56 + 330) ≈ **163 KB**.

---

## 5. Sound: tones and rates

```
bin spacing  = fs / N = 44 100 / 1 024 = 43.066 Hz
tone(g, v)   = (40 + 16g + v) × 43.066 Hz        g = group, v = nibble 0–15
sync tones   = bin 28 (1 205.9 Hz) and bin 36 (1 550.4 Hz)
symbol       = F × 1 024 samples                  F = 3…6
bits/symbol  = 4 × G
raw rate     = 4G × fs / (F × 1 024)
amplitude    = 0.98 / tones                       peak never exceeds 0.98
```

| Profile | G | F | Symbol | Raw rate |
|---|---|---|---|---|
| Rugged | 6 | 6 | 139.3 ms | 24 bits / 0.1393 s = **172 b/s** |
| Safe | 6 | 4 | 92.9 ms | **258 b/s** |
| Standard | 8 | 4 | 92.9 ms | **345 b/s** |
| Fast | 8 | 3 | 69.7 ms | **459 b/s** |

Example: group 2, nibble 0xA → bin 40 + 32 + 10 = 82 → 82 × 43.066 = **3 531 Hz**.

---

## 6. Sound: frame and transfer time

### 6.1 Frame

```
codeword    = 11 (header 9 + CRC-16 2) + L + P
dataSymbols = ceil(codeword / (G/2))              G/2 bytes per symbol
frameSamples = 2 048 (marker) + dataSymbols × F × 1 024
frameTime   = frameSamples / 44 100
net rate    = L / frameTime
```

| Profile | L | P | Codeword | Symbols | Samples | Frame time | Net |
|---|---|---|---|---|---|---|---|
| Rugged | 32 | 20 | 63 | 21 | 131 072 | 2.972 s | 10.8 B/s |
| Safe | 48 | 24 | 83 | 28 | 116 736 | 2.647 s | 18.1 B/s |
| Standard | 64 | 24 | 99 | 25 | 104 448 | 2.368 s | 27.0 B/s |
| Fast | 64 | 24 | 99 | 25 | 78 848 | 1.788 s | 35.8 B/s |

### 6.2 Transfer

```
K               = ceil(envelope / L)
expectedSymbols = ceil(1.25 K) + 2           progress target
symbolBudget    = max(6K, K + 24)            sender stops after this many frames
burst           = max(2, min(4, K)) frames per WAV, after 120 ms of silence
time ≈ expectedSymbols × frameTime  (+ 0.12 s per burst)
```

| Envelope | Profile | K | Frames | Time |
|---|---|---|---|---|
| 31 B | Standard | 1 | ⌈1.25⌉ + 2 = 4 | 4 × 2.368 = **9.5 s** |
| 500 B | Rugged | 16 | 20 + 2 = 22 | 22 × 2.972 = **65 s** |
| 500 B | Fast | 8 | 10 + 2 = 12 | 12 × 1.788 = **21 s** |
| 2.1 KB | Standard | 33 | ⌈41.25⌉ + 2 = 44 | 44 × 2.368 = **1.7 min** |

Session ID: `(millisecondsSinceEpoch ~/ 97) & 0xFF`.

---

## 7. Sound: error correction

```
RS(n, k) over GF(256), primitive polynomial 0x11D, n = 11 + L + P, k = 11 + L
corrects e errors and f erasures when 2e + f ≤ P
GMD retries erase the 4, 8, 12, … least-confident bytes while keeping ≥ 4 parity spare
```

| Profile | P | Errors only | Erasures only | Example mix |
|---|---|---|---|---|
| Rugged | 20 | 10 | 20 | 6 errors + 8 erasures (12 + 8 = 20) |
| Standard | 24 | 12 | 24 | 9 errors + 4 erasures (18 + 4 = 22 ≤ 24) |

**Worked GMD case (P = 24).** 13 errors fail errors-only decoding (26 > 24). The first GMD retry erases the 4 weakest bytes. If those include 4 of the errors, 9 errors + 4 erasures remain: 2·9 + 4 = 22 ≤ 24, so the frame is repaired.

Field facts: α = 0x02, α⁸ = 0x1D (since x⁸ ≡ x⁴ + x³ + x² + 1). Full walkthrough: [Reed-Solomon](REED_SOLOMON.md).

---

## 8. Sound: synchronisation

```
marker score = min over both half-windows of  2 · min(P28, P36) / E
    ideal (pure marker)  = N/2 = 512
    noise                ≈ 1
    lock threshold       = 8
leading edge  = first sample where score ≥ 50% of the peak
refine span   = min(symbolSamples / 8, 512)
search step   = 64 samples
```

Processing gain of a Goertzel bin integrated over one symbol of L = F × 1 024 samples (a coherent tone gains L²/2 in power while white noise gains L):

```
gain = 10 log10(L / 2)
```

| Profile | L | Gain |
|---|---|---|
| Fast | 3 072 | 31.9 dB |
| Standard / Safe | 4 096 | 33.1 dB |
| Rugged | 6 144 | 34.9 dB |

Derivation: [Signal Processing](SIGNAL_PROCESSING.md).

---

## 9. Vibration

```
bit 0 period = 80 + 50 + 60  = 190 ms
bit 1 period = 180 + 50 + 60 = 290 ms
average      = 240 ms → 4.17 bit/s → 0.52 B/s
decision     = pulse ≥ 130 ms → 1
pulse detect = |‖a‖ − baseline| ≥ 1.4 m/s²;   baseline ← 0.92·b + 0.08·‖a‖
reject       = pulses < 25 ms
```

| Message | On-air bytes | Bits | Time |
|---|---|---|---|
| "hi" | 58 | 472 | ≈113 s |
| "hello" | 61 | 496 | ≈119 s |
| Full 48-byte payload | 76 | 616 | ≈148 s |

---

## 10. Protocol packets

```
packet     = 24-byte header + payload + CRC-32 (4)   (little-endian fields; 28 bytes overhead)
fragments  = ceil(data / packetSize)
window     = [lastAcked + 1, lastAcked + windowSize]
```

| Mode | packetSize | Window | ACK timeout | Retries | Worst wait per packet |
|---|---|---|---|---|---|
| Simulation | 256 | 8 | 500 ms | 5 | 6 × 0.5 = 3 s |
| Hardware, optical | 1 400 | 4 | 20 s | 8 | 9 × 20 = 180 s |
| Hardware, acoustic | 512 | 4 | 20 s | 8 | 180 s |
| Hardware, vibration | 48 | 4 | 20 s | 8 | 180 s |

Example: the raw payload "sos" as a single packet is 24 + 3 + 4 = **31 bytes** (see [Data Formats](../architecture/DATA_FORMATS.md)).

---

## 11. Adaptive scoring

```
T = min(throughput / 25 000, 1)    R = reliability    L = max(1 − latency/500, 0)
score = 0.35 T + 0.25 R + 0.15 L + 0.15 C + 0.10 S
degraded   : score < 0.65
switch     : degraded AND alternative − current ≥ 0.15
evaluate   : every 20 loop iterations, alternatives tested with 20 packets
```

Worked example (optical collapsing to 2 kbps, 30% loss, 500 ms):
0.35·0.08 + 0.25·0.70 + 0.15·0 + 0.15·0.30 + 0.10·0.20 = **0.268**, so the engine switches to acoustic at 0.70. See [Adaptive Engine §10](ADAPTIVE_ENGINE.md#10-worked-examples).

---

## 12. Checksums and identifiers

| Algorithm | Parameters | Check value ("123456789") | Used by |
|---|---|---|---|
| CRC-32 (IEEE) | poly 0xEDB88320 reflected, init/xorout 0xFFFFFFFF | **CBF43926** | Light frames, packets, de-duplication |
| CRC-16/CCITT-FALSE | poly 0x1021, init 0xFFFF, no reflection | **29B1** | Sound frames |

```
Light session ID = (CRC32(envelope) XOR (blockLen × 0x9E3779B1)) & 0xFFFFFFFF ;  0 → 1
Sound session ID = (ms ~/ 97) & 0xFF
```

The same content at the same density always gets the same Light session ID, which is what makes **Resume streaming** work.

---

## 13. Media budgets

### 13.1 Photo compression (`compressImageForTransfer`)

```
fit inside 960 × 960 → JPEG q78
while size > 120 KiB and q > 40: q −= 8          (78, 70, 62, 54, 46, 38)
still too big and > 640 px → resize to 640, q65
```

### 13.2 Sample video encoding (`tool/make_sample_media.py`)

```
budget      = target_kb × 1024 bytes
total kbps  = budget × 8 / 1000 / duration × 0.96        (4% container margin)
video kbps  = total − audio − 3   (MP4; −1 for WebM)
retry       : video kbps × budget / size × 0.97 until size ≤ budget
```

Example: 200 KB, 30 s, 12 kbps audio → 204 800 × 8 / 1000 / 30 × 0.96 = 52.4 kbps total → **37.4 kbps video**.

### 13.3 What that costs on each channel

| File | Light (Auto) | Sound (Standard) | Vibration |
|---|---|---|---|
| 5 KB photo (5 126 B envelope) | ⌈35/8.4⌉ ≈ **5 s** | K = 81 → 104 frames × 2.368 s ≈ **4.1 min** | 107 packets, ≈8.1 KB on air ≈ **4.3 h** (plus ACK waits) |
| 80 KB video | ≈38 s | Over the 8 KiB fountain limit | Not practical |

---

## 14. Quick comparison

| | Light | Sound | Vibration |
|---|---|---|---|
| Carrier | QR codes at 8–12 fps | 1.2–7.2 kHz tones | 80/180 ms buzzes |
| Net rate | ≈1.3–2.5 KB/s | 10.8–35.8 B/s | ≈0.5 B/s |
| Ratio to vibration | ≈2 500–4 800× | ≈20–70× | 1× |
| Integrity | CRC-32 + QR's RS | RS + CRC-16 + GMD | Packet CRC-32 |
| Loss recovery | LT fountain | LT fountain | ACK/NACK retransmit |
| Typical range | 15–40 cm | 0.3–2 m | Phones touching |
