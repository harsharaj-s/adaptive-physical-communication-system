# Changelog

The history of the project, from the first text-QR prototype to the current fountain-coded Light and Sound modems. The app version in `pubspec.yaml` is still `1.0.0+1`. The milestones below are named by the protocol generation they introduced, which is what matters for compatibility between two phones.

Back to the [documentation index](../README.md).

---

## Compatibility rule

Two phones can talk if they run builds from the **same milestone**. Light frames carry a version byte (APCF v3), and older v2 frames are rejected rather than mis-decoded. Sound frames of different generations simply don't sync, because the tone plan changed.

---

## Unreleased: documentation, branding and repository

- **Added** the full `docs/` set (33 documents): getting started, architecture, channels, algorithms, development, operations and project pages, with hex dumps generated from the real codecs.
- **Added** the app logo, drawn by `tool/make_app_icon.py`:
  - Android legacy, round, adaptive and themed (monochrome) icons; a dark splash screen on all Android versions, including the Android 12+ system splash.
  - All iOS App Icon sizes and a dark launch screen.
  - Web favicon, PWA and maskable icons, title, theme colour and a loading splash.
  - In the app: the home screen logo, logo marks in the app bars, and an About dialog with licences. The shared `AppBrand` / `AppLogo` / `BrandedTitle` live in `lib/ui/widgets/app_logo.dart`.
- **Changed** the Android window background to the brand colour, so there's no white flash before the first frame.
- **Changed** the web manifest name to "Adaptive Physical Communication", short name "Adaptive Comm".

---

## Milestone 5: media, samples and Gallery

- **Added** bundled demo samples in `assets/samples/`: four photo subjects at 2/5/10/20 KB, eight narrated explainer videos (80–160 KB) and a 23 KB A/V sync clip. They're generated reproducibly by `tool/make_sample_media.py` and `tool/make_explainer_videos.py` (Windows TTS narration, Pillow frames, two-pass size-targeted H.264/VP9 encodes).
- **Added** a **Samples** picker in the compose screen, with titles derived from file names.
- **Added** automatic saving of received photos and videos to the Gallery album **Adaptive Comm** through `gal`, with de-duplication and a manual **Save to Gallery** button.
- **Changed** photo compression to a 960 px, q78, ≤ 120 KiB JPEG ladder.

---

## Milestone 4: Sound modem v2 (MT-FSK + Reed-Solomon + fountain)

- **Added** multi-tone FSK: 6 or 8 simultaneous tones, 16 tones per group, 43.07 Hz spacing, phase-continuous symbols.
- **Added** Reed-Solomon RS(n, k) over GF(256) with Berlekamp–Massey, Chien and Forney, errors-and-erasures decoding, and GMD retries driven by per-byte confidence.
- **Added** a per-frame two-tone sync marker, leading-edge detection and fine timing refinement.
- **Added** four profiles (Rugged, Safe, Standard, Fast), which the **receiver detects automatically**.
- **Added** LT fountain coding over sound frames, burst playback, and a progress HUD (tone meter, solved blocks, repaired/rejected frames).
- **Added** a headless room simulator (SNR, reverb, high-frequency roll-off, clock drift, multipath) with easy/room/noisy/hostile scenarios.
- **Fixed** frame sync on real recordings (leading edge at 50% of the peak marker score; stale-lock recovery after 4 missed markers).

---

## Milestone 3: Light v3 (the reliability rewrite)

This milestone addressed the field report: *"stuck at 1/3 symbols, DEC 2/s"*.

- **Changed** the LT code from robust soliton to **cycled subsets (K ≤ 8) / dense (≤ 256) / sparse (> 256)** rows with an **exact incremental GF(2) Gauss-Jordan decoder**. Mean overhead is now 0–2.2 symbols, and small transfers no longer stall on the last block.
- **Changed** frames to **APCF v3** (22-byte header, CRC-32, content-derived session ID).
- **Changed** density to **Auto 160/240/330 bytes (QR v8/v10/v12)** at 12 fps, instead of 800 bytes (v20). The measured camera decode rate rose from about 13% to 55–70%.
- **Added** camera tuning: 1.5× zoom, −0.7 EV, Y-plane-only extraction, a single long-lived decode isolate with busy-drop, and a zxing2 sequence of GlobalHistogram → pureBarcode → Hybrid.
- **Added** QR rendering with a fixed mask and integer pixels per module, full screen brightness on Android, and the wakelock.
- **Added** **Resume streaming** (same session, new symbols), multi-session receivers (up to 3), and completed-session suppression.
- **Added** the optical camera simulator and density sweep tests.

---

## Milestone 2: fountain QR (APCF v2)

- **Added** a systematic LT fountain code and binary **raw byte-mode** QR frames (25% fewer bytes per QR than base64).
- **Added** the `OpticalModem` interface with `FountainQrModem` beside the existing CSK modem (no overwrite).
- **Added** the Light HUD (CAP/DEC/DROP/GOOD, NEW/DUP/RED), the aim guide, the immersive sender overlay and the completion card.
- **Added** Safe/Standard/Fast profiles.
- **Known problem**, fixed in milestone 3: dense v20 codes and a soliton decoder that stalled near the end.

---

## Milestone 1.5: colour-shift keying (CSK)

- **Added** a 4-colour screen-flash modem (red/green/blue/white = 2 bits per flash, preamble `00 55 AA FF`, up to 180 bytes).
- **Outcome:** too fragile under real white balance and auto-exposure, and about 160× slower than fountain QR v8. It was kept as a library and is no longer offered in the UI.

---

## Milestone 1: prototype

- **Added** the protocol stack: `PacketCodec` (24-byte little-endian header + CRC-32), `ReliableTransport` (sliding window, ACK/NACK), `TransferStateMachine`, `AdaptiveDecisionEngine` (weighted scoring, degradation threshold 0.65, hysteresis 0.15).
- **Added** the Simulation Lab with virtual endpoints, scenarios and a performance comparison.
- **Added** APCS1 text QR (base64 carousel), two-tone FSK sound (18 ms/bit), on/off light keying and vibration pulse-width keying.
- **Added** the physical-only policy: no radio of any kind in the data path.
- **Added** the chat UI, the APCM envelope for text/links/photos/videos, and the home screen with Send/Receive.

See also the [Design Decisions](../architecture/DESIGN_DECISIONS.md) and the [Legacy Modems](../channels/LEGACY_MODEMS.md) evolution timeline.
