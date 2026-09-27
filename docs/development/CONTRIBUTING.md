# Contributing

How to make changes to the project safely: the workflow, the code conventions the existing code follows, how to add a feature without breaking two-phone compatibility, and how to keep these documents correct.

Back to the [documentation index](../README.md).

---

## Contents

1. [Principles](#1-principles)
2. [Workflow](#2-workflow)
3. [Project layout](#3-project-layout)
4. [Code style](#4-code-style)
5. [Performance rules](#5-performance-rules)
6. [Changing a wire format](#6-changing-a-wire-format)
7. [Common tasks](#7-common-tasks)
8. [Tests](#8-tests)
9. [Documentation](#9-documentation)
10. [Commits and pull requests](#10-commits-and-pull-requests)

---

## 1. Principles

1. **Extend, don't overwrite.** New modems, codecs and widgets sit *beside* the old ones behind shared interfaces (`OpticalModem`, channel classes). Legacy code stays as a library unless it's truly dead ([ADR-15](../architecture/DESIGN_DECISIONS.md)).
2. **Reuse over duplication.** One codec, one metrics notifier, one HUD widget, one logo widget (`AppLogo`). If you are about to copy a block, extract it instead.
3. **Physical channels only.** No network code in the data path ([ADR-01](../architecture/DESIGN_DECISIONS.md)).
4. **Simulate first.** Every PHY change is proven in a headless simulator test before touching hardware ([ADR-17](../architecture/DESIGN_DECISIONS.md)).
5. **Smooth UI.** Heavy work belongs in the decode isolate or is skipped when busy; never block the UI thread for more than a few milliseconds.

---

## 2. Workflow

```powershell
git checkout -b feature/short-description
flutter pub get
# ...edit...
dart format lib test
flutter analyze            # must print: No issues found!
flutter test               # must stay green
git commit -m "Short imperative summary"
git push -u origin feature/short-description
```

Then open a pull request against `main`. For PHY changes, also run the device checklist in [Testing](TESTING.md) on two real phones.

---

## 3. Project layout

| Path | Contents |
|---|---|
| `lib/main.dart` | App root, theme, `AppProvider`, overlay stack |
| `lib/application/` | `AppController`: the single controller the UI talks to |
| `lib/core/physical/` | Codecs and modems (fountain, acoustic, CSK, legacy) with no Flutter UI imports |
| `lib/core/channels/` | Hardware and simulated channel classes, `ChannelManager` |
| `lib/core/transport/`, `protocol/`, `manager/`, `engine/` | Packet protocol, reliable transport, state machine, adaptive engine |
| `lib/core/media/`, `chat/` | Compression, samples, Gallery, envelope codec |
| `lib/core/platform/` | Platform capabilities, notifiers, brightness control |
| `lib/core/simulation/`, `performance/` | Simulation Lab and comparisons |
| `lib/ui/` | Screens, widgets, models, theme |
| `test/` | Unit, simulator and widget tests |
| `tool/` | Asset generators (icon, samples, videos) |
| `docs/` | This documentation |

Details: [Architecture](../architecture/ARCHITECTURE.md) and [API Reference](API_REFERENCE.md).

---

## 4. Code style

The conventions visible throughout the existing code:

- **Lints:** `package:flutter_lints/flutter.yaml` (see `analysis_options.yaml`). Zero analyzer issues is the bar.
- **Imports:** absolute `package:adaptive_physical_communication/...` imports, not relative ones.
- **Naming:** `UpperCamelCase` types; `lowerCamelCase` members and top-level constants (e.g. `hardwareOpticalPacketSize`, `acousticFountainMaxBytes`); private members with `_`.
- **Constants live next to their meaning:** channel limits in `hardware_phy_config.dart`, profile numbers in the profile classes. Don't scatter magic numbers.
- **Doc comments** (`///`) on public classes and on anything whose *why* isn't obvious (e.g. "Runs synchronously in the camera callback, because the plugin recycles plane buffers"). Don't narrate what the next line does.
- **Immutability:** `const` constructors and `final` fields for value types (profiles, frames, decisions).
- **Byte handling:** `Uint8List`, `ByteData` with an explicit `Endian`. Light and Sound frames are big-endian; packets are little-endian.
- **State:** `AppController` (a `ChangeNotifier`) plus small dedicated notifiers for high-rate data (optical metrics, acoustic RX/TX state), so the HUD repaints without rebuilding whole screens.
- **UI:** Material 3, dark theme seeded from `#3B82F6`; wrap page bodies in `PageContainer`; use `BrandedTitle` for app bars and `AppBrand` for the app name and version.

---

## 5. Performance rules

| Rule | Reason |
|---|---|
| Drop work when busy; never queue camera frames | The fountain only needs *some* frames; queues add latency and memory |
| Move frames across isolates with `TransferableTypedData` | No copy |
| Allocate typed arrays once and reuse them in hot loops | Avoids GC pauses at 30 fps |
| Repaint only when the data changes (`shouldRepaint`) | Stable 12 fps QR display |
| Keep QR mask fixed, module size integer | 4 ms vs 15–40 ms per frame; crisp edges |
| No per-sample `List<double>` in audio paths | Use `Float32List` |

---

## 6. Changing a wire format

Two phones must agree byte-for-byte. Before changing any frame, envelope or packet:

1. **Bump the version** (APCF has a version byte; add one to any new format).
2. Make the receiver **reject** unknown versions rather than guess (as APCF v3 rejects v2).
3. Update [Data Formats](../architecture/DATA_FORMATS.md) with a regenerated hex dump from the real codec.
4. Add a round-trip test and, for PHY changes, a simulator test.
5. Add a [Changelog](../project/CHANGELOG.md) entry under a new milestone and state the compatibility break.

---

## 7. Common tasks

### Add a Light or Sound profile

1. Add a `static const` instance to `OpticalTxProfile` / `AcousticTxProfile` and include it in that class's `values` list.
2. Check it in the simulator tests (density sweep / acoustic scenarios) before exposing it.
3. Update the profile tables in [Light Channel](../channels/LIGHT_CHANNEL.md) or [Sound Channel](../channels/SOUND_CHANNEL.md) and [Calculations](../algorithms/CALCULATIONS.md).

### Add a new modem

1. Implement it under `lib/core/physical/<name>/` with no UI imports.
2. Plug it in through the existing interface (e.g. `OpticalModem`) beside the others.
3. Publish metrics through the existing notifiers so the HUD widgets work unchanged.

### Add a sample

Drop `name_<N>kb.jpg|png|mp4|webm` into `assets/samples/images/` or `videos/`. It appears automatically ([Media Pipeline](MEDIA_PIPELINE.md)).

### Change the logo or brand colour

Edit the constants in `tool/make_app_icon.py`, run it, and update the splash colour in the places listed in [Build and Release §7](../operations/BUILD_AND_RELEASE.md#7-icons-splash-and-generated-assets).

---

## 8. Tests

- Put tests in `test/<area>_test.dart`, and reuse the simulators (`optical_camera_sim.dart`, `acoustic_channel_sim.dart`).
- Use **seeded** `Random` so failures reproduce.
- Keep tests headless (no plugins); hardware behaviour goes on the manual device checklist.
- Long sweeps sit behind an environment variable (like `OPTICAL_SWEEP`) so the default run stays around 40 s.

See [Testing](TESTING.md).

---

## 9. Documentation

- **The code wins.** If a document disagrees with the code, fix the document in the same pull request.
- Every doc starts with a title, a one-paragraph intro and "Back to the [documentation index](../README.md)."
- Use numbered sections, tables for enumerable facts, relative links, and backticks for file and class names.
- Regenerate hex dumps and example numbers from the real code (a throwaway script under `tool/`, run with `dart run`, then deleted), never by hand.
- New documents must be added to the map in [`docs/README.md`](../README.md).

---

## 10. Commits and pull requests

- **Commits:** a short imperative subject ("Add Rugged sound profile"), with an optional body explaining *why*.
- **One topic per pull request**; keep refactors separate from behaviour changes.
- **The PR description** says what changed, why, how it was tested (tests + devices), and any compatibility impact.
- Never commit secrets: `android/key.properties`, keystores, `.env` files.
