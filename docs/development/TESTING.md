# Testing

This document explains how the APCS automated test suite is run, what every test file proves, and how the two headless physical models work: the phone-camera simulator behind the Light tests and the room simulator behind the Sound tests. It also lists the conventions to follow when adding tests, a manual checklist for testing on two real phones, and the parts of the app that no automated test reaches. Every count, threshold and printed value below was taken from the test code or from a real run on 2026-09-27 with Flutter 3.41.1 and Dart 3.11.0.

Back to the [documentation index](../README.md).

---

## Contents

1. [Overview and how to run the tests](#1-overview-and-how-to-run-the-tests)
2. [Test inventory](#2-test-inventory)
3. [What each area covers](#3-what-each-area-covers)
4. [The simulators explained](#4-the-simulators-explained)
5. [Writing new tests](#5-writing-new-tests)
6. [Device test checklist](#6-device-test-checklist)
7. [Coverage gaps](#7-coverage-gaps)

---

## 1. Overview and how to run the tests

All tests are plain `flutter_test` tests in `test/`. They are headless: none of them needs a phone, a camera, a microphone or a network connection. The Light and Sound tests reach realistic conditions by pushing real production code through software models of a camera and a room (see [section 4](#4-the-simulators-explained)).

Run every command from the project root in PowerShell.

### 1.1 Commands

| Goal | Command |
|---|---|
| Run the whole suite | `flutter test` |
| See one line per test and the values the tests print | `flutter test --reporter expanded` |
| Machine-readable results with per-test timings | `flutter test --reporter json > results.json` |
| Run one file | `flutter test test/reed_solomon_test.dart` |
| Run one test by name | `flutter test test/lt_small_k_test.dart --plain-name "K=3 with five distinct repair symbols"` |
| Run tests whose names match a regular expression, across all files | `flutter test --name "scenario completes"` |
| Run files one at a time (for fair timings) | `flutter test --concurrency=1` |
| Static analysis | `flutter analyze` |

`--plain-name` matches a plain substring of the full test name, and the full name includes any `group(...)` prefix. For example, the full name of a test in `acoustic_channel_test.dart` is `acoustic profiles rugged profile carries a message through a hostile room`, so either the whole string or any part of it can be passed.

Many tests print measurements (decode rates, frame counts, overhead tables). The default compact reporter hides them; use `--reporter expanded` to see them.

### 1.2 The `OPTICAL_SWEEP` environment variable

`OPTICAL_SWEEP` is the only environment variable the tests read. When it is unset, the `full density table` test in `optical_density_sweep_test.dart` is skipped with the reason `set OPTICAL_SWEEP=1 to print the full table`. When it is set to any value, the test runs; it renders 512 camera frames and has a 30-minute timeout.

```powershell
$env:OPTICAL_SWEEP = "1"
flutter test test/optical_density_sweep_test.dart --plain-name "full density table" --reporter expanded
Remove-Item Env:OPTICAL_SWEEP
```

The test only checks the value against `null`, so any value, including `"0"`, enables it. Remove the variable afterwards so later runs skip the table again.

### 1.3 Latest results

| Item | Value |
|---|---|
| Date | 2026-09-28 |
| Toolchain | Flutter 3.41.1, Dart 3.11.0, Windows 10.0.26200 |
| Test files | 22 (plus 2 helper files that contain no tests) |
| Tests declared | 101 (88 before the Silent sound band, 94 before the live frequency readout) |
| Passed | 100 |
| Skipped | 1 (`full density table`, needs `OPTICAL_SWEEP`) |
| Failed | 0 |
| Final line | `All tests passed!` |
| Duration | About 38–39 s on the test runner's clock; just under a minute of wall-clock time including compilation |
| `flutter analyze` | No issues found |

The slowest files are `optical_density_sweep_test.dart` and `acoustic_channel_test.dart`, which render 720 × 720 camera frames and synthesise tens of seconds of audio, and `simulation_integration_test.dart`, whose simulated medium really waits for each packet's delay.

---

## 2. Test inventory

Counts come from the JSON reporter of the run above. The runner executes every file whose name ends in `_test.dart`.

| File | What it covers | Tests |
|---|---|---|
| `acoustic_channel_test.dart` | Sound profiles through the room simulator at frame-sync level: rates, per-scenario frame recovery, full transfers in `room`, `noisy room` and `hostile`, per-band ladders; Silent band plan, energy below 16 kHz, transfers in every near-ultrasonic scenario, odd-group byte packing | 12 |
| `acoustic_live_tone_test.dart` | The live frequency readout: `ToneTimeline` matches `MtFskCodec.encode` sample for sample in all six profiles; silence merging and time lookup; `onBurst` timelines match every Standard and Silent WAV burst, with the right tone count per segment; `SpectrumAnalyzer` places a pure 18 906 Hz tone within 8 Hz, resolves a four-tone chord, and stays empty on silence and after `reset` | 7 |
| `acoustic_modem_test.dart` | The complete `AcousticFountainModem` loop (WAV out, room, PCM16 in), rateless stopping, profile auto-detection across both bands, fixed-profile receivers, profile switching, a Silent hand-held loopback, PCM16 conversion | 9 |
| `adaptive_engine_test.dart` | `AdaptiveDecisionEngine`: best-channel selection, switch hysteresis, degradation threshold | 3 |
| `broadcast_mode_test.dart` | Broadcast is the hardware default; `ReliableTransport` sends without ACKs in broadcast mode and de-duplicates received sequence numbers | 3 |
| `fountain_benchmark_test.dart` | LT recovery of a 365 KiB file on the Standard Light profile with erasures, decode speed, and the optical `slower` ladder | 2 |
| `fountain_qr_roundtrip_test.dart` | The real Light pipeline without a device: QR byte-mode encoding, rasterisation, `zxing2` decoding, APCF parsing and LT reassembly for text, photo, video and hostile binary data | 6 |
| `gallery_saver_test.dart` | Which messages `GallerySaver` may save, and that it is a no-op on the desktop test host | 2 |
| `image_envelope_test.dart` | A JPEG in an APCM envelope survives the legacy `APCS1` QR chunking and decodes back to a displayable image | 1 |
| `lt_codec_test.dart` | `LtEncoder` / `LtDecoder` basics and the APCF v3 frame codec (`QrFountainFrameCodec`): CRC-32, raw byte path, padding, `FQR3:` string path | 9 |
| `lt_small_k_test.dart` | Decoder rank against an independent GF(2) rank, K = 3 edge case, reception overhead for K from 1 to 600 | 3 |
| `optical_density_sweep_test.dart` | Auto density selection and decode rates through the simulated hand-held camera; 2 KB files through `typical` and `hard` cameras with frame loss; optional full density table | 5 (1 skipped) |
| `physical_codecs_test.dart` | Legacy codecs: `OpticalBitCodec`, `FskCodec`, `Goertzel`, `VibrationBitCodec` (pulse-width keying), `FskStreamDecoder` | 10 |
| `physical_only_test.dart` | The physical-only policy: exactly three channel IDs, excluded network transports, policy summary text | 3 |
| `platform_capabilities_test.dart` | Platform capability flags and labels | 2 |
| `protocol_test.dart` | CRC-32 and `PacketCodec` encode, decode and corruption rejection | 4 |
| `qr_optical_codec_test.dart` | The legacy `APCS1:` QR chunk codec: single chunk, multiple chunks, foreign strings | 3 |
| `reed_solomon_test.dart` | GF(256) Reed-Solomon encoding and errors-and-erasures decoding | 9 |
| `sample_media_test.dart` | Parsing of sample asset names and loading of every bundled sample within its size budget | 2 |
| `simulation_integration_test.dart` | Three Simulation Lab scenarios end to end through `SimulationOrchestrator` | 3 |
| `state_machine_test.dart` | `TransferStateMachine` legal path and illegal transition | 2 |
| `widget_test.dart` | The home screen renders Send and Receive | 1 |
| **Total** | | **101** (100 run, 1 skipped) |

Two files in `test/` are helpers and contain no tests:

| File | Purpose |
|---|---|
| `optical_camera_sim.dart` | `CameraDegradation` and `renderCameraFrame`: renders a QR code as a phone camera would capture it from another phone's screen |
| `acoustic_channel_sim.dart` | `AcousticScenario` and `simulateAcoustic`: passes a waveform through a simulated speaker, room and microphone |

---

## 3. What each area covers

Test names are given in *italics*. "Floor" means a minimum the test asserts. Seeds are listed where they decide the outcome, because every Light and Sound test is deterministic for a given seed.

### 3.1 Fountain code (LT)

The algorithm itself is described in [FOUNTAIN_CODE.md](../algorithms/FOUNTAIN_CODE.md).

**`lt_codec_test.dart`, group `LtCodec` (3 tests)**

| Test | What it checks |
|---|---|
| *systematic path recovers with exactly K symbols* | 5000 bytes at `blockLen` 200: feeding symbols 0 … K − 1 completes the decoder and returns the exact bytes. |
| *recovers with 30% random erasures using repair symbols* | 12 000 bytes at `blockLen` 250; each symbol is dropped with probability 0.30 (`Random(7)`), up to `ceil(1.6K) + 20` symbols. The file must complete. |
| *duplicate symbols are ignored* | Adding symbol 0 twice returns `true` then `false`, and `duplicateSymbols` is 1. |

**`lt_small_k_test.dart` (3 tests)**

| Test | What it checks |
|---|---|
| *decoder completes exactly when the received symbols reach rank K* | For K in {1, 2, 3, 4, 5, 7, 8, 9, 12, 40, 257, 300}, 30 trials each, K + 3 random distinct symbols. After every symbol, `dec.rank` must equal a GF(2) rank computed independently in the test from `LtEncoder.neighborsFor`, and the decoder is complete exactly when the rank is K. |
| *K=3 with five distinct repair symbols always completes* | 500 trials of a 2000-byte file at `blockLen` 800 (K = 3), using five consecutive repair symbols as a camera that missed the systematic frames would see them. |
| *overhead stays under two symbols for every K a camera will see* | For K from 1 to 600, with 40% loss and a late start, the number of extra symbols needed beyond K must have a mean below 2.5 and a 95th percentile of at most 7. |

The overhead test printed the following in the latest run (extra symbols beyond K):

| K | 1 | 2 | 3 | 5 | 8 | 9 | 16 | 32 | 64 | 128 | 256 | 300 | 600 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Mean | 0.00 | 0.10 | 0.28 | 1.00 | 1.10 | 1.52 | 1.63 | 1.87 | 1.43 | 1.73 | 1.68 | 1.75 | 2.17 |
| p95 | 0 | 1 | 1 | 3 | 4 | 5 | 5 | 5 | 5 | 5 | 6 | 5 | 6 |

**`fountain_benchmark_test.dart` (2 tests)**

- *Standard profile recovers ~365 KB with 25% frame loss* encodes 365 × 1024 bytes at the Standard `blockLen` of 330, drops symbols with probability **0.20** (`Random(365)`), and requires byte-exact recovery, a decode goodput above 40 KB/s and an erased fraction above 0.1. The name says 25%, but the code uses 20%.
- *OpticalTxProfile.slower steps Safe←Standard←Fast* checks that `fast.slower` is Standard, `standard.slower` is Safe, and `safe.slower` is Safe.

### 3.2 Light frame format and QR round trip

See [LIGHT_CHANNEL.md](../channels/LIGHT_CHANNEL.md) for the channel design.

**`lt_codec_test.dart`, group `QrFountainFrameCodec` (6 tests)** covers the APCF v3 frame (magic `APCF`, `qrFountainVersion = 3`, 22-byte header plus a 4-byte CRC-32): a normal round trip with CRC verification; rejection of a frame whose last byte is flipped; a round trip through the raw QR byte path with bytes that are invalid UTF-8; tolerance of trailing QR padding; the `FQR3:` base64 string path used by the web sampler, which must stay pure ASCII; and `decodeFromQrBytes` accepting `FQR3:` text delivered as UTF-8 bytes.

**`fountain_qr_roundtrip_test.dart` (6 tests)** runs the production Light pipeline with no device: `qr` byte-mode encoding at error-correction level L and mask 0, rasterisation at 4 pixels per module, the production decoder `decodeQrBytesFromLuminance` (built on `zxing2`), APCF parsing and LT reassembly. The file's header explains why it exists: it catches transport-level corruption that a codec-only unit test cannot see.

| Test | What it checks |
|---|---|
| *text message survives the full pipeline* | A text envelope on the Standard profile; every rendered QR must decode (`failed == 0`) and the bytes must match. |
| *photo survives with 30% of frames dropped* | A 40 KiB pseudo-random photo envelope, 30% of frames skipped, seed 11. |
| *video survives with 30% of frames dropped* | A 30 KiB pseudo-random video envelope, 30% of frames skipped, seed 23. |
| *every profile stays within a camera-readable QR version* | An 8 KiB file on every profile; no undecodable frames and QR version at most 25 (117 modules). |
| *production decoder reads every rendered frame* | 150 frames per profile (3 seeds × 50). The decoder's loss must stay below 1%. It also measures a finder-pattern-only decode, printed for comparison but not asserted. |
| *binary payloads that look like text are not mangled* | 2048 bytes cycling `00 FF C0 80 ED A0` on the Safe profile. |

Values printed in the latest run:

| Profile | Block (bytes) | Framed size | QR version | K for 8 KiB | Finder-only loss | Production decoder loss |
|---|---|---|---|---|---|---|
| Auto | 240 | 266 B | 10 (57 modules) | 35 | 3.3% | 0.0% |
| Safe | 160 | 186 B | 8 (49 modules) | 52 | 2.7% | 0.0% |
| Standard | 330 | 356 B | 12 (65 modules) | 25 | 4.0% | 0.0% |
| Fast | 600 | 626 B | 17 (85 modules) | 14 | 2.7% | 0.0% |

The round-trip helper uses the Auto profile's nominal block of 240 bytes; the size-based Auto ladder is tested separately in `optical_density_sweep_test.dart`.

**Legacy QR path.** `qr_optical_codec_test.dart` (3 tests) covers the older `APCS1:` text-QR chunk codec: a small packet fits one chunk, a 1400-byte payload splits into several chunks and reassembles, and `https://example.com` and `APCS2:abc:1/1:QQ` are rejected. `image_envelope_test.dart` (1 test) sends a 64 × 64 JPEG envelope through the same legacy chunking and checks that it decodes back to a displayable image of the same length.

### 3.3 Optical camera simulator and density sweep

`optical_density_sweep_test.dart` pushes fountain QR frames through the camera model in `optical_camera_sim.dart` (explained in [section 4.1](#41-camera-simulator-optical_camera_simdart)) and into the production decoder.

| Test | What it checks |
|---|---|
| *Auto keeps small payloads on sparse QR versions* | `OpticalTxProfile.auto.resolveFor` returns a block of 160 for 300 B and 2 KB, 240 for 10 KB, and 330 for 15 KB and 200 KB. Standard always uses 330. A 2 KB file's QR is version 8 or lower. |
| *Auto ladder decodes reliably at the field-report pose* | 12 frames per block size in the `typical` tier. Floors: 160 B at least 90%, 240 B at least 80%, 330 B at least 60%. The old 800-byte density must decode below 50%. |
| *2 KB file completes through a hand-held camera with 30% frame loss* | A 2000-byte file envelope on Auto, `typical` camera, 30% frames lost. Must be byte-exact and finish in fewer than 2K + 12 frames shown. |
| *2 KB file still completes when the camera is too far and shaky* | The same file through `CameraDegradation.hard.zoomed(1.5)`, seed 2. Must be byte-exact. |
| *full density table* | Skipped unless `OPTICAL_SWEEP` is set. Prints the decode rate and decode time for 8 block sizes × 4 camera tiers, 16 frames per cell. |

Key results printed in the latest run:

| Measurement | Result |
|---|---|
| `typical`, 160 B (QR v8) | 100% decoded |
| `typical`, 240 B (QR v10) | 92% decoded |
| `typical`, 330 B (QR v12) | 75% decoded |
| `typical`, 800 B (QR v20, the old default) | 8% decoded |
| 2 KB file, `typical` | K = 13, block 160, done after 22 frames shown (13 decoded), about 1.8 s at 12 fps |
| 2 KB file, `hard x1.5` | K = 13, done after 23 frames shown (14 decoded), about 1.9 s |

Decode rates are deterministic for a given seed; the milliseconds-per-frame figures the test also prints depend on the machine and on how many test files run in parallel.

Full density table from an `OPTICAL_SWEEP` run on 2026-09-27, which took 3 min 16 s on the runner's clock. Each cell is the decode rate and the mean decode time per frame:

```
block  QRv  good            typical         hard            hard x1.5
  100  v6   100%    7ms   100%    4ms    94%    9ms    94%    8ms
  160  v8   100%    4ms   100%    5ms    63%    9ms    81%    7ms
  240  v10  100%    5ms    94%    6ms    13%   16ms    88%    9ms
  330  v12  100%    5ms    81%    7ms     0%   16ms    56%   11ms
  430  v14   88%    7ms    69%    8ms     0%   15ms    44%   13ms
  600  v17  100%    7ms    31%   10ms     0%   12ms    25%   13ms
  800  v20  100%   10ms    13%   11ms     0%   11ms     0%   15ms
 1200  v25   81%   10ms     0%   13ms     0%   11ms     0%   12ms
```

The `typical` column is the data behind the Auto ladder: the comment above `OpticalTxProfile.auto` quotes the same rates (160 B 100%, 240 B 94%, 330 B 81%, 600 B 31%, 800 B 13%, 1200 B 0%). The `hard x1.5` column shows why receiver zoom matters: at 240 B the `hard` rate rises from 13% to 88%. The 12-frame floor test above prints slightly different rates for the same tier (for example 92% instead of 94% at 240 B) because it uses fewer frames; neither is wrong.

With 16 frames per cell, one frame is 6.25 percentage points, so small non-monotonic steps between neighbouring cells are sampling noise rather than a real effect.

### 3.4 Acoustic modem and room simulator

See [SOUND_CHANNEL.md](../channels/SOUND_CHANNEL.md) for the channel design. Both Sound transfer test files feed audio to the receiver in 2048-sample chunks, so the streaming path is what gets tested.

**`acoustic_channel_test.dart` (12 tests)** works at frame-sync level: it wraps LT symbols in acoustic fountain frames (`AcousticFrame`), modulates them with each profile's codec, passes them through `simulateAcoustic`, and feeds `AcousticFrameSync`. Its `runTransfer` helper sends bursts of 2 frames until the LT decoder completes or a symbol budget of `ceil(K × symbolBudget) + 24` is reached (default `symbolBudget` 3.0).

| Test | What it checks |
|---|---|
| *advertised rates and frame geometry* | Every audible profile's net rate is above 7.0 B/s, every Silent one above 3.0 B/s. |
| *frame recovery rate per scenario* | Prints frames recovered out of 16 for each audible profile in `easy`, `room` and `noisy room` (seed 9). It asserts nothing. |
| *text message arrives in a normal room* | A text envelope on Standard in `room`. |
| *every audible profile recovers a payload in a normal room* | A 415-byte envelope on every audible profile in `room`, seed 17. |
| *safe profile still works in a noisy room* | Safe in `noisy room`, seed 23, `symbolBudget` 6. |
| *rugged profile carries a message through a hostile room* | The text `sos` on Rugged in `hostile`, seed 5, `symbolBudget` 20. |
| *each band's ladder is ordered slowest to fastest* | Within `AcousticTxProfile.forBand(band)` each profile is strictly faster than the previous one, `faster.slower == slower`, and the slowest is its own `slower`. |
| *every tone stays inside 18–20 kHz* | Silent codecs' lowest and highest frequencies, sync included, lie inside 18–20 kHz; Standard's top is below 7.3 kHz. |
| *a burst puts almost no energy where people hear* | A faded Silent burst's energy below 16 kHz, from a Hann-windowed DFT misaligned with the symbols, is under −40 dB (printed: −59.9 dB). |
| *a text arrives in every near-ultrasonic scenario* | "Meet at gate 3" (21 B, one Silent frame) on Silent in `ultra desk`, `ultra hand`, `chatter` and `crowd`, seed 7. |
| *silent robust carries a longer message through a crowd* | A 59-byte text on Silent Robust in `crowd`, seed 13. |
| *odd tone counts pack bytes across symbols losslessly* | A 51-byte codeword on the one-tone Silent codec takes 102 symbols, decodes exactly with every byte's reliability above 0.9, and its marker scores above 400. |

Profile geometry printed in the latest run:

| Profile | Tones × frames | Symbol | Block | Parity (corrects) | Frame | Net rate |
|---|---|---|---|---|---|---|
| Rugged | 6 × 6 | 139 ms | 32 B | 20 B (10) | 2.97 s | 10.8 B/s |
| Safe | 6 × 4 | 93 ms | 48 B | 24 B (12) | 2.65 s | 18.1 B/s |
| Standard | 8 × 4 | 93 ms | 64 B | 24 B (12) | 2.37 s | 27.0 B/s |
| Fast | 8 × 3 | 70 ms | 64 B | 24 B (12) | 1.79 s | 35.8 B/s |
| Silent Robust | 1 × 3 | 70 ms | 24 B | 16 B (8) | 7.15 s | 3.4 B/s |
| Silent | 1 × 2 | 46 ms | 24 B | 16 B (8) | 4.78 s | 5.0 B/s |

Transfer results printed in the latest run (2026-09-28). Text envelopes are now 7 bytes plus the text, and the room simulator now resamples with cubic rather than linear interpolation, so several rows changed from the 2026-09-27 run:

| Measurement | Result |
|---|---|
| Frames recovered of 16, Rugged | easy 16, room 12, noisy room 16 |
| Frames recovered of 16, Safe | easy 16, room 13, noisy room 16 |
| Frames recovered of 16, Standard | easy 16, room 12, noisy room 7 |
| Frames recovered of 16, Fast | easy 16, room 1, noisy room 0 |
| Text on Standard, `room` | 81 B in 4.7 s (17.1 B/s) |
| 415 B in `room` | Rugged 41.6 s (10.0 B/s), Safe 26.5 s (15.7 B/s), Standard 18.9 s (21.9 B/s), Fast 14.3 s (29.0 B/s) |
| Safe, `noisy room` | 26 B in 5.3 s |
| Rugged, `hostile` | 10 B in 5.9 s |
| Silent, each near-ultrasonic scenario | 21 B in 9.6 s (one burst of 2 frames) |
| Silent Robust, `crowd` | 59 B in 28.6 s |

The frame-recovery row uses one seed per scenario, and the random multipath taps differ between scenarios, so a single cell (such as Rugged doing better in `noisy room` than in `room`) says little on its own. The ordering between profiles is the meaningful part.

**`acoustic_modem_test.dart` (9 tests)** drives the whole `AcousticFountainModem` exactly as the channel wires it: the sender produces WAV bytes, the test strips the 44-byte header, runs the room simulator, and quantises the result to PCM16 again before the receiver sees it.

| Test | What it checks |
|---|---|
| *a text message survives speaker, room and microphone* | Standard in `room` (printed: 75 B in 1 burst). |
| *rateless sender stops as soon as the receiver has enough* | A one-block message in `easy` finishes in at most 3 bursts. |
| *every audible profile completes a loopback in a normal room* | 220 bytes on every audible profile in `room`, seed 31. |
| *a file spanning many bursts completes in a noisy room* | 1200 bytes on Safe (K = 25) in `noisy room`; `bursts × 4` must stay below `AcousticFountainModem.symbolBudget(K)`, which is `max(6K, K + 24)`. Printed: 7 bursts. |
| *receiver finds the sender's profile without being told* | One listening receiver hears Rugged, Silent, Standard and Safe messages in turn; `rxProfile` is `null` before and after each message. |
| *silent text round-trips through a hand-held loopback* | "SOS" (a 10-byte envelope) on Silent through `ultra hand`, heard by a receiver listening for every profile. Printed: 1 burst, 4.78 s per frame. |
| *fixed-profile receiver ignores other profiles* | A Standard receiver with `autoDetectProfile: false` repairs no frames from a Rugged sender. |
| *changing profile mid-listen restarts the receiver cleanly* | Switching profile while listening stops the receiver and does not throw on the next audio. |
| *pcm16 conversion round-trips within quantisation error* | `pcm16ToFloat32` is within `2 / 32767` of the source. |

**`acoustic_live_tone_test.dart` (7 tests)** covers the live frequency readout. The sender side must describe exactly what is played, and the receiver side must name the right frequency.

| Test | What it checks |
|---|---|
| *describes exactly the samples encode writes* | For a 29-byte payload on all six profiles, `MtFskCodec.describe` produces a `ToneTimeline` whose `totalSamples` equals `encode(payload).length`, starting with a marker, ending with data, and returning `null` past the end. |
| *merges consecutive silences and looks up by time* | Two silences in a row become one segment; `atTime` and `duration` agree at 1000 samples per second. |
| *timeline matches each Standard burst* / *each Silent burst* | With `onBurst`, every burst's timeline length equals the WAV's sample count (`(bytes − 44) / 2`). Data segments carry `groups` tones (8 for Standard, 1 for Silent) and markers 2 tones on Audible and 1 on Silent, all inside the codec's `lowestHz`…`highestHz`. |
| *finds a silent-band tone within a few hertz* | A pure 18 906 Hz sine gives exactly one peak, within 8 Hz, above −30 dBFS. |
| *resolves every tone of an audible chord* | Four tones between 1.9 and 5.1 kHz give four peaks, each within 12 Hz. |
| *reports nothing for silence and after reset* | No peaks before the ring is full, and none after `reset`. |

### 3.5 Reed-Solomon

`reed_solomon_test.dart` (9 tests) covers the GF(256) code used inside every Sound frame; the maths is in [REED_SOLOMON.md](../algorithms/REED_SOLOMON.md).

| Test | What it checks |
|---|---|
| *clean codeword decodes unchanged* | Parity 16, data lengths 1 to 100 in steps of 7. |
| *repairs up to the correctable limit, every position* | Parity 4, 8, 16 and 32; 60 trials each with exactly `correctableBytes` random errors. |
| *errors in parity bytes are repaired too* | 10 errors confined to the parity bytes at parity 20. |
| *rejects damage beyond the limit rather than returning garbage* | 9 errors at parity 8 (corrects 4), 400 trials; wrong payloads must be returned in fewer than 5% of trials. The frame CRC catches the rest. |
| *burst errors are repaired* | A 12-byte burst at parity 24. |
| *single byte payload and maximum payload both work* | A 1-byte payload and `maxDataLength()` at parity 10. |
| *rejects a codeword of the wrong length* | A 4-byte input at parity 8 returns `null`. |
| *repairs errors plus erasures whenever 2e + f fits the parity* | Every split of 2e + f = parity for parity 4, 8, 16, 20 and 24, sometimes flagging a byte that is actually intact. |
| *erasures double how many known-bad bytes can be fixed* | 18 damaged bytes at parity 20 fail without erasure hints and succeed with them. |

### 3.6 Protocol, transport, state machine and adaptive engine

| File | Tests | What it checks |
|---|---|---|
| `protocol_test.dart` | 4 | `computeCrc32` is consistent and `verifyCrc32` detects a flipped byte; `PacketCodec` round-trips a header and payload; a packet with a flipped last byte decodes to `null`. |
| `state_machine_test.dart` | 2 | `TransferStateMachine` accepts idle → discovering → testingChannels → negotiating → transferring → degraded → switchingChannel → recovering → transferring → completed, with a history of 9 entries; idle → transferring throws `StateError`. |
| `adaptive_engine_test.dart` | 3 | `selectBestChannel` picks optical (19/20 received, 18 000 throughput, 80 ms, confidence 0.9, stability 0.85) over acoustic (17/20, 9000, 130 ms, 0.75, 0.7). `shouldSwitch(0.70, 0.71)` and `shouldSwitch(0.85, 0.90)` are false, `shouldSwitch(0.60, 0.82)` is true. `isDegraded(0.50)` is true and `isDegraded(0.80)` is false. |

The scoring and hysteresis rules behind these numbers are described in [ADAPTIVE_ENGINE.md](../algorithms/ADAPTIVE_ENGINE.md).

### 3.7 Broadcast mode

`broadcast_mode_test.dart` (3 tests) uses a stub optical channel (`_StubChannel`, defined in the test) registered with a real `ChannelManager`:

- *broadcast is default in hardware TransferManagerConfig*: `TransferManagerConfig(mode: OperationMode.hardware).transferMode` is `TransferMode.broadcast`.
- *sender completes without ACK in broadcast mode*: with `broadcastMode: true` and a window of 2, `ReliableTransport` transmits every packet exactly once, finishes, and never records an ACK (`lastAckedSequence == 0`).
- *receiver deduplicates sequence numbers*: handing the same decoded packet to `handleReceivedPackets` twice returns an ACK both times and counts one duplicate.

### 3.8 Simulation integration

`simulation_integration_test.dart` (3 tests) runs scenarios from `lib/core/simulation/scenarios.dart` through the real `SimulationOrchestrator`, `ReliableTransport` and `SimulatedMedium`. Only byte-exact delivery (`dataMatch`) is asserted; the chosen channel and the number of switches are not checked.

| Test | Scenario | Data size | Timeout |
|---|---|---|---|
| *optical always good scenario completes* | `optical-always-good` | 1024 bytes (the scenario's own size is 4096) | 30 s |
| *acoustic always good scenario completes* | `acoustic-always-good` | 4096 bytes (the scenario's size) | 2 min |
| *random loss scenario completes with retransmission* | `random-loss` | 1024 bytes (the scenario's own size is 4096) | 60 s |

The other six scenarios (`optical-degrades`, `burst-loss`, `both-degrade`, `acoustic-recovers`, `repeated-degradation`, `vibration-coupled`) have no automated test. See [SIMULATION_LAB.md](SIMULATION_LAB.md) for what each scenario does.

### 3.9 Media: samples, gallery and image envelope

| File | Tests | What it checks |
|---|---|---|
| `sample_media_test.dart` | 2 | `SampleMedia.fromAssetPath` parses `how_qr_codes_work_140kb.mp4` into the title "How QR codes work", a 140 KB budget, type video and `video/mp4`, maps `.webm` to `video/webm`, and returns `null` for `assets/other/x.jpg` and `assets/samples/notes.txt`. `loadSampleMediaCatalog` returns images and videos with an image first, and every bundled asset loads and is no larger than its budget × 1024 bytes. |
| `gallery_saver_test.dart` | 2 | `GallerySaver.canSave` accepts only non-empty images and videos. On the desktop test host `isSupported` is false, `save` returns false, and nothing is marked as saved or saving. |
| `image_envelope_test.dart` | 1 | Described in [section 3.2](#32-light-frame-format-and-qr-round-trip). |

`GallerySaver.isSupported` uses `dart:io` (`Platform.isAndroid || Platform.isIOS`), so it is false on the Windows test host and the real `gal` plugin is never called.

### 3.10 Platform and physical-only policy

| File | Tests | What it checks |
|---|---|---|
| `physical_only_test.dart` | 3 | `CommChannelId` has exactly three values (`optical`, `acoustic`, `vibration`); `excludedNetworkTransports` mentions Internet, Wi-Fi and Bluetooth; `physicalOnlyPolicySummary` contains "no internet" and "physical". |
| `platform_capabilities_test.dart` | 2 | `isVibrationSupported` equals `isHardwarePlatform`, and if the platform counts as hardware then physical channels and vibration are reported as supported; the capability label, summary and pairing steps are non-empty. |

Under `flutter test`, Flutter reports the target platform as Android even on a Windows host (the SDK checks the `FLUTTER_TEST` environment variable). `isHardwarePlatform` is based on `defaultTargetPlatform`, so it is **true** in tests, and the first test always takes its "hardware" branch. The comment in the test that says both flags may be false does not describe what actually happens.

### 3.11 Widget test

`widget_test.dart` (1 test) pumps `AdaptiveCommApp` on a 400 × 800 surface and checks that the home screen shows `HomeScreen.appName`, a **Send** entry and a **Receive** entry, and does **not** show "Simulation Lab" (the lab is reached through the developer menu instead). No other screen is exercised by a widget test.

---

## 4. The simulators explained

Both simulators live in `test/` and are used only by tests. They are deterministic: the same seed produces the same output.

### 4.1 Camera simulator (`optical_camera_sim.dart`)

`renderCameraFrame(bitmap, d, rng)` returns a square luminance frame `(width, height, lum)` showing the QR `bitmap` as a phone camera would record it when pointed at another phone's screen under the degradation `d`. The frame goes straight into the production decoder `decodeQrBytesFromLuminance`. Each call draws a fresh random pose within the tier's limits, so running many frames measures a decode *rate* rather than one lucky pose.

`CameraDegradation` parameters and the three built-in tiers (`CameraDegradation.tiers` is `[good, typical, hard]`):

| Parameter | What it models | Default | `good` | `typical` | `hard` |
|---|---|---|---|---|---|
| `framePx` | Side of the square luminance frame handed to the decoder, in pixels | 720 | 720 | 720 | 720 |
| `qrFraction` | Size of the QR (including its quiet zone) as a fraction of the frame side; smaller means the camera is further away | 0.5 | 0.62 | 0.5 | 0.42 |
| `rotationDeg` | Maximum in-plane rotation of the phone, drawn uniformly in ± this value | 0 | 4 | 8 | 12 |
| `skew` | Keystone (perspective) strength: each corner moves by up to this fraction of the QR side | 0 | 0.03 | 0.06 | 0.08 |
| `blurSigma` | Gaussian blur in pixels (defocus) | 0 | 0.7 | 1.1 | 1.5 |
| `motionBlurPx` | Length of a linear motion-blur streak in a random direction (hand shake) | 0 | 0 | 1 | 2 |
| `black` | Luminance the camera records for a dark module | 20 | 35 | 60 | 80 |
| `white` | Luminance the camera records for the white screen | 235 | 220 | 205 | 195 |
| `gamma` | Tone-curve exponent; below 1 lifts the darks, like a washed-out bright screen | 1 | 0.9 | 0.8 | 0.7 |
| `noiseSigma` | Standard deviation of Gaussian sensor noise, in luminance levels | 0 | 3 | 6 | 8 |
| `glare` | Peak brightness of a soft glare hotspot at a random spot, as a fraction of `white` | 0 | 0 | 0.1 | 0.2 |
| `quietModules` | White margin the sender draws around the code, in modules | 4 | 4 | 4 | 4 |

The code describes the tiers as "Well aimed, steady, bright screen" (`good`), "code fills about half the view, hand-held" (`typical`) and "Too far away, some shake, washed out" (`hard`).

Two helpers derive new tiers:

- `zoomed(zoom)` multiplies `qrFraction` by `zoom` and appends, for example, ` x1.5` to the label. This models the receiver's camera zoom making the code cover more pixels.
- `withFrame(px)` changes `framePx` and scales both blur values by the same ratio, so the blur stays the same physical size.

The rendering pipeline, in order:

1. **Pose.** Random rotation within `rotationDeg`, the centre jittered by up to 3% of the frame, and each corner offset by up to `skew` of the QR side.
2. **Projection.** A homography maps every output pixel back to module coordinates. The scene includes the portrait phone screen (white above and below the code, a 0.6-module margin beside the quiet zone), a dark bezel, and a textured table or hand background, so the decoder sees realistic surroundings rather than a clean white field.
3. **Supersampling.** Each pixel averages a 3 × 3 grid of sub-samples, as a sensor integrates light over a pixel.
4. **Blur.** Separable Gaussian blur, then motion blur, if enabled.
5. **Tone.** `black + (white − black) × value^gamma`.
6. **Glare and noise.** A Gaussian hotspot with radius a quarter of the frame, then Box–Muller Gaussian noise.
7. **Quantisation.** Rounded and clamped to 0–255, stored in an `Int8List` as `zxing2` expects.

**What the simulator does not model.** Frame loss is not part of the simulator: the test helpers (`streamThroughCamera` in `optical_density_sweep_test.dart` and `runOpticalRoundTrip` in `fountain_qr_roundtrip_test.dart`) skip frames with a seeded random probability before rendering. "Shake" is represented only by motion blur plus the per-frame random pose. Autofocus hunting, rolling-shutter tearing, exposure changes, screen refresh flicker and moiré are not modelled.

How the tests use it:

- `measure(blockLen, d, frames, seed)` builds a random file of `blockLen × 40` bytes, renders repair symbols 50, 51, … through the camera, and counts how many decode and parse with the expected symbol index.
- `streamThroughCamera(envelope, profile, d, frameLoss, seed, maxFrames)` resolves the profile from the envelope size, uses the production session ID from `FountainQrModem.sessionIdFor`, drops frames with probability `frameLoss` (default 0.3), renders the rest, feeds the LT decoder, and reports how many frames had been shown when the file completed.

### 4.2 Room simulator (`acoustic_channel_sim.dart`)

`simulateAcoustic(clean, scenario:, leadSilence = 1777, seed = 1, sampleRate = 44100)` turns the clean transmitted waveform into what a microphone would hear. The code's comment explains the design: narrowband tone detection has a large processing gain, so white noise alone tells you little. What actually breaks multi-tone FSK is frequency-selective multipath, speaker and microphone roll-off, and sample-clock drift between the two phones, so the model concentrates on those.

`AcousticScenario` parameters:

| Parameter | What it models |
|---|---|
| `snrDb` | Signal-to-noise ratio of the added background noise, measured against the signal after multipath, reverb and roll-off |
| `reverbTail` | Room reverberation: six echoes 35 ms apart, echo k having gain `reverbTail^k` |
| `rolloffStages` | Number of cascaded one-pole low-pass filters (`alpha = 0.35`), modelling cheap speakers and microphones that lose the high tones; one stage is about −3 dB at 3.1 kHz |
| `clockDriftPpm` | Sample-clock mismatch between sender and receiver, applied by stretching the signal with Catmull-Rom (cubic) interpolation. Linear interpolation would knock about 6 dB off a 19 kHz tone. |
| `multipathTaps` | Number of discrete reflections, each with a random delay of 40 to 1239 samples (about 1 to 28 ms) and a random gain of ±0.2 to ±0.9 |
| `wobblePpm` (default 0) | Peak of a time-varying clock ratio at about 1 Hz: the Doppler of a hand-held phone. 600 ppm is about 0.2 m/s. |
| `chatterSnrDb` (default none) | Signal-to-babble ratio of three simulated talkers: harmonic series on gliding 100–250 Hz fundamentals, energy up to 5 kHz, gated at a syllable rate |
| `micGain` (default 1.0) | Level the signal reaches the ADC at, applied before noise, so loud chatter has headroom instead of clipping |

The four scenarios, verified against the code:

| Scenario | `snrDb` | `reverbTail` | `rolloffStages` | `clockDriftPpm` | `multipathTaps` | Description in the code |
|---|---|---|---|---|---|---|
| `easy` | 20 | 0.15 | 0 | 0 | 0 | Two phones on a desk, quiet room |
| `room` | 12 | 0.35 | 2 | 50 | 3 | Across a table in a normal room |
| `noisyRoom` (name `noisy room`) | 6 | 0.45 | 4 | 200 | 5 | Background chatter, further apart, reverberant |
| `hostile` | 2 | 0.55 | 6 | 400 | 7 | Loud room, phones a few metres apart, cheap speaker, badly mismatched sample clocks |

`AcousticScenario.all` is `[easy, room, noisyRoom]` and `allIncludingHostile` adds `hostile`. No test iterates over `allIncludingHostile`; `hostile` is used only by the Rugged test.

Four near-ultrasonic scenarios form `AcousticScenario.ultra`. None has roll-off stages: at 19 kHz what matters is how weak the tone arrives relative to the microphone's own noise, which `snrDb` already expresses.

| Scenario | `snrDb` | `reverbTail` | `clockDriftPpm` | `multipathTaps` | Extra |
|---|---|---|---|---|---|
| `ultraDesk` (name `ultra desk`) | 10 | 0.2 | 80 | 3 | — |
| `ultraHand` (name `ultra hand`) | 4 | 0.35 | 200 | 5 | `wobblePpm` 500 |
| `chatter` | 10 | 0.3 | 100 | 3 | `chatterSnrDb` −6, `micGain` 0.2 |
| `crowd` | 10 | 0.3 | 100 | 3 | `chatterSnrDb` −15, `micGain` 0.08 |

Processing order: clock drift and wobble, then the direct path placed after `leadSilence` samples of silence (the buffer also gets a 0.5-second tail for echoes), then the multipath taps, then the reverb echoes, then the roll-off filters, then `micGain`, then chatter, and finally noise over the whole buffer with clipping to ±1. One `Random(seed)` drives both the multipath taps and the noise.

The noise is a sum of four uniform random numbers scaled by 1.41, whose standard deviation is about 0.81 rather than 1. The effective SNR is therefore about 1.8 dB better than `snrDb` states. The scenarios are still hard, but keep this in mind when comparing them with other channel models.

How the tests use it:

- `runTransfer` in `acoustic_channel_test.dart` simulates each 2-frame burst separately with seed `seed + nextSymbol` and a lead silence of `1200 + (nextSymbol × 37) % 900` samples, so every burst meets different reflections and a different start offset.
- `loopback` in `acoustic_modem_test.dart` simulates each modem burst with seed `seed + bursts` and the default lead silence of 1777 samples.

---

## 5. Writing new tests

These conventions are what the existing tests already do.

| Convention | What the existing tests do |
|---|---|
| File naming | One file per area, named `test/<topic>_test.dart`. Helpers that contain no tests drop the `_test` suffix (`optical_camera_sim.dart`, `acoustic_channel_sim.dart`) so the runner does not treat them as test files. |
| Test naming | Names are plain sentences describing the behaviour that must hold, for example *photo survives with 30% of frames dropped* or *rejects damage beyond the limit rather than returning garbage*. Related tests share a `group(...)` named after the class or area (`ReedSolomon`, `acoustic modem`, `optical round trip (QR byte mode + zxing + LT)`). |
| Determinism | Every random source is seeded: `Random(7)`, `Random(seed)`, the `seed:` argument of `simulateAcoustic`, the `rng` passed to `renderCameraFrame`. Test data is either seeded random bytes or a formula such as `(i * 37 + 11) & 0xFF`. A failing seed then reproduces exactly. |
| Failure messages | Loops over profiles, seeds or trials pass a `reason:` naming the case, for example `reason: '${profile.label} failed'` or `reason: 'K=$k symbol $i'`. |
| Helper reuse | Light tests reuse `renderCameraFrame`, `buildQrBitmap`, `rasterizeQrBitmap` and `decodeQrBytesFromLuminance`. Sound tests reuse `simulateAcoustic` and the `runTransfer` or `loopback` pattern. Copy those patterns rather than writing a new pipeline. |
| Production code paths | Tests call the same functions the app uses (for example the production QR decoder, `FountainQrModem.sessionIdFor`, `OpticalTxProfile.resolveFor`, `AcousticFountainModem`) instead of re-implementing them. |
| Measure, then assert a floor | Heavy tests print what they measured and assert a threshold with margin (for example a 90% floor where 100% was measured). Printing uses `print` with a `// ignore: avoid_print` comment on the line before, rather than disabling the lint globally. |
| Timeouts | Camera-model tests set `timeout: const Timeout(Duration(minutes: 5))`, the full sweep uses 30 minutes, and the simulation tests set 30 s, 60 s or 2 minutes. The two Sound files set none and rely on the default. |
| Slow reports | Anything that takes minutes is skipped unless an environment variable is set, following `OPTICAL_SWEEP`: `skip: Platform.environment['OPTICAL_SWEEP'] == null ? 'set OPTICAL_SWEEP=1 to print the full table' : null`. |
| Headless | No test touches a camera, microphone, speaker, vibration motor, sensor, file picker or network. Plugin-backed classes are either replaced by a stub (`_StubChannel` in `broadcast_mode_test.dart`) or only tested for their host-independent logic (`GallerySaver.canSave`). New tests should stay headless so `flutter test` keeps working on any development machine and in CI. |

Before committing, run the new file on its own, then the whole suite, then `flutter analyze`.

Two host behaviours to keep in mind:

- `defaultTargetPlatform` is Android inside `flutter test`, so code that branches on it takes its mobile path, while code that checks `dart:io`'s `Platform` sees Windows (or whatever the host is).
- `SimulatedMedium` creates an unseeded `Random()`, so Simulation Lab transfers are not reproducible run to run. Assert only outcomes that hold for every run, as `simulation_integration_test.dart` does with `dataMatch`.

---

## 6. Device test checklist

The automated suite cannot replace two real phones. Install the same build on both (older builds use an earlier APCF frame version and are rejected on purpose), and use a fresh install at least once so the permission prompts appear. Record the phone models, OS versions, distances and times for every run.

### 6.1 Light

| Check | Steps | Pass criteria |
|---|---|---|
| Auto, short text | Send a short text over Light with the Auto profile; hold the receiver about 15–25 cm away with the QR inside the viewfinder square | The text arrives exactly |
| Safe profile | Repeat with Safe | Completes; slower than Auto, but more tolerant of distance and shake |
| Fast profile | Repeat with Fast from close range with a steady hand | Completes; note whether it fails where Auto and Safe succeed |
| 2 KB photo | Pick a 2 KB sample photo (for example `cat_sketch_2kb.jpg`) and send on Auto | Arrives intact and opens full screen; time is close to the on-screen estimate |
| 5 KB photo | Repeat with a 5 KB sample (for example `cat_sketch_5kb.jpg`) | Arrives intact |
| Video | Send a sample video (for example `countdown_beeps_30kb.mp4`, or `speed_of_light_80kb.webm` for a longer run) | Plays on the receiver; record the time |
| Frame loss | Cover the sender's screen with a hand for 2–3 s mid-transfer | Progress pauses and then continues; the file still completes |
| Resume streaming | Stop the sender before the receiver finishes, then tap **Resume streaming** | The receiver keeps its progress and completes |
| Multiple receivers | Point two or more receivers at one sender | Every receiver completes independently |

### 6.2 Sound

Run each Audible profile (Rugged, Safe, Standard, Fast) at two distances, then both Silent profiles at arm's length.

| Check | Steps | Pass criteria |
|---|---|---|
| Close range | Send a short text with the speaker facing the receiver's microphone at 20–50 cm, once per profile | Every profile delivers the message |
| Across a room | Repeat at 1–2 m | Record which profiles still work; Rugged and Safe should reach further than Fast |
| Profile auto-detection | Send consecutive messages at different profiles without touching the receiver | The receiver shows the correct profile each time and delivers each message |
| Background noise | Play speech or music nearby and send on Rugged | The message still arrives, possibly more slowly |
| Multiple receivers | Two receivers listen to one sender | Both receive the message |
| Silent band | Send "sos" on Silent at 20–50 cm with media volume at maximum, then swap roles | Nothing audible to most adults; the receiver's *Silent band 18–20 kHz* meter rises and the message arrives. Record any phone pair that fails in one direction |
| Live readout, sender | Watch **Sending now** during an Audible and a Silent send | Audible shows a range such as *1.94–6.80 kHz · 8 tones at once*; Silent shows one tone between 18.3 and 19.9 kHz; *Sync marker* and *Gap between frames* appear briefly; the readout disappears on **Stop** |
| Live readout, receiver | Watch **Hearing now** on the receiver during the same sends, then in a quiet room | During a send it follows the sender's kHz to within about ±20 Hz; in a quiet room it shows **—**; whistling or a tone app shows that frequency |

### 6.3 Vibration

| Check | Steps | Pass criteria |
|---|---|---|
| Phones touching | Send a very short text (two or three characters) with the phones pressed firmly together | The message arrives; record the time, since this channel is very slow |
| Loose contact | Repeat with the phones barely touching | Expect failure or slow progress; this documents the limit rather than a bug |

Vibration is contact-only and one-to-one; the app's pairing steps state that it is not supported for broadcast.

### 6.4 Gallery auto-save

| Check | Steps | Pass criteria |
|---|---|---|
| Automatic save | Receive a photo and a video | The status reports the save and both appear in the **Adaptive Comm** album |
| No duplicates | Leave and reopen the received item, then save again | Only one copy exists (saves are tracked per message ID) |
| iOS video format | Receive the `.webm` sample on an iPhone | Record the result; MP4 samples are the safer choice for iOS Photos |

### 6.5 Permissions denied

| Check | Steps | Pass criteria |
|---|---|---|
| Camera denied | Deny the camera prompt on the first Light receive | The app explains the problem and does not crash; allowing it later (or in system settings) makes Light receive work |
| Microphone denied | Deny the microphone prompt on the first Sound receive | The app explains the problem and does not crash; allowing it later makes Sound receive work |
| Storage or photos denied | Deny gallery access when the first photo is saved (where the OS asks) | The received item still displays, the save reports an error, and no crash occurs |
| No network | Enable airplane mode on both phones | Every channel still works, as the physical-only policy requires |

---

## 7. Coverage gaps

The following are not exercised by any automated test. They are the main reason the device checklist exists. Known defects are tracked separately in [KNOWN_ISSUES.md](../project/KNOWN_ISSUES.md).

| Area | What is not tested | Where the logic lives |
|---|---|---|
| Real hardware | Actual cameras, screens, speakers, microphones, vibration motors and accelerometers. The simulators approximate them but omit autofocus, rolling shutter, automatic gain control, echo cancellation and per-phone frequency response. | Plugins `camera`, `record`, `audioplayers`, `vibration`, `sensors_plus` |
| Hardware channel classes | `HardwareOpticalChannel`, `HardwareAcousticChannel` and `HardwareVibrationChannel` are never instantiated by a test; the broadcast tests use a stub channel instead. | `lib/core/channels/` |
| Light sender timing | `FountainQrModem`'s display loop, frame rate and screen brightness control. Only its `sessionIdFor` helper is used by a test. | `lib/core/physical/fountain/fountain_qr_modem.dart` |
| Platform channels and permissions | The `apcs/optical_display` method channel, `permission_handler` requests and their denied paths, and wake-lock handling. | `lib/core/platform/`, channel classes |
| Gallery write path | The `gal` plugin calls and the album write on a real OS; the test host reports `isSupported == false`, so only `canSave` is really exercised. | `lib/core/media/gallery_saver.dart` |
| Vibration end to end | Only `VibrationBitCodec` bit and pulse mapping and threshold checks are tested; there is no vibration channel simulator and no end-to-end vibration transfer test. | `lib/core/physical/physical_codecs.dart`, `lib/core/channels/vibration_channel.dart` |
| UI flows | Only the home screen is pumped. Send compose, send transmit (including **Resume streaming**), receive, the developer menu, the Simulation Lab and Performance screens, and the received-content view have no widget tests. | `lib/ui/screens/`, `lib/ui/widgets/` |
| Live readout on a device | `LiveToneMeter` is never pumped, and nothing checks the sender's clock against real playback. The sender starts its clock when `AudioPlayer.play()` returns, so output latency (tens of milliseconds, more over Bluetooth) makes **Sending now** run slightly ahead of the sound. The receiver path is only tested through `SpectrumAnalyzer` on synthetic tones. | `lib/ui/widgets/live_tone_meter.dart`, `HardwareAcousticChannel._playWav` |
| Simulation scenarios | Six of the nine scenarios, and channel choice or switch counts in the three that are tested. Simulation results are also non-deterministic because `SimulatedMedium` uses an unseeded `Random()`. | `lib/core/simulation/` |
| Performance Comparison | `PerformanceComparator` and its strategies have no test. | `lib/core/performance/` |
| Web build | Nothing runs in a browser; the `FQR3:` string path is tested only as a codec. | `web/`, `lib/core/physical/fountain/qr_fountain_frame.dart` |
| Full density table | Skipped in normal runs; it only runs when `OPTICAL_SWEEP` is set. | `test/optical_density_sweep_test.dart` |
| Platform branches | Because `flutter test` reports Android as the target platform, the non-hardware branch of `platform_capabilities_test.dart` is never taken, and platform-specific behaviour on iOS, web and desktop is not checked. | `lib/core/platform/platform_capabilities.dart` |

Some test names also promise slightly more than they assert: *Standard profile recovers ~365 KB with 25% frame loss* uses a 20% loss probability, *overhead stays under two symbols for every K a camera will see* asserts a mean below 2.5 rather than 2, and *frame recovery rate per scenario* prints results without asserting any.
