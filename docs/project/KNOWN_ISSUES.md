# Known Issues

This page lists the limits of the current build and the problems found while writing these documents by reading the code and running it. Each entry gives the symptom, the cause with a file reference, the impact, and a workaround or fix. Nothing here blocks the main demo: Light and Sound fountain transfers of text, photos and short videos work as documented. The Vibration channel is the exception: it is experimental and doesn't work reliably yet ([§2.8](#28-vibration-transfers-are-unreliable-on-real-phones-high)).

Back to the [documentation index](../README.md).

---

## Contents

1. [Severity scale](#1-severity-scale)
2. [Transfer behaviour](#2-transfer-behaviour)
3. [Protocol and simulation](#3-protocol-and-simulation)
4. [Media and composing](#4-media-and-composing)
5. [Build, platform and release](#5-build-platform-and-release)
6. [Physical limits (by design)](#6-physical-limits-by-design)
7. [Summary table](#7-summary-table)

---

## 1. Severity scale

| Level | Meaning |
|---|---|
| **High** | Can make a user-visible transfer fail or report the wrong outcome |
| **Medium** | Wastes time or airtime, or misleads developers |
| **Low** | Cosmetic, or only reachable from developer screens |

---

## 2. Transfer behaviour

### 2.1 Sound sends were marked "delivered" (fixed)

- **Was.** After a Sound send, the sender's chat bubble showed *delivered*, even if nobody was listening. The fountain Sound path is broadcast-only and has no acknowledgement.
- **Now.** `AppController.sendPhysicalMessage` marks both direct paths (Light and Sound) as `sent`, or `failed`.
- **Also fixed at the same time.** Pressing **Stop** during a Sound send used to let the current burst (up to four frames, about 10 s) play out. `HardwareAcousticChannel.cancelTransmit` now stops the audio player immediately, and the transfer screen's cancel reaches it.

### 2.2 Sound messages over 8 KiB silently use a path the receiver can't decode (High)

- **Symptom.** A photo larger than about 8 KB sent over Sound never arrives.
- **Cause.** Only envelopes up to `acousticFountainMaxBytes` (8 192 B) take the fountain path. Larger ones go through `runHardwareTransfer` and the legacy packet/FSK modem. The receiver listens with the fountain modem, so it never decodes them.
- **Made worse by** send-time re-compression ([§4.1](#41-photos-are-re-compressed-and-grow-medium)): the bundled **5 KB** photos become 8.5–8.7 KB envelopes, just over the limit.
- **Workaround.** Use Light for anything above 2–3 KB. For Sound demos, use text or a **2 KB** photo.
- **Fix.** Refuse (or warn about) Sound envelopes over 8 KiB in the UI, or raise the limit (the fountain has no hard limit; 8 KiB is a time-budget choice).

### 2.3 Vibration airtime exceeds the acknowledgement timeout (Medium)

- **Symptom.** Vibration transfers of more than a few words take many minutes, or fail.
- **Cause.** A full 48-byte payload packet takes about 148 s to buzz out, while the hardware ACK timeout is 20 s (`hardwareTransportConfig`). The sender starts retransmitting while the first copy is still on air.
- **Workaround.** Keep vibration messages to a word or two ("hi", "ok", "sos").
- **Fix.** Scale `ackTimeoutMs` with the channel's expected airtime.

### 2.4 The Light sender can't know when the receiver finished (Low, by design)

Light has no return path, so the sender streams until **Stop** or the 10-minute safety cap. The receiver's **DONE** is the only completion signal. **Resume streaming** continues the same session if the sender stopped too early. See [ADR-14](../architecture/DESIGN_DECISIONS.md).

### 2.5 The Silent band depends on each phone's 19 kHz response (Medium, by design)

- **Symptom.** Silent transfers work between some pairs of phones and not others, or only in one direction. The receiver's *Silent band 18–20 kHz* meter stays near zero.
- **Cause.** Phone speakers and microphones aren't specified above about 16 kHz. Some are 30–40 dB down at 19 kHz; some capture paths low-pass the microphone even with the voice-recognition source (`HardwareAcousticChannel`), which Android only guarantees to pass 18.5–20 kHz on devices that declare near-ultrasound support. Bluetooth hands-free audio stops at 8 kHz, and web browsers resample the microphone.
- **Impact.** The simulator can't predict a given phone. Its near-ultrasonic results (Silent 14–18 of 18 frames in every scenario) assume the tones arrive at the stated SNR.
- **Workaround.** Media volume to maximum, phones 10–50 cm apart, speaker facing the microphone. Try swapping the roles. Fall back to **Audible** if the meter doesn't move. Rehearse on the actual demo phones.

### 2.6 Silent's first frame costs 4.8 s even for "sos" (Low, by design)

A Silent frame always carries a 24-byte block, so a three-letter message takes one 4.8 s frame. A plain two-tone FSK sender at 60 ms per bit needs 4.3 s for the same text, but falls behind from about five characters on and has no error correction. See [Sound Channel §14](../channels/SOUND_CHANNEL.md#14-silent-band-near-ultrasonic).

### 2.7 The live frequency readout is approximate in time (Low)

- **Symptom.**
  - The sender's **Sending now** can change tone a moment before the sound does.
  - On Audible chords, the receiver's **Hearing now** can report fewer tones than the sender lists.
  - The receiver occasionally shows two Silent tones for a moment at a symbol boundary.
- **Cause.**
  - `HardwareAcousticChannel._playWav` starts the readout clock when `AudioPlayer.play()` returns. Output buffering adds tens of milliseconds before the sound leaves the speaker, and far more over Bluetooth.
  - `SpectrumAnalyzer` treats peaks within 4 bins (172 Hz) of a stronger one as window leakage, and neighbouring audible groups can put tones 1 bin apart.
  - Its 23 ms window can straddle two symbols.
- **Impact.** Display only. Decoding doesn't use either readout, and the frequencies themselves are exact on the sender and accurate to a few hertz on the receiver.
- **Workaround.** Compare the kHz values, not their exact timing. For a clean side-by-side demo, use Silent, where one tone plays at a time.

### 2.8 Vibration transfers are unreliable on real phones (High)

- **Symptom.** A vibration send between two phones usually fails, stalls, or never shows the message on the receiver, even for a two-letter text.
- **Status.** Experimental. The bit codec passes its unit tests (`physical_codecs_test.dart`), but real phone-to-phone transfers haven't been made to work reliably. The `vibration-coupled` Simulation Lab scenario doesn't prove otherwise, because it ends up sending over the simulated optical channel ([§3.3](#33-other-simulation-lab-quirks-low), first row).
- **Likely causes** (not yet confirmed on devices):
  - Motor spin-up and spin-down times differ between phones, so the 80 ms and 180 ms pulses can arrive stretched or shortened past the 130 ms decision boundary.
  - The accelerometer sampling rate and noise vary by phone, and small movements shift the gravity baseline.
  - A single packet takes over a minute on air, far longer than the 20 s acknowledgement timeout ([§2.3](#23-vibration-airtime-exceeds-the-acknowledgement-timeout-medium)), so the sender retransmits over its own first copy.
  - The protocol path's ACK handling can lose track of gaps ([§3.1](#31-acks-are-treated-as-cumulative-high-for-the-protocol-path)).
  - iOS offers limited motor control, so it falls back to haptic ticks.
- **Workaround.** Use Light or Sound. Don't use Vibration in demonstrations.
- **Fix.** Calibrate pulse timing per phone, fix §2.3 and §3.1, then measure on several real device pairs.

---

## 3. Protocol and simulation

### 3.1 ACKs are treated as cumulative (High for the protocol path)

- **Cause.** The receiver ACKs each packet separately, but `ReliableTransport._handleAck` sets `lastAcked = seq` and drops *every* pending packet up to `seq` (`lib/core/transport/reliable_transport.dart`). A later NACK finds nothing pending to resend.
- **Impact.** Under loss, the sender can report "32 / 32 acknowledged" while the receiver still has gaps. The transfer then stalls until the iteration limit. This affects Vibration, over-8-KiB Sound, the legacy Messages screen and the Simulation Lab.
- **Fix.** Track ACKs per sequence number (a bitmap), and advance `lastAcked` only over a contiguous run.

### 3.2 Simulation scenarios that should switch channels fail (Medium)

`optical-degrades` and `burst-loss` fail in every measured run. The engine makes the right decision (optical ≈0.27, acoustic ≈0.70), but only at the first evaluation (iteration 20), after issue 3.1 has already stalled the transfer. Details and measurements: [Simulation Lab](../development/SIMULATION_LAB.md).

### 3.3 Other Simulation Lab quirks (Low)

| Quirk | Effect |
|---|---|
| Undiscoverable channels are still tested and can be selected | "Acoustic only" scenarios may run on optical |
| Override profiles replace *all* fields of a channel | Unset fields fall back to class defaults, not to the base profile |
| "Fixed" comparison strategies still run the adaptive orchestrator | Their switch count is hard-coded to 0 |
| Lost packets cost no simulated time | Throughput under loss looks better than reality |
| Progress bars stay at 0%, score rows don't update after a switch, "Run All" doesn't refresh the screen | UI only |
| The adaptive comparison uses 4 096 bytes instead of the scenario's 8 192; "Static Switch" is never run | Comparison numbers aren't like-for-like |

### 3.4 Hardware protocol selection ignores scores (Low)

In hardware mode with acoustic available and no forced channel, `TransferManager` always selects acoustic ("Acoustic is bidirectional", fixed score 0.9). The main UI always forces the channel, so this only shows up in the developer screens.

---

## 4. Media and composing

### 4.1 Photos are re-compressed and grow (Medium)

- **Cause.** `compressImageForTransfer` always decodes and re-encodes at JPEG quality 78. It runs in the compose screen for picked photos, and **again** in `AppController._prepareEnvelope` for every image, including the bundled samples.
- **Impact.** Already-small, low-quality JPEGs get **60–70% larger**: 2 KB samples become 3.3–3.5 KB, 5 KB become 8.5–8.7 KB, 20 KB become 32–35 KB. That's about 60% longer transfers on Light, and it breaks Sound for the 5 KB tier (issue 2.2).
- **Fix.** Skip re-encoding when the input is already a JPEG within the size and dimension limits, and don't compress twice.

### 4.2 Text typed next to an attachment replaces it (Medium)

If you attach a photo or video **and** type text, `SendComposeScreen._buildPayload` sends only the text. Fix: send both (two envelopes), or disable the text box while an attachment is present.

### 4.3 The Light frame's gzip flag is never used (Low)

`qrFountainFlagGzip` (`0x01`) and `isGzip` exist in `qr_fountain_frame.dart`, but no sender sets the flag and no receiver inflates. Text could gain 2–3× from compression; JPEG and MP4 gain nothing.

### 4.4 Envelope names are limited to 255 bytes (Low)

`nameLen` and `mimeLen` are single bytes. `ChatPayloadCodec.encode` doesn't truncate, so a UTF-8 file name over 255 bytes would corrupt the envelope. Fix: clamp names in `encode`.

### 4.5 Text in the compose screen uses `codeUnits` for `data` (Low)

`ComposePayload.data` for text is `text.codeUnits` (UTF-16 units truncated to bytes). The envelope itself is built from `text` via `encodeText` (UTF-8), so transfers are correct. Only `byteSize` shown before sending can be off for non-ASCII text.

---

## 5. Build, platform and release

| Issue | Where | Impact | Fix |
|---|---|---|---|
| Release builds are signed with the **debug key** | `android/app/build.gradle.kts` | Fine for sideloading and demos; can't be published on Play | Add a release keystore ([Build and Release](../operations/BUILD_AND_RELEASE.md)) |
| `applicationId` still marked TODO | Same file | A generic ID may clash with other builds | Choose a final reverse-DNS ID before publishing |
| Brightness boost is Android-only | `OpticalDisplayControl` | iOS senders must turn brightness up by hand | Add an iOS implementation (`UIScreen.main.brightness`) |
| Web: camera needs HTTPS or localhost; no vibration; no Gallery saving | Browser limits | Web works as a Light receiver/sender demo only | By design |
| `flutter test` reports the platform as Android on every OS | Test environment | `platform_capabilities_test` always takes the "hardware" branch | Documented in [Testing](../development/TESTING.md) |
| CSK and legacy FSK modems aren't reachable from the main UI | By design ([ADR-15](../architecture/DESIGN_DECISIONS.md)) | Kept as libraries and in tests | None needed |

---

## 6. Physical limits (by design)

These aren't bugs; they follow from the physics. See [Performance](../operations/PERFORMANCE.md).

| Limit | Value | Why |
|---|---|---|
| Light range | ≈15–40 cm | Pixels per QR module at the camera (≥ 5 needed) |
| Light speed | ≈1.3–2.5 KB/s | Camera decode rate × bytes per sparse QR |
| Sound speed | 10.8–35.8 B/s audible; 3.4–5.0 B/s Silent | Symbol length needed to beat echo; Silent can play only one tone at a time without an audible difference tone |
| Sound range | ≈0.3–2 m audible; ≈0.1–0.5 m Silent | Speaker power and room noise; phones are weak at 19 kHz |
| Vibration speed | ≈0.5 B/s (nominal; real transfers are unreliable, see §2.8) | Motor spin-up/down time (tens of ms per pulse) |
| Vibration range | Phones touching | The accelerometer must feel the other phone's motor |
| Security | None | See [Security](../operations/SECURITY.md) |

---

## 7. Summary table

| # | Issue | Severity | Area |
|---|---|---|---|
| 2.1 | Sound sends marked delivered; Stop let a burst play out | Fixed | App controller, acoustic channel |
| 2.2 | Sound > 8 KiB uses an undecodable path | High | App controller |
| 2.3 | Vibration airtime > ACK timeout | Medium | Transport config |
| 2.5 | Silent depends on each phone's 19 kHz response | Medium (by design) | Hardware |
| 2.6 | Silent "sos" takes one 4.8 s frame | Low (by design) | Sound profiles |
| 2.7 | Live kHz readout slightly ahead of the audio; close chord tones merge | Low | Sound UI |
| 2.8 | Vibration transfers unreliable on real phones (experimental) | High | Vibration channel |
| 3.1 | Cumulative ACK handling | High (protocol path) | Transport |
| 3.2 | Switching scenarios fail | Medium | Simulation |
| 3.3 | Simulation Lab quirks | Low | Simulation / UI |
| 3.4 | Hardware selection ignores scores | Low | Transfer manager |
| 4.1 | Photos re-compressed and grow | Medium | Media |
| 4.2 | Text replaces attachment | Medium | Compose UI |
| 4.3 | Gzip flag unused | Low | Light frame |
| 4.4 | 255-byte name limit unchecked | Low | Envelope |
| 4.5 | `codeUnits` byte size | Low | Compose model |
| 5 | Debug signing, TODO applicationId, platform gaps | Medium / Low | Build |

The [Roadmap](ROADMAP.md) turns the High and Medium items into planned work.
