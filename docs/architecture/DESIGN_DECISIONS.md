# Design Decisions

A record of the major technical decisions: the context, the options considered, what was chosen and why, and the consequences. Each record uses the Architecture Decision Record (ADR) format. When you change one of these decisions, add a new record rather than silently editing an old one.

Back to the [documentation index](../README.md).

---

## Index

| # | Decision | Status |
|---|---|---|
| [ADR-01](#adr-01-physical-channels-only) | Physical channels only | Accepted |
| [ADR-02](#adr-02-rateless-fountain-coding-for-light-and-sound) | Rateless fountain coding for Light and Sound | Accepted |
| [ADR-03](#adr-03-replace-robust-soliton-with-cycleddensesparse-rows-and-an-exact-decoder) | Replace robust soliton with cycled/dense/sparse rows and an exact decoder (APCF v3) | Accepted, supersedes the v2 mapping |
| [ADR-04](#adr-04-raw-qr-byte-mode-instead-of-base64-text) | Raw QR byte mode instead of base64 text | Accepted |
| [ADR-05](#adr-05-sparse-qr-codes-and-auto-density) | Sparse QR codes and Auto density | Accepted, supersedes the 800 B default |
| [ADR-06](#adr-06-qr-error-correction-level-l-and-fixed-mask-0) | QR error-correction level L and fixed mask 0 | Accepted |
| [ADR-07](#adr-07-camera-tuned-for-screens-zoom-exposure-y-plane-single-isolate) | Camera tuned for screens: zoom, exposure, Y plane, single isolate | Accepted |
| [ADR-08](#adr-08-zxing2-decode-sequence-globalhistogram--purebarcode--hybrid) | zxing2 decode sequence: GlobalHistogram → pureBarcode → Hybrid | Accepted |
| [ADR-09](#adr-09-content-derived-light-session-ids-and-resume) | Content-derived Light session IDs and Resume | Accepted |
| [ADR-10](#adr-10-multi-tone-fsk-for-sound) | Multi-tone FSK for sound | Accepted, supersedes two-tone FSK |
| [ADR-11](#adr-11-reed-solomon-per-frame-with-soft-decision-erasures) | Reed-Solomon per frame with soft-decision erasures | Accepted |
| [ADR-12](#adr-12-per-frame-sync-marker-with-leading-edge-detection) | Per-frame sync marker with leading-edge detection | Accepted |
| [ADR-13](#adr-13-receiver-auto-detects-the-sound-profile) | Receiver auto-detects the Sound profile | Accepted |
| [ADR-14](#adr-14-no-back-channel-sender-streams-until-stopped) | No back-channel: sender streams until stopped | Accepted |
| [ADR-15](#adr-15-extend-dont-overwrite-legacy-modems-stay) | Extend, don't overwrite: legacy modems stay | Accepted |
| [ADR-16](#adr-16-single-controller-plus-fine-grained-notifiers) | Single controller plus fine-grained notifiers | Accepted |
| [ADR-17](#adr-17-headless-simulators-before-hardware) | Headless simulators before hardware | Accepted |
| [ADR-18](#adr-18-photos-compressed-to--120-kb-bundled-demo-samples) | Photos compressed to ≤ 120 KB; bundled demo samples | Accepted |
| [ADR-19](#adr-19-automatic-gallery-saving-with-gal) | Automatic Gallery saving with `gal` | Accepted |

---

## ADR-01: Physical channels only

**Context.** The project's goal is communication with no radio or network infrastructure: air-gapped, radio-silent, emergency and demonstration settings.

**Decision.** Only three channels exist: optical (screen → camera), acoustic (speaker → microphone) and vibration (motor → accelerometer). `platform_capabilities.dart` lists the excluded transports (Internet/IP, Wi-Fi, Bluetooth, NFC, cellular/SMS, cloud), and `test/physical_only_test.dart` checks that exactly three physical channels exist. The Android release manifest requests no `INTERNET` permission.

**Consequences.** Throughput is low compared with radio. The app can never "cheat" by falling back to a network, so every result is a genuine physical-channel result.

---

## ADR-02: Rateless fountain coding for Light and Sound

**Context.** A screen can't hear a camera and a speaker has no reliable return path. With a "send each chunk once, then repeat" carousel, a receiver that misses chunk 7 of 40 must wait a whole cycle to see it again. The expected time to collect all N chunks at loss rate p grows like a coupon-collector problem.

**Options.**
1. Repeating carousel of numbered chunks (the old APCS1 text QR).
2. Carousel plus per-chunk ACK over another channel (needs a return path).
3. **Fountain (LT) code**: an endless stream of distinct encoded symbols, any K of which (plus a few) decode.

**Decision.** Option 3, systematic LT, shared by Light and Sound (`lt_codec.dart`).

**Consequences.**
- Lost frames don't matter; only the count of good ones does.
- One-to-many broadcast works with no coordination.
- Receivers can join mid-stream.
- The sender can't know when to stop (see ADR-14).
- The same codec serves both channels, which follows the reuse rule.

---

## ADR-03: Replace robust soliton with cycled/dense/sparse rows and an exact decoder

**Context.** The first fountain used the classic robust-soliton degree distribution with a peeling decoder. Field reports showed transfers "stuck at 1 / 3 symbols". Measurement showed that at small K the robust soliton's spike put about **47%** of repair symbols on the *same* all-blocks equation (K = 3). Only **56%** of random K+2 symbol sets for K = 1…10 were full rank, and a 3-block transfer completed from five distinct repair symbols only **69%** of the time.

**Decision (APCF v3).**
- **Systematic** first K symbols.
- **K ≤ 8:** cycle through a session-keyed shuffle of all 2ᴷ−1 non-empty subsets, so no equation repeats within a cycle.
- **9 ≤ K ≤ 256:** uniformly random dense rows (each block with p = ½).
- **K > 256:** fixed weight `min(K/2, ⌈2 ln K⌉ + 8)`.
- **Exact incremental Gauss–Jordan decoder** over GF(2): it completes the moment rank reaches K.
- The frame **version byte was bumped to 3** so old v2 frames can't be decoded into garbage.

**Consequences.** Mean overhead is 0–2.2 symbols across K = 1…600 at 40% loss; K = 3 always completes from 5 consecutive repair symbols. The cost is O(K²/32) word operations per symbol in the dense regime, which is trivial at the K values used (≤ ~1 000). See [Fountain Code](../algorithms/FOUNTAIN_CODE.md).

---

## ADR-04: Raw QR byte mode instead of base64 text

**Context.** The first QR transport encoded binary chunks as base64 text, which costs 33% capacity and forces a denser QR for the same payload.

**Decision.** Encode APCF frames in true QR **byte mode** (`QrCode.fromUint8List`) and read the raw byte segment back from zxing2. A text form (`FQR3:` + base64url) remains only for the string-only web preview sampler.

**Consequences.** 25% fewer bytes inside each QR for the same payload (base64 turns 3 bytes into 4 characters), hence smaller QR versions and higher decode rates.

---

## ADR-05: Sparse QR codes and Auto density

**Context.** The old default was 800 B per frame (QR v20, 97×97 modules). In the field it produced "DEC 2.0/s from CAP 18 fps" (≈11% decode rate).

**Investigation.** A camera simulator (`test/optical_camera_sim.dart`) rendered QR frames with perspective, blur, motion blur, washed-out contrast, glare, noise and a bezel. A density sweep with the production decoder gave, in the "typical" hand-held tier: 160 B **100%**, 240 B **94%**, 330 B **81%**, 600 B **31%**, 800 B **13%**, 1 200 B **0%**. The simulator reproduced the field report almost exactly.

**Decision.**
- Default profile **Auto**: the sparsest of 160 / 240 / 330 B that keeps K ≤ 48, else 330 B.
- Safe (8 fps, 160 B), Standard (12 fps, 330 B) and Fast (12 fps, 600 B) remain as manual overrides.
- Display rate capped at **12 fps**, so each code spans at least two camera exposures at 30 fps.

**Consequences.** Effective goodput rose even though each frame carries less, because far more frames decode. Worked example: 800 B × 12 fps × 13% ≈ 1.25 KB/s, against 160 B × 12 fps × 100% × a 0.7 refresh yield ≈ 1.34 KB/s. On top of that, the sparse code keeps working in the "hard" tier, where the dense one reads 0%.

---

## ADR-06: QR error-correction level L and fixed mask 0

**Context.** Higher QR EC levels (M, Q, H) add Reed-Solomon parity inside each code, making it denser. Mask selection evaluates 8 masks with penalty rules.

**Decision.**
- **EC level L** (≈7%). Integrity comes from the APCF CRC-32, and missing or unreadable frames are absorbed by the fountain code. Extra in-code redundancy would only make the code denser, which lowers the decode rate.
- **Fixed mask pattern 0.** Searching all 8 masks cost about 15–40 ms per dense frame (a visible stutter at 12 fps) against about 4 ms fixed. Fountain payloads are pseudo-random, so all masks score about the same.

**Consequences.** The steady 12 fps cadence stays within budget; the next symbol is built while the current one is displayed.

---

## ADR-07: Camera tuned for screens: zoom, exposure, Y plane, single isolate

**Decision and rationale.**

| Choice | Why |
|---|---|
| 1280×720 (`ResolutionPreset.high`), YUV420 | Enough pixels for v8–v12 at arm's length; a cheap stream |
| **1.5× zoom** by default (chips 1×/1.5×/2×/3×) | Zoom crops the sensor *before* it is downscaled, adding real pixels per module; the user can stay at 15–25 cm where every camera focuses |
| **−0.7 EV** exposure offset | Screens are bright. A shorter exposure means less motion blur and no bloom |
| Centre focus and metering, tap to refocus | The code is in the centre; lets the user recover focus |
| Use the **Y plane** directly | It is already luminance, so there is no colour conversion; the crop is a row `memmove` |
| Centred crop of 98% of the short side | Matches the on-screen aim brackets |
| **One** long-lived decode isolate, 1 in flight | Keeps the UI thread free; with fountain symbols, dropping a frame while busy costs nothing |

---

## ADR-08: zxing2 decode sequence: GlobalHistogram → pureBarcode → Hybrid

**Context.** The sweep compared binarizers and hints. Random payload bytes occasionally form fake 1:1:3:1:1 finder patterns that outrank the true corners.

**Decision.**
1. `GlobalHistogramBinarizer` first: the fastest, and it beat Hybrid in almost every sweep cell.
2. The same bitmap with `pureBarcode`, which reads the grid from the black bounding box. It rescued **100%** of the fake-finder failures (3–8% of frames).
3. `HybridBinarizer` last, for uneven lighting.

`tryHarder` stays off: it's cheaper to drop a frame and take the next symbol.

---

## ADR-09: Content-derived Light session IDs and Resume

**Decision.** `sessionId = (CRC32(envelope) ^ blockLen·0x9E3779B1) & 0xFFFFFFFF` (0 → 1). The sender remembers the next unshown symbol index per session (last 16 sessions).

**Consequences.** Re-sending the same file at the same density *continues* the same fountain with new symbols. A receiver that got 80% of the way keeps its progress (it holds up to 3 partial sessions). Changing density creates a new session, as it must, because the block layout differs.

---

## ADR-10: Multi-tone FSK for sound

**Context.** The legacy two-tone FSK (1 800 / 3 200 Hz, 18 ms per bit) delivered about 55.6 b/s raw, had no error correction, and assumed symbol boundaries at fixed offsets from the buffer start. Microphone chunks arrive at arbitrary offsets, so windows straddled tones.

**Decision.** Multi-tone FSK in the style of ggwave: 6 or 8 simultaneous tones, each choosing 1 of 16 frequencies (4 bits). Every tone sits on an exact FFT bin of a 1 024-sample frame at 44.1 kHz (43.066 Hz spacing), so tones are orthogonal and phase-continuous. The band is about 1.2–7.2 kHz.

**Consequences.** Standard reaches 345 b/s raw and 27 B/s net *after* RS parity and sync, about 4× the old modem, with error correction. The cost is audible chords and a need for per-frame sync (ADR-12).

---

## ADR-11: Reed-Solomon per frame with soft-decision erasures

**Context.** Even in a quiet room a few percent of acoustic bytes are wrong: multipath nulls wipe out a tone. With only a checksum, nearly every frame would be discarded.

**Decision.**
- Systematic RS over GF(256) (polynomial `0x11D`) with P = 20–24 parity bytes per frame.
- Errors-and-erasures decoding (`2e + f ≤ P`).
- **GMD retries:** after a failed plain decode, erase the 4, 8, 12, … least reliable bytes (reliability = the weaker nibble margin), always keeping 4 parity bytes in reserve.
- A CRC-16 vets the result.
- **No interleaver:** RS handles bursts up to P/2 bytes directly.

**Consequences.** The hardest simulated room went from decoding nothing to passing. The parity costs 27–39% of each frame's bytes, which the measured byte error rates justify.

---

## ADR-12: Per-frame sync marker with leading-edge detection

**Decision.**
- Every frame starts with a 2-frame (46 ms) burst of both sync tones (bins 28 and 36).
- The receiver scans in 64-sample steps.
- **Marker score** = the *minimum* over the two half-windows of `2·min(P₂₈, P₃₆)/E`. An ideal aligned marker scores exactly 512; the threshold is 8.
- It then takes the **first** probe reaching 50% of the local peak, not the peak itself.
- Finally, the data start is refined by ±min(symbol/8, 512) samples to maximise tone separation.

**Why.** Scoring a single full window normalised by its own energy is scale-invariant, so a window holding the *back half* of the marker plus silence scored as well as an aligned one, and every frame locked one frame early. The two-half minimum fixes that. Reflections can be louder than the direct sound, but the direct sound always arrives first, hence the leading edge.

---

## ADR-13: Receiver auto-detects the Sound profile

**Decision.** All profiles share the same marker. The receiver runs one frame-sync per profile. The first profile whose frame passes RS, the CRC *and* the header's `blockLen` check becomes the lock. After 4 markers with no good frame the lock goes stale and all profiles are heard again. After each completed message the receiver reopens to all profiles.

**Consequences.** The receiver never has to be configured, and the sender can switch to Rugged in a noisy room with no coordination. CPU use is about four frame-syncs while hunting, then one.

---

## ADR-14: No back-channel: sender streams until stopped

**Decision.**
- **Light:** stream fresh symbols until **Stop**, with a 10-minute safety cap. The chat status is **sent**, not delivered. The result screen offers "Receiver shows DONE" and "Resume streaming".
- **Sound:** stream until Stop or a symbol budget of `max(6K, K+24)`, with a progress target of `⌈1.25K⌉ + 2`.

**Consequences.** The user decides when to stop, based on the receiver's DONE. Receivers ignore the sender's "tail" for sessions they have completed. (Known inconsistency: Sound sends are currently marked *delivered*; see [Known Issues](../project/KNOWN_ISSUES.md).)

---

## ADR-15: Extend, don't overwrite: legacy modems stay

**Decision.** The CSK light modem, the APCS1 text QR codec, two-tone FSK and on/off light keying remain in the codebase with their tests. New modems are added alongside them.

**Consequences.** There are more files, but earlier work stays reusable and testable and nothing regresses silently. The legacy modems aren't selectable in the current UI.

---

## ADR-16: Single controller plus fine-grained notifiers

**Decision.** One `AppController` (`ChangeNotifier`) owns application state. Values that change at frame or audio rate (QR bitmap, HUD metrics, meters) use dedicated singleton notifiers, so only the widgets displaying them rebuild. The QR painter repaints only when its bitmap changes and snaps modules to whole device pixels.

**Consequences.** The UI stays at display rate during streaming, the state flow stays simple, and no external state-management package is needed.

---

## ADR-17: Headless simulators before hardware

**Decision.** Every modem parameter was chosen from simulations that drive the *production* decoders:
- **Camera model:** perspective, rotation, supersampling, Gaussian and motion blur, contrast/gamma, glare, noise and bezel, in good/typical/hard tiers.
- **Room model:** clock drift, multipath, reverb tail, speaker roll-off stages and noise at a target SNR, in easy/room/noisy/hostile tiers.

**Consequences.** Design choices are reproducible and regression-tested (`flutter test`). Real devices still vary, so rehearsal on the target phones remains essential.

---

## ADR-18: Photos compressed to ≤ 120 KB; bundled demo samples

**Decision.**
- Photos are resized to a long side of ≤ 960 px, JPEG q = 78, stepping q down by 8 to ≥ 40 until ≤ 120 KB, then falling back to 640 px at q = 65.
- 16 demo photos (2/5/10/20 KB) and 9 short videos with sound (8 narrated explainers and a sync clip) ship in `assets/samples/`, generated reproducibly by `tool/` scripts with two-pass encoding to exact byte budgets.

**Consequences.** Demos need no files on the phone. Photo transfer time stays bounded (≤ ~1 minute over Light). Samples are re-compressed at send time (see Known Issues).

---

## ADR-19: Automatic Gallery saving with `gal`

**Decision.** Received photos and videos are saved automatically to the album **Adaptive Comm** via the `gal` plugin. Saving is idempotent per message ID and exposes Save / Saving… / Saved / Retry states. It needs no permission on Android 10+, `WRITE_EXTERNAL_STORAGE` (maxSdk 29) on older Android, and photo-library add permission on iOS.

**Consequences.** Users keep what they receive without extra taps. WebM can't be saved to iOS Photos.
