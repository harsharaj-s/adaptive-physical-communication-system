<p align="center"><img src="../assets/branding/app_icon.png" alt="Adaptive Physical Communication logo" width="112"></p>

# Adaptive Physical Communication System — Documentation

This folder is the complete documentation set for the **Adaptive Physical Communication System (APCS)**. APCS is a Flutter app that moves text, links, photos and short videos from one phone to another using only **light** (animated QR codes) or **sound** (multi-tone chords). A third channel, **vibration** (motor pulses), is experimental and doesn't work reliably on real phones yet. No Internet, Wi-Fi, Bluetooth, NFC or mobile data is involved.

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
| **Contributing** to the project | [`CONTRIBUTING.md`](../CONTRIBUTING.md) → [Contributing (developer guide)](development/CONTRIBUTING.md) → [Code of Conduct](../CODE_OF_CONDUCT.md) |

---

## Documentation by type

The documents follow the [Diátaxis](https://diataxis.fr/) framework: each one is mainly a tutorial, a how-to guide, a reference or an explanation. Knowing which kind you need helps you pick the right page.

### Tutorials: learn by doing

| Document | What you'll do |
|---|---|
| [Installation](getting-started/INSTALLATION.md) | Go from a clean machine to the app running on a phone, in Chrome and in the test suite |
| [User Guide](getting-started/USER_GUIDE.md) | Make your first transfer, then learn every screen and button |

### How-to guides: get a specific job done

| Document | The job |
|---|---|
| [Showcase Guide](getting-started/SHOWCASE_GUIDE.md) | Run a live demo, with a checklist, script, talking points and a recovery plan |
| [Troubleshooting](operations/TROUBLESHOOTING.md) | Find the cause of a symptom and fix it |
| [Build and Release](operations/BUILD_AND_RELEASE.md) | Produce signed Android, iOS and web builds |
| [Contributing (developer guide)](development/CONTRIBUTING.md) | Add a profile, a modem or a sample, and change a wire format safely |
| [Media Pipeline](development/MEDIA_PIPELINE.md) | Regenerate demo samples and explainer videos |

### Reference: look up exact facts

| Document | What it lists |
|---|---|
| [API Reference](development/API_REFERENCE.md) | Every public class, function and constant in `lib/core`, `lib/application` and `lib/main.dart` |
| [Data Formats](architecture/DATA_FORMATS.md) | Every byte layout, with real hex dumps |
| [Calculations](algorithms/CALCULATIONS.md) | Every formula and worked number |
| [UI Guide](development/UI_GUIDE.md) | Screens, widgets, navigation and state management |
| [Testing](development/TESTING.md) | Every test file, the simulators and the device checklist |
| [Simulation Lab](development/SIMULATION_LAB.md) | The medium model, scenarios, orchestrator and comparison |
| [Performance](operations/PERFORMANCE.md) | Throughput, timing tables, CPU and memory |
| [Permissions and Privacy](operations/PERMISSIONS_AND_PRIVACY.md) | Every permission, why it's needed, and how data is handled |
| [Known Issues](project/KNOWN_ISSUES.md) | Limitations and code-review findings |
| [Changelog](project/CHANGELOG.md) | What changed in each milestone |
| [Glossary](project/GLOSSARY.md) | Terms and abbreviations |
| [References](project/REFERENCES.md) | Papers, standards and libraries |

### Explanation: understand why

| Document | The question it answers |
|---|---|
| [System Architecture](architecture/ARCHITECTURE.md) | How are the layers and modules put together? |
| [Design Decisions](architecture/DESIGN_DECISIONS.md) | Why was each major choice made, and what else was considered? |
| [Light Channel](channels/LIGHT_CHANNEL.md) | How does the animated fountain QR link work? |
| [Sound Channel](channels/SOUND_CHANNEL.md) | How do MT-FSK, Reed-Solomon and fountain coding work over audio? |
| [Vibration Channel](channels/VIBRATION_CHANNEL.md) | How is pulse-width keying between motor and accelerometer designed? (Experimental, not reliable yet.) |
| [Legacy Modems](channels/LEGACY_MODEMS.md) | What came before, and why was it replaced? |
| [Fountain Code](algorithms/FOUNTAIN_CODE.md) | How does the LT code let the receiver finish with any K frames? |
| [Reed-Solomon](algorithms/REED_SOLOMON.md) | How are corrupted bytes repaired? |
| [Signal Processing](algorithms/SIGNAL_PROCESSING.md) | How are tones detected, synchronised and shown live? |
| [Adaptive Engine](algorithms/ADAPTIVE_ENGINE.md) | How are channels scored and switched? |
| [Security](operations/SECURITY.md) | What is protected, what isn't, and why? |
| [FAQ](getting-started/FAQ.md) | Short answers to the questions people ask most |
| [Roadmap](project/ROADMAP.md) | Where could the project go next? |

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
│   ├── VIBRATION_CHANNEL.md           Pulse-width keying with motor and accelerometer (experimental)
│   └── LEGACY_MODEMS.md               CSK light, APCS1 text QR, two-tone FSK
├── algorithms/
│   ├── FOUNTAIN_CODE.md               LT code: encoding, proofs, GF(2) decoder, worked example
│   ├── REED_SOLOMON.md                GF(256), Berlekamp–Massey, Forney, erasures, GMD
│   ├── SIGNAL_PROCESSING.md           Goertzel, tone orthogonality, sync, QR imaging, live-readout FFT
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
├── project/
│   ├── CHANGELOG.md                   Version history
│   ├── ROADMAP.md                     Planned and possible future work
│   ├── KNOWN_ISSUES.md                Limitations and code-review findings
│   ├── GLOSSARY.md                    Terms and abbreviations
│   └── REFERENCES.md                  Papers, standards, libraries
└── images/                            Screenshots used by the guides and the root README
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
2. **Camera-realistic QR density.** QR codes are kept sparse (version 8–12) because, in the camera simulator and in an early field test, a hand-held camera read a dense (version 20) code only about 11–13% of the time. See [Light Channel](channels/LIGHT_CHANNEL.md).
3. **Soft-decision acoustic decoding.** The demodulator reports which bytes it is unsure of, and Reed-Solomon spends half the parity on those. See [Sound Channel](channels/SOUND_CHANNEL.md) and [Reed-Solomon](algorithms/REED_SOLOMON.md).
4. **Honest simulation before hardware.** Headless models of a phone camera and of a room drove every design number. See [Testing](development/TESTING.md).

---

## Key numbers

Most of these values are exact, because they're set in the code: frame sizes, frequencies, tone spacing and the scoring weights. The rates are **nominal**, calculated from each profile's timing; real transfers take longer when frames are lost, and results vary between phones. See [Performance](operations/PERFORMANCE.md) for how each figure is derived.

| Quantity | Value | Where explained |
|---|---|---|
| Light frame overhead | 26 bytes (22 header + 4 CRC-32) | [Data Formats](architecture/DATA_FORMATS.md#3-apcf-v3-light-frame) |
| Light bytes per QR (Auto) | 160 / 240 / 330 → QR v8 / v10 / v12 | [Light Channel](channels/LIGHT_CHANNEL.md#5-density-profiles-and-the-auto-rule) |
| Light display rate | 12 frames/s (Safe: 8) | [Light Channel](channels/LIGHT_CHANNEL.md) |
| Sound rates (nominal) | 10.8 / 18.1 / 27.0 / 35.8 B/s audible; 3.4 / 5.0 B/s Silent (18–20 kHz) | [Sound Channel](channels/SOUND_CHANNEL.md#7-profiles) |
| Sound tone spacing | 44 100 / 1024 = 43.066 Hz | [Signal Processing](algorithms/SIGNAL_PROCESSING.md) |
| Sound time per bit | Standard 2.9 ms raw / 4.6 ms net; Silent 11.6 ms raw / 25 ms net (16-ary FSK, 4 bits per tone) | [FAQ](getting-started/FAQ.md#sound-channel) |
| Reed-Solomon repair | up to 12 errors or 24 erasures per 99-byte frame | [Reed-Solomon](algorithms/REED_SOLOMON.md) |
| Fountain overhead | mean 0–2.2 extra symbols (measured in tests) | [Fountain Code](algorithms/FOUNTAIN_CODE.md#7-measured-overhead) |
| Adaptive score | 0.35T + 0.25R + 0.15L + 0.15C + 0.10S | [Adaptive Engine](algorithms/ADAPTIVE_ENGINE.md) |
| Vibration (nominal; experimental, unreliable) | ≈0.5 B/s | [Vibration Channel](channels/VIBRATION_CHANNEL.md) |

---

## Conventions used in these documents

- **Byte order.** Light and Sound frames are **big-endian**. Protocol packets are **little-endian**. Every table says which.
- **Hex dumps** are real output of the project's own codecs (generated on 27 Sep 2026; envelope and Sound dumps regenerated on 28 Sep 2026 for the compact envelopes and the Silent band), not hand-written.
- **"K"** always means the number of source blocks in a fountain transfer.
- **File paths** are relative to the project root, e.g. `lib/core/physical/fountain/lt_codec.dart`.
- **Numbers** are copied from the code. If the code and a document ever disagree, the code wins. Please fix the document (see [Contributing](development/CONTRIBUTING.md)).
- **Style.** British English in prose, "you" for the reader, **bold** for buttons and labels in the app, `code font` for files, classes and commands. The full style rules are in [Contributing §9](development/CONTRIBUTING.md#9-documentation).

---

## Getting help

1. Search these documents; the [FAQ](getting-started/FAQ.md) and [Troubleshooting](operations/TROUBLESHOOTING.md) answer most questions.
2. Check [Known Issues](project/KNOWN_ISSUES.md) to see whether the problem is already known.
3. Open an issue on GitHub using the **Bug report**, **Device test report** or **Feature request** form.
4. For a security problem, don't open an issue; follow the [security policy](../SECURITY.md).

---

## Related top-level files

| File | Purpose |
|---|---|
| [`README.md`](../README.md) | Single-file technical manual and project front page |
| [`PROJECT_REPORT.md`](../PROJECT_REPORT.md) | Academic-style report (abstract, objectives, literature survey) |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | How to report bugs, share device results and open pull requests |
| [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) | Community rules (Contributor Covenant 2.1) |
| [`SECURITY.md`](../SECURITY.md) | Supported versions and private vulnerability reporting |
| [`CITATION.cff`](../CITATION.cff) | Citation metadata for academic use |
| [`LICENSE`](../LICENSE) | MIT License |
| [`llms.txt`](../llms.txt) | Short project summary and documentation map for AI assistants ([llmstxt.org](https://llmstxt.org/) format) |
| [`_config.yml`](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/_config.yml) | Settings for the [documentation website](https://harsharaj-s.github.io/adaptive-physical-communication-system/) built by GitHub Pages |
| [`.github/`](https://github.com/harsharaj-s/adaptive-physical-communication-system/tree/main/.github) | Issue forms and the pull request template |
