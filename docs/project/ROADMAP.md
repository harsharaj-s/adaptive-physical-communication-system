# Roadmap

Planned and possible future work, ordered by value to users. The near-term items fix the [Known Issues](KNOWN_ISSUES.md). The later items extend what the channels can do. None of these are promises, and each is small enough to be done independently.

Back to the [documentation index](../README.md).

---

## Contents

1. [Near term: correctness](#1-near-term-correctness)
2. [Mid term: speed and usability](#2-mid-term-speed-and-usability)
3. [Long term: new capabilities](#3-long-term-new-capabilities)
4. [Research ideas](#4-research-ideas)
5. [Not planned](#5-not-planned)

---

## 1. Near term: correctness

| Item | Fixes | Effort | Notes |
|---|---|---|---|
| Per-sequence ACK bitmap in `ReliableTransport` | Known Issue 3.1, 3.2 | Small | Advance `lastAcked` only over a contiguous run; keep NACK/retransmission requests |
| Block Sound envelopes > 8 KiB in the compose/transmit UI | 2.2 | Small | Show "Too large for Sound: use Light" with the estimated time |
| Skip re-encoding JPEGs that already fit | 4.1 | Small | Check the size and dimensions first; compress once, in one place |
| Send text *and* attachment | 4.2 | Small | Two envelopes, or a caption field in APCM |
| Clamp envelope names to 255 bytes | 4.4 | Trivial | In `ChatPayloadCodec.encode` |
| Airtime-aware ACK timeout for Vibration | 2.3 | Small | `ackTimeoutMs = max(20 s, 2 × expected airtime)` |
| Make Vibration work on real phones | 2.8 | Medium | After 2.3 and 3.1: log pulse lengths on real device pairs, calibrate the 130 ms decision boundary per phone, then measure success rates |
| Release signing and final `applicationId` | Build | Small | See [Build and Release](../operations/BUILD_AND_RELEASE.md) |

---

## 2. Mid term: speed and usability

| Item | Benefit | Notes |
|---|---|---|
| **Gzip for text and documents** | 2–3× faster for text-heavy payloads | The `qrFountainFlagGzip` flag already exists; add `package:archive` or `dart:io` zlib on mobile |
| **Decode-rate feedback into Auto density** | Faster on good cameras, safer on weak ones | The receiver already measures DEC; a sender-side "Faster/Slower" control could step the profile (the `slower()` hook exists) |
| **iOS brightness boost** | Better Light reliability from iPhones | `UIScreen.main.brightness` through the same `apcs/optical_display` method channel |
| **Sound profile auto-suggestion** | Fewer failed Sound transfers | Suggest Rugged/Safe/Standard/Fast from a 2-second noise measurement on the receiver |
| **Progress on the Light sender** | Less guesswork about when to stop | Show "about K + 2 frames × yield" as an ETA ring (the ETA formula already exists) |
| **Colour QR (3 layers)** | Up to 3× bytes per frame | Encode three QR codes in R, G, B; needs per-channel binarization and good white balance, so experimental |
| **Accessibility pass** | Screen-reader labels for HUD values | Semantics on HUD chips and the Send/Receive buttons |

---

## 3. Long term: new capabilities

| Item | Description |
|---|---|
| **Two-way Light + Sound** | Use Sound as a low-rate back-channel for Light: the receiver sends "done" or its rank so the sender stops automatically |
| **Silent-band capability check** | The Silent band shipped ([ADR-20](../architecture/DESIGN_DECISIONS.md#adr-20-a-silent-near-ultrasonic-band-for-sound)). Next: a one-tap test where each phone plays a 19 kHz tone and the other reports its *Silent band* level, so the app can suggest Audible before a transfer fails |
| **Authenticated encryption** | Optional passphrase: derive a key with Argon2id, encrypt the envelope with AES-GCM or ChaCha20-Poly1305. See [Security](../operations/SECURITY.md) |
| **Multi-file bundles** | Send several files in one fountain session with a small manifest |
| **Desktop builds** | Windows/macOS/Linux as Light senders on a big screen for classroom broadcast |
| **Adaptive switching in the live UI** | Let the engine move a Vibration/protocol transfer to Sound when both phones can hear each other |

---

## 4. Research ideas

- **Raptor/RaptorQ codes** instead of LT: overhead below 1 symbol even for large K, and linear-time decoding. Only worth it if files grow past ≈1 MB.
- **Camera-side super-resolution**: combine two consecutive captures of the same QR to recover codes that neither capture decodes alone.
- **OFDM for Sound**: more tones with a cyclic prefix against echo; potentially 2–3× Standard's rate in quiet rooms.
- **Rolling-shutter screen modulation**: flicker the screen above the flicker-fusion rate so the camera sees stripes a human can't. This is a known research technique but very device-dependent.

---

## 5. Not planned

| Idea | Why not |
|---|---|
| Any radio link (Wi-Fi, Bluetooth, NFC) as a data path | The project's premise is physical-only communication ([ADR-01](../architecture/DESIGN_DECISIONS.md)) |
| Cloud relay or accounts | Same reason; also removes the privacy advantage |
| Removing the legacy modems | They are kept deliberately as reusable libraries ([ADR-15](../architecture/DESIGN_DECISIONS.md)) |
