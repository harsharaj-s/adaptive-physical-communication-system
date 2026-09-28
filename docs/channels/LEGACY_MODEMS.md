# Legacy Modems

Earlier modems that were superseded by the fountain QR and MT-FSK modems. Following the project rule *extend, don't overwrite*, they remain in the codebase with their tests. They are reusable building blocks and a record of how the design evolved. None of them can be selected from the current Send/Receive UI.

Back to the [documentation index](../README.md).

---

## Contents

- [Summary](#summary)
1. [APCS1 text QR](#1-apcs1-text-qr-libcorephysicalqr_optical_codecdart)
2. [CSK: colour-shift keying](#2-csk-colour-shift-keying-libcorephysicalcskcsk_optical_modemdart-optical_csk_codecdart-optical_csk_samplerdart)
3. [On/off light keying](#3-onoff-light-keying-opticalbitcodec-in-physical_codecsdart)
4. [Two-tone FSK](#4-two-tone-fsk-fskcodec-fskstreamdecoder-goertzeldetector-in-physical_codecsdart)
5. [Evolution timeline](#5-evolution-timeline)

---

## Summary

| Modem | Medium | Rate | Status | Replaced by |
|---|---|---|---|---|
| APCS1 text QR | Screen → camera | ≈1.4 KB per 220 ms frame (base64) | Kept, tested | Fountain QR (APCF v3) |
| CSK (colour-shift keying) | Screen colour → camera | ≈6 B/s, ≤ 180 B | Kept | Fountain QR |
| On/off light keying | Screen brightness → camera | 10 bit/s | Test-only | Fountain QR |
| Two-tone FSK | Speaker → microphone | 55.6 b/s ≈ 7 B/s | Used for Sound messages > 8 KiB via the protocol path | MT-FSK fountain |

---

## 1. APCS1 text QR (`lib/core/physical/qr_optical_codec.dart`)

**Format.** Each QR contains a text string:

```
APCS1:<id>:<i>/<n>:<base64url chunk>
```

- `id`: message identifier; `i` / `n`: chunk index and count.
- Chunks of ≤ 1 400 bytes, base64url-encoded (+33%).
- Shown sequentially at 220 ms per frame, then repeated as a carousel.

**Why it was replaced.**
1. **Carousel problem:** a receiver missing chunk *i* waits a full cycle to see it again. The expected collection time grows like a coupon-collector problem.
2. **Density:** 1 400 B + base64 needs QR version 30 or more, which a hand-held camera almost never reads (see [Light Channel §6](LIGHT_CHANNEL.md#6-why-sparse-codes-win-optics)).
3. **Base64 overhead:** 33% capacity lost.

Test: `test/qr_optical_codec_test.dart`. `test/image_envelope_test.dart` also round-trips an image through it.

---

## 2. CSK: colour-shift keying (`lib/core/physical/csk/csk_optical_modem.dart`, `optical_csk_codec.dart`, `optical_csk_sampler.dart`)

**Idea.** Inspired by IEEE 802.15.7 colour-shift keying, the screen shows a **2×2 mosaic** of coloured cells. Each cell is one of four colours, and each colour encodes 2 bits (a "dibit"):

| Colour (`CskSymbol`) | ARGB | Dibit |
|---|---|---|
| Red | `FFFF1414` | `00` |
| Green | `FF14DC28` | `01` |
| Blue | `FF1E50FF` | `10` |
| White | `FFFFFFFF` | `11` |

The four cells carry bits 7–6, 5–4, 3–2 and 1–0 of a byte, so each displayed frame is **1 byte**. Example: `0x4B` = `01 00 10 11` → green, red, blue, white.

**Framing:** preamble `00 55 AA FF`, then a 2-byte **little-endian** length, then the envelope. Timing constants: 250 ms lead, 140 ms colour hold per byte, a 20 ms black guard between bytes, and the whole burst repeated 3 times with 400 ms gaps. Maximum envelope: 180 B (`hardwareOpticalCskMaxBytes`).

**Receiver:** `optical_csk_sampler.dart` samples the four quadrant centres of the camera frame and classifies each by its dominant channel.

**Rate:** 1 byte / 160 ms ≈ **6 B/s**, with messages ≤ 180 B.

**Why it was replaced:** colour classification is fragile under white balance, screen gamut and ambient light, and 1 byte per frame is 160× less than a v8 QR frame carries.

UI remnant: `lib/ui/widgets/optical_csk_overlay.dart`.

---

## 3. On/off light keying (`OpticalBitCodec` in `physical_codecs.dart`)

- Bright frame = 1, dark = 0; luminance > 0.5 decides.
- Preamble `1 0 1 0 1 0 1 1`; 100 ms per bit (the hardware constant `hardwareOpticalBitMs = 35` exists for faster experiments).
- **10 bit/s** at 100 ms. Used only in tests as the simplest possible optical link.

---

## 4. Two-tone FSK (`FskCodec`, `FskStreamDecoder`, `GoertzelDetector` in `physical_codecs.dart`)

| Parameter | Value |
|---|---|
| Bit 0 frequency | 1 800 Hz |
| Bit 1 frequency | 3 200 Hz |
| Symbol duration | 80 ms codec default; **18 ms** on hardware (`hardwareAcousticSymbolMs`) |
| Preamble | `1 0 1 0 1 0 1 0` |
| Detection | Goertzel power at each frequency per symbol |
| Lead silence | 180 ms (`hardwareAcousticLeadSilenceMs`), letting the mic AGC settle |
| Repeats | 3 (`hardwareAcousticTxRepeatCount`) with 350 ms gaps |
| Direct-send limit | 900 B (`hardwareAcousticDirectMaxBytes`) |
| Rate at 18 ms | 1 / 0.018 = 55.6 b/s ≈ 7 B/s |

**Stream decoder.** `FskStreamDecoder` keeps a rolling sample buffer, demodulates symbols at fixed offsets, looks for the preamble, reads the packet header to learn the length (rejecting lengths over 8 192), and advances one symbol past a failed preamble.

**Why it was replaced.**
- 1 bit per symbol against MT-FSK's 24–32 bits per symbol.
- No error correction: one wrong bit fails the whole packet CRC.
- **Fixed-offset symbol timing:** the decoder assumed symbol boundaries at exact multiples from the buffer start. Microphone chunks arrive at arbitrary offsets, so analysis windows straddled two tones.

**Where it still runs.** Sound messages larger than `acousticFountainMaxBytes` (8 192 B) go through the protocol path, whose acoustic channel falls back to this modem. A receiver in fountain mode doesn't decode it, which is a known issue.

Tests: `test/physical_codecs_test.dart`.

---

## 5. Evolution timeline

```
v1  APCS1 text QR carousel (base64, 1 400 B chunks, 220 ms)      two-tone FSK (18 ms/bit)
     │                                                               │
v1.5 CSK colour mosaic (1 B/frame) ── abandoned: colour fragility     │
     │                                                               │
v2  Fountain QR APCF v2: raw byte mode, robust-soliton LT, 800 B     │
     │  field bug: "stuck at 1/3 symbols", DEC 2/s                   │
v3  APCF v3: cycled/dense/sparse LT + exact GF(2) decoder;           │
     Auto density 160/240/330 B; 12 fps; camera tuning               │
                                                                     ▼
                                               MT-FSK + Reed-Solomon + LT fountain,
                                               6 profiles (4 audible, 2 Silent), auto-detect
```

See [Changelog](../project/CHANGELOG.md) and [Design Decisions](../architecture/DESIGN_DECISIONS.md).
