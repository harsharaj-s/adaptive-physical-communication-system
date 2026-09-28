# Changelog

All notable changes to this project are documented in this file, from the first text-QR prototype to the current fountain-coded Light and Sound modems.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Dates use the ISO 8601 format (YYYY-MM-DD).

Back to the [documentation index](../README.md).

---

## Versioning

The app hasn't published a tagged release yet; `pubspec.yaml` says `1.0.0+1`. Until the first tagged release, history is recorded as **protocol milestones**, because the protocol generation is what decides whether two phones can talk to each other.

From the first tagged release, the project will follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):

- **Major**: any wire-format change that stops older builds decoding the new frames (see the compatibility rule below).
- **Minor**: new features that keep the wire format compatible.
- **Patch**: bug fixes only.

## Compatibility rule

Two phones can talk if they run builds from the **same milestone**. Light frames carry a version byte (APCF v3), and older v2 frames are rejected rather than mis-decoded. Sound frames of different generations simply don't sync, because the tone plan changed. Each entry below says when a change breaks compatibility.

---

## [Unreleased]

Silent sound band, faster short texts, the live frequency readout, and the public-release documentation.

### Added

- A **Silent** band for Sound: the same frames, Reed-Solomon and fountain coding, played between 18.3 and 19.9 kHz, which most adults can't hear. Two profiles:
  - **Silent** (46 ms symbols, 5.0 B/s) and **Silent Robust** (70 ms symbols, 3.4 B/s).
  - One tone at a time. Two simultaneous tones would produce an audible difference tone in a small speaker.
  - Tones on every second bin (86 Hz apart) to tolerate hand-held Doppler.
  - A guard frame at the start of each symbol, ignored by the demodulator, so echoes of the previous tone have died away. This was the biggest single gain in the parameter sweep.
  - A sequential marker (bin 424, then bin 427) and a 4th-order 16 kHz high-pass in front of the Silent frame-syncs, so voices can't bury the marker.
  - The receiver listens for both bands at once and auto-detects all six profiles.
