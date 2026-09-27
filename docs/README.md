<p align="center"><img src="../assets/branding/app_icon.png" alt="Adaptive Physical Communication logo" width="112"></p>

# Adaptive Physical Communication System — Documentation

This folder is the complete documentation set for the **Adaptive Physical Communication System (APCS)**. APCS is a Flutter app that moves text, links, photos and short videos from one phone to another using only **light** (animated QR codes), **sound** (multi-tone chords) or **vibration** (motor pulses). No Internet, Wi-Fi, Bluetooth, NFC or mobile data is involved.

The root [`README.md`](../README.md) is a one-file technical manual. The documents here split that material by topic and go deeper. They add byte-level examples generated from the real code, step-by-step derivations, design rationale, developer references and operational guides.

---

## Start here

| If you are… | Read these, in order |
|---|---|
| **Presenting the app** at a showcase | [Showcase Guide](getting-started/SHOWCASE_GUIDE.md) → [User Guide](getting-started/USER_GUIDE.md) → [Troubleshooting](operations/TROUBLESHOOTING.md) |
| **Using the app** for the first time | [User Guide](getting-started/USER_GUIDE.md) → [FAQ](getting-started/FAQ.md) |
| **Building it** from source | [Installation](getting-started/INSTALLATION.md) → [Build and Release](operations/BUILD_AND_RELEASE.md) |
| **Explaining how it works** (viva, report, interview) | [Architecture](architecture/ARCHITECTURE.md) → [Fountain Code](algorithms/FOUNTAIN_CODE.md) → [Light Channel](channels/LIGHT_CHANNEL.md) → [Sound Channel](channels/SOUND_CHANNEL.md) → [Calculations](algorithms/CALCULATIONS.md) |
| **Changing the code** | [Architecture](architecture/ARCHITECTURE.md) → [API Reference](development/API_REFERENCE.md) → [UI Guide](development/UI_GUIDE.md) → [Testing](development/TESTING.md) → [Contributing](development/CONTRIBUTING.md) |
| **Checking limits and risks** | [Known Issues](project/KNOWN_ISSUES.md) → [Security](operations/SECURITY.md) → [Permissions and Privacy](operations/PERMISSIONS_AND_PRIVACY.md) |

---

## Documentation map

```
docs/
├── README.md                          ← you are here
├── getting-started/
│   ├── INSTALLATION.md                Toolchain, clone, run on phone / web
│   ├── USER_GUIDE.md                  Every screen and button, for end users
│   ├── SHOWCASE_GUIDE.md              Demo script, checklist, talking points, recovery plan
│   └── FAQ.md                         Short answers to common questions
├── architecture/
│   ├── ARCHITECTURE.md                Layers, modules, send/receive flows, threading
│   ├── DATA_FORMATS.md                Every byte layout with real hex dumps
│   └── DESIGN_DECISIONS.md            Why each major choice was made (decision records)
├── channels/
│   ├── LIGHT_CHANNEL.md               Fountain QR: framing, density, camera, HUD
│   ├── SOUND_CHANNEL.md               MT-FSK + Reed-Solomon + fountain over audio
│   ├── VIBRATION_CHANNEL.md           Pulse-width keying with motor and accelerometer
│   └── LEGACY_MODEMS.md               CSK light, APCS1 text QR, two-tone FSK
├── algorithms/
│   ├── FOUNTAIN_CODE.md               LT code: encoding, proofs, GF(2) decoder, worked example
│   ├── REED_SOLOMON.md                GF(256), Berlekamp–Massey, Forney, erasures, GMD
│   ├── SIGNAL_PROCESSING.md           Goertzel, tone orthogonality, sync, QR imaging
│   ├── ADAPTIVE_ENGINE.md             Transport, state machine, scoring, switching
│   └── CALCULATIONS.md                Every formula and worked number in one place
├── development/
│   ├── API_REFERENCE.md               Public classes, functions and constants in lib/core
│   ├── UI_GUIDE.md                    Screens, widgets, navigation, state management
│   ├── TESTING.md                     Test suite, simulators, device test checklist
│   ├── SIMULATION_LAB.md              Medium model, scenarios, orchestrator, comparison
│   ├── MEDIA_PIPELINE.md              Compression, demo samples, explainer tooling, Gallery
│   └── CONTRIBUTING.md                Workflow, code style, adding features safely
├── operations/
│   ├── BUILD_AND_RELEASE.md           APK / iOS / web builds, signing, versioning
│   ├── PERMISSIONS_AND_PRIVACY.md     Every permission and why; data handling
│   ├── SECURITY.md                    Threat model and what is (not) protected
│   ├── PERFORMANCE.md                 Throughput, timing tables, CPU and memory
│   └── TROUBLESHOOTING.md             Symptoms → causes → fixes
└── project/
    ├── CHANGELOG.md                   Version history
    ├── ROADMAP.md                     Planned and possible future work
    ├── KNOWN_ISSUES.md                Limitations and code-review findings
    ├── GLOSSARY.md                    Terms and abbreviations
    └── REFERENCES.md                  Papers, standards, libraries
```