- On the Send screen: an Audible / Silent switch, per-band speed chips, and a **Frame to be sent** card that splits a frame's airtime into marker, header, message, CRC and parity and shows the tone range, frame time and frame count. The on-air size now shows the real envelope bytes.
- A *Silent band 18–20 kHz* level meter on the Receive screen.
- A live frequency readout. While playing, the Send screen shows **Sending now**: the exact tones on air, in kHz. While listening, the Receive screen shows **Hearing now**: the strongest frequencies the microphone picks up. Both include a 0–22 kHz spectrum strip with the Audible and Silent bands shaded.
- Near-ultrasonic room scenarios in the simulator (*ultra desk*, *ultra hand* with hand wobble, *chatter*, *crowd*) and six tests for the Silent band.
- Public-release repository files: `LICENSE` (MIT), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` (private vulnerability reporting), `CITATION.cff`, GitHub issue forms (bug report, device test report, feature request) and a pull request template.

### Changed

- Text and link envelopes carry no file name or MIME type: 7 bytes of overhead instead of 28. "sos" is now 10 B and a 17-character text 24 B, so short texts fit one Sound frame. Older receivers still decode them.
- The Android microphone source is now voice recognition, which must have noise suppression and AGC off and a flat response.
- Silent playback uses the plain media path, because the voice-call path filters out 18–20 kHz. Audible keeps the speakerphone voice path.
- Every sound burst starts and ends with a 256-sample raised-cosine fade and a 40 ms tail, removing clicks.
- The room simulator's clock-drift resampling is now cubic (Catmull-Rom) instead of linear. Linear interpolation attenuates a 19 kHz tone by about 6 dB. Some audible results moved slightly as a result.
- The documentation index is organised by reader need (tutorials, how-to guides, reference and explanation), and the README links to the community files.
- Performance figures in the README, the documentation index, Performance and the project report are labelled as nominal (calculated), estimated (from the simulators) or recommended. The report no longer calls Vibration "secure", and every mention of adaptive switching says it runs in the Simulation Lab and developer tools only.
- Vibration is now described as **experimental and unreliable on real phones** throughout the docs, with a new Known Issue (§2.8) and a Roadmap item. The Showcase guide no longer includes a Vibration step, and its Simulation Lab step says that `optical-degrades` currently ends in FAILED.

### Fixed

- **Stop** during a Sound send now cuts the playing burst immediately, instead of letting up to four frames play out.
- Sound sends are now marked *sent*, like Light, instead of *delivered*, because there's no return path.

### Compatibility

Silent frames don't sync on earlier builds, so both phones need this build to use Silent. Audible frames are unchanged.

---

## 2026-09-27: first repository commit

The first commit to the public repository. It contains milestones 1 to 5 below, plus the documentation and branding listed here.

### Added

- The full `docs/` set (33 documents): getting started, architecture, channels, algorithms, development, operations and project pages, with hex dumps generated from the real codecs.
- The app logo, drawn by `tool/make_app_icon.py`:
  - Android legacy, round, adaptive and themed (monochrome) icons; a dark splash screen on all Android versions, including the Android 12+ system splash.
  - All iOS App Icon sizes and a dark launch screen.
  - Web favicon, PWA and maskable icons, title, theme colour and a loading splash.
  - In the app: the home screen logo, logo marks in the app bars, and an About dialog with licences. The shared `AppBrand` / `AppLogo` / `BrandedTitle` live in `lib/ui/widgets/app_logo.dart`.

### Changed

- The Android window background is the brand colour, so there's no white flash before the first frame.
- The web manifest name is "Adaptive Physical Communication", short name "Adaptive Comm".

---

## Milestone 5: media, samples and Gallery

Milestones 1 to 5 were developed before the repository existed, so they have no individual dates.

### Added

- Bundled demo samples in `assets/samples/`: four photo subjects at 2/5/10/20 KB, eight narrated explainer videos (80–160 KB) and a 23 KB A/V sync clip. They're generated reproducibly by `tool/make_sample_media.py` and `tool/make_explainer_videos.py` (Windows TTS narration, Pillow frames, two-pass size-targeted H.264/VP9 encodes).
- A **Samples** picker in the compose screen, with titles derived from file names.
- Automatic saving of received photos and videos to the Gallery album **Adaptive Comm** through `gal`, with de-duplication and a manual **Save to Gallery** button.

### Changed

- Photo compression uses a 960 px, q78, ≤ 120 KiB JPEG ladder.

---

## Milestone 4: Sound modem v2 (MT-FSK + Reed-Solomon + fountain)

### Added

- Multi-tone FSK: 6 or 8 simultaneous tones, 16 tones per group, 43.07 Hz spacing, phase-continuous symbols.
- Reed-Solomon RS(n, k) over GF(256) with Berlekamp–Massey, Chien and Forney, errors-and-erasures decoding, and GMD retries driven by per-byte confidence.
- A per-frame two-tone sync marker, leading-edge detection and fine timing refinement.
- Four profiles (Rugged, Safe, Standard, Fast), which the **receiver detects automatically**.
- LT fountain coding over sound frames, burst playback, and a progress HUD (tone meter, solved blocks, repaired/rejected frames).
- A headless room simulator (SNR, reverb, high-frequency roll-off, clock drift, multipath) with easy/room/noisy/hostile scenarios.

### Fixed

- Frame sync on real recordings (leading edge at 50% of the peak marker score; stale-lock recovery after 4 missed markers).

### Compatibility

The tone plan replaced the two-tone FSK modem, so Sound frames from earlier builds don't sync.

---

## Milestone 3: Light v3 (the reliability rewrite)

This milestone addressed the field report: *"stuck at 1/3 symbols, DEC 2/s"*.

### Added

- Camera tuning: 1.5× zoom, −0.7 EV, Y-plane-only extraction, a single long-lived decode isolate with busy-drop, and a zxing2 sequence of GlobalHistogram → pureBarcode → Hybrid.
- QR rendering with a fixed mask and integer pixels per module, full screen brightness on Android, and the wakelock.
- **Resume streaming** (same session, new symbols), multi-session receivers (up to 3), and completed-session suppression.
- The optical camera simulator and density sweep tests.

### Changed

- The LT code moved from robust soliton to **cycled subsets (K ≤ 8) / dense (≤ 256) / sparse (> 256)** rows with an **exact incremental GF(2) Gauss-Jordan decoder**. Mean overhead is now 0–2.2 symbols, and small transfers no longer stall on the last block.
- Frames are **APCF v3** (22-byte header, CRC-32, content-derived session ID).
- Density is **Auto 160/240/330 bytes (QR v8/v10/v12)** at 12 fps, instead of 800 bytes (v20). The measured camera decode rate rose from about 13% to 55–70%.

### Compatibility

APCF v3 receivers reject v2 frames on purpose, so both phones need a milestone 3 or later build.

---

## Milestone 2: fountain QR (APCF v2)

### Added

- A systematic LT fountain code and binary **raw byte-mode** QR frames (25% fewer bytes per QR than base64).
- The `OpticalModem` interface with `FountainQrModem` beside the existing CSK modem (no overwrite).
- The Light HUD (CAP/DEC/DROP/GOOD, NEW/DUP/RED), the aim guide, the immersive sender overlay and the completion card.
- Safe/Standard/Fast profiles.

### Known problems

- Dense v20 codes and a soliton decoder that stalled near the end. Both were fixed in milestone 3.

---

## Milestone 1.5: colour-shift keying (CSK)

### Added

- A 4-colour screen-flash modem (red/green/blue/white = 2 bits per flash, preamble `00 55 AA FF`, up to 180 bytes).

### Outcome

Too fragile under real white balance and auto-exposure, and about 160× slower than fountain QR v8. It was kept as a library and is no longer offered in the UI.

---

## Milestone 1: prototype

### Added

- The protocol stack: `PacketCodec` (24-byte little-endian header + CRC-32), `ReliableTransport` (sliding window, ACK/NACK), `TransferStateMachine`, `AdaptiveDecisionEngine` (weighted scoring, degradation threshold 0.65, hysteresis 0.15).
- The Simulation Lab with virtual endpoints, scenarios and a performance comparison.
- APCS1 text QR (base64 carousel), two-tone FSK sound (18 ms/bit), on/off light keying and vibration pulse-width keying.
- The physical-only policy: no radio of any kind in the data path.
- The chat UI, the APCM envelope for text/links/photos/videos, and the home screen with Send/Receive.

---

See also the [Design Decisions](../architecture/DESIGN_DECISIONS.md) and the [Legacy Modems](../channels/LEGACY_MODEMS.md) evolution timeline.

[Unreleased]: https://github.com/harsharaj-s/adaptive_physical_communication_system/commits/main