---

## The system in one page

```
            SENDER PHONE                                   RECEIVER PHONE(S)
 ┌──────────────────────────────┐                ┌──────────────────────────────┐
 │ Text / link / photo / video  │                │ Message card, video player,  │
 │            │                 │                │ auto-save to Gallery         │
 │   APCM envelope (7 B + name  │                │            ▲                 │
 │   + MIME + raw bytes)        │                │   APCM envelope validated    │
 │            │                 │                │            ▲                 │
 │   LT fountain encoder        │                │   LT decoder (GF(2) exact)   │
 │   (endless fresh symbols)    │                │   done at rank = K           │
 │      │           │           │                │      ▲           ▲           │
 │  APCF frame   Acoustic frame │                │  APCF+CRC32  RS+CRC16        │
 │  + CRC-32     + CRC-16 + RS  │                │      ▲           ▲           │
 │      │           │           │                │      │           │           │
 │  QR code on   MT-FSK chords  │ ~~~ light ~~~► │  camera +    microphone +    │
 │  full-bright  from speaker   │ ~~~ sound ~~~► │  zxing2      Goertzel        │
 │  screen                      │                │                              │
 │                              │                │                              │
 │  Vibration: packets + CRC-32 │ ~~ contact ~~► │  accelerometer pulse timing  │
 └──────────────────────────────┘                └──────────────────────────────┘
```

**The four ideas that make it work:**

1. **Rateless fountain coding.** The sender never repeats itself and never waits for replies. The receiver completes as soon as it has caught about K good frames, *whichever* frames those are. See [Fountain Code](algorithms/FOUNTAIN_CODE.md).
2. **Camera-realistic QR density.** QR codes are kept sparse (version 8–12) because a hand-held camera reads a dense code only about 13% of the time. See [Light Channel](channels/LIGHT_CHANNEL.md).
3. **Soft-decision acoustic decoding.** The demodulator reports which bytes it is unsure of, and Reed-Solomon spends half the parity on those. See [Sound Channel](channels/SOUND_CHANNEL.md) and [Reed-Solomon](algorithms/REED_SOLOMON.md).
4. **Honest simulation before hardware.** Headless models of a phone camera and of a room drove every design number. See [Testing](development/TESTING.md).

---

## Key numbers

| Quantity | Value | Where explained |
|---|---|---|
| Light frame overhead | 26 bytes (22 header + 4 CRC-32) | [Data Formats](architecture/DATA_FORMATS.md#3-apcf-v3-light-frame) |
| Light bytes per QR (Auto) | 160 / 240 / 330 → QR v8 / v10 / v12 | [Light Channel](channels/LIGHT_CHANNEL.md#5-density-profiles-and-the-auto-rule) |
| Light display rate | 12 frames/s (Safe: 8) | [Light Channel](channels/LIGHT_CHANNEL.md) |
| Sound rates | 10.8 / 18.1 / 27.0 / 35.8 B/s | [Sound Channel](channels/SOUND_CHANNEL.md#7-profiles) |
| Sound tone spacing | 44 100 / 1024 = 43.066 Hz | [Signal Processing](algorithms/SIGNAL_PROCESSING.md) |
| Reed-Solomon repair | up to 12 errors or 24 erasures per 99-byte frame | [Reed-Solomon](algorithms/REED_SOLOMON.md) |
| Fountain overhead | mean 0–2.2 extra symbols | [Fountain Code](algorithms/FOUNTAIN_CODE.md#7-measured-overhead) |
| Adaptive score | 0.35T + 0.25R + 0.15L + 0.15C + 0.10S | [Adaptive Engine](algorithms/ADAPTIVE_ENGINE.md) |
| Vibration | ≈0.5 B/s | [Vibration Channel](channels/VIBRATION_CHANNEL.md) |

---

## Conventions used in these documents

- **Byte order.** Light and Sound frames are **big-endian**. Protocol packets are **little-endian**. Every table says which.
- **Hex dumps** are real output of the project's own codecs (generated on 27 Sep 2026), not hand-written.
- **"K"** always means the number of source blocks in a fountain transfer.
- **File paths** are relative to the project root, e.g. `lib/core/physical/fountain/lt_codec.dart`.
- **Numbers** are copied from the code. If the code and a document ever disagree, the code wins. Please fix the document (see [Contributing](development/CONTRIBUTING.md)).

## Related top-level files

- [`README.md`](../README.md): single-file technical manual.
- [`PROJECT_REPORT.md`](../PROJECT_REPORT.md): academic-style report (abstract, objectives, literature survey). Some parameters in it predate the current modems; where it differs, these documents are current.
