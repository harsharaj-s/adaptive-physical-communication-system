# Signal Processing

The signal-processing theory behind the three channels:
- **Sound:** Goertzel detection, why exact-bin tones are orthogonal, the sync marker score, processing gain, clock drift and reverberation.
- **Light:** sampling a QR code through a camera, blur and pixels per module, screen–camera timing, luminance and binarization.
- **Vibration:** baseline tracking.

Numbers come from the code; derivations are shown step by step.

Back to the [documentation index](../README.md).

---

## Contents

1. [The Goertzel algorithm](#1-the-goertzel-algorithm)
2. [Tone orthogonality](#2-tone-orthogonality)
3. [Phase continuity and clicks](#3-phase-continuity-and-clicks)
4. [Processing gain and noise](#4-processing-gain-and-noise)
5. [The sync marker score](#5-the-sync-marker-score)
6. [Leading-edge detection and multipath](#6-leading-edge-detection-and-multipath)
7. [Clock drift](#7-clock-drift)
8. [Reverberation and symbol length](#8-reverberation-and-symbol-length)
9. [Speaker and microphone response](#9-speaker-and-microphone-response)
10. [QR imaging: sampling and blur](#10-qr-imaging-sampling-and-blur)
11. [Screen–camera timing](#11-screencamera-timing)
12. [Luminance and binarization](#12-luminance-and-binarization)
13. [Vibration: baseline tracking](#13-vibration-baseline-tracking)

---

## 1. The Goertzel algorithm

Goertzel computes the power at a single DFT bin k of an L-sample block with a second-order IIR filter:

```
ω      = 2π·k / N
coeff  = 2·cos ω
s[n]   = x[n] + coeff·s[n−1] − s[n−2]          n = 0 … L−1,  s[−1] = s[−2] = 0
|X_k|² = s1² + s2² − coeff·s1·s2                s1 = s[L−1], s2 = s[L−2]
```

The code divides by L (`MtFskCodec._power`), which normalises for block length.

**Why not an FFT?** An FFT of 1 024 points gives all 512 bins in O(N log N) ≈ 10 000 butterfly operations. The demodulator needs only 16·G = 96 or 128 bins, and the marker hunt needs just 2 (bins 28 and 36). Goertzel costs one multiply-add per sample per bin and needs no windowing or buffering, so for the marker hunt it is about 100× cheaper than an FFT.

**Derivation.** The filter's transfer function H(z) = 1 / (1 − 2cos ω·z⁻¹ + z⁻²) has poles at e^{±jω}. Running L samples and then applying the FIR step y = s1 − e^{−jω} s2 gives y = e^{jω(L−1)}·X_k, whose squared magnitude expands to the formula above.

---

## 2. Tone orthogonality

Let the analysis block be N = 1 024 samples and the tones sit at integer bins k, m (k ≠ m, both < N/2):

```
x_k[n] = sin(2π k n / N)
```

Over one block:

```
Σ_{n=0}^{N−1} sin(2π k n/N) · sin(2π m n/N)
  = ½ Σ [cos(2π(k−m)n/N) − cos(2π(k+m)n/N)]
  = ½ (0 − 0) = 0            (a sum of a full-period cosine over its period is zero)
```

Each tone therefore contributes **zero** to the correlation with every other tone. In DFT terms, a tone at exactly bin k puts all its energy into bin k and none into its neighbours. There is no spectral leakage, because the block contains a whole number of cycles.

A symbol lasts F blocks (L = F·N samples). A tone at bin k of N is bin F·k of the L-point transform, and the tones remain F bins apart, so still exactly orthogonal. The longer window gives no extra resolution between tones (they are already orthogonal), but it collects F times more energy (see §4).

**The price of exact bins:** tone spacing is fixed at f_s/N = 43.066 Hz. The 16 tones of a group span 16 × 43 = 689 Hz, and 8 groups plus 2 sync tones cover about 1.2–7.2 kHz.

---

## 3. Phase continuity and clicks

Each symbol's tones start at phase 0 (`sin(step·i)` with i restarting at 0). A tone at bin k completes exactly k·F cycles in the symbol, so it ends at phase 2πkF ≡ 0. The next symbol, whatever its tones, therefore starts from the same phase state. Any tone that continues doesn't jump at all, and new tones start from zero amplitude-weighted phase.

An abrupt phase jump is a broadband click, which spreads energy across every bin and raises the noise floor for all groups. Exact bins avoid this without needing windowing or ramps.

---

## 4. Processing gain and noise

For a tone of amplitude A in white noise of variance σ², the Goertzel output over L samples has:

```
signal power  ∝ (A·L/2)²
noise power   ∝ σ²·L/2
SNR_out / SNR_in (per sample) = L/2
```

So coherent integration over a symbol gives a processing gain of **10·log₁₀(L/2)**:

| Profile | L (samples) | Gain |
|---|---|---|
| Fast | 3 072 | 31.9 dB |
| Standard / Safe | 4 096 | 33.1 dB |
| Rugged | 6 144 | 34.9 dB |

This is why tones remain decodable when the per-sample SNR is well below 0 dB. In the "hostile" simulation (2 dB broadband SNR shared across 6–8 tones plus heavy roll-off), each tone's per-sample SNR is strongly negative, yet Rugged still delivers.

**Power split.** Each tone's amplitude is 0.98/G. Going from G = 8 to G = 6 raises each tone by 20·log₁₀(8/6) = **2.5 dB**, one of Rugged's and Safe's advantages.

**Decision rule.** Per group, the largest of the 16 powers wins (a maximum-likelihood detector for non-coherent orthogonal FSK). The *margin* 1 − P₂/P₁ is a soft reliability used by GMD decoding (see [Reed-Solomon §10](REED_SOLOMON.md#10-gmd-using-the-demodulators-confidence)).

---

## 5. The sync marker score

The marker is 2 048 samples of bins 28 (1 205.9 Hz) and 36 (1 550.4 Hz) at amplitude 0.49 each.

**Per half-window** (1 024 samples):

```
E     = (1/N) Σ x[n]²                       mean-square energy
P_k   = |X_k|² / N                          Goertzel power (as normalised in code)
score = 2 · min(P28, P36) / E
```

**Ideal value.** For x[n] = A sin(ω₂₈ n) + A sin(ω₃₆ n):

```
|X_28|² = (A·N/2)²            ⇒  P28 = A²·N/4
E       = A²/2 + A²/2 = A²    (orthogonal tones: energies add)
score   = 2 · (A²·N/4) / A² = N/2 = 512
```

The score is **independent of amplitude A** (volume) and scales with N, so it measures "how tone-like" the window is rather than how loud.

**Pure noise.** For white noise of variance σ², each normalised Goertzel power is exponentially distributed with mean σ², and E ≈ σ². The minimum of two such powers has mean σ²/2, so the expected score is about **1**. Speech and music concentrate energy but rarely at both exact bins at once, and they score in the tens. The threshold **8.0** is about 64× below an ideal marker and comfortably above noise.

**Why the minimum of two halves.** Consider a window covering the *last* 1 024 samples of the marker plus 1 024 samples of silence. Its full-window score is the tone power over 1 024 samples, normalised by energy that is also from those same 1 024 samples, so it scores as high as an aligned window. With the two-half rule, the silent half has E ≈ 0 (scores 0) or pure noise (scores about 1), so the minimum is low. Only a window whose **both** halves are marker, i.e. exactly aligned (within the search step), scores high.

---

## 6. Leading-edge detection and multipath

Sound reaches the microphone by several paths: direct, plus reflections from the table, walls and ceiling, delayed by path-length difference / 343 m/s (e.g. 1 m extra ≈ 2.9 ms ≈ 129 samples). A reflection can be **louder** than the direct path (the phone's speaker may face away, or the table focuses energy).

The marker score as a function of offset forms a plateau with bumps from each echo. Taking the **peak** could lock onto a late echo, placing every symbol window hundreds or thousands of samples late. The receiver therefore:

1. Finds any probe ≥ 8.0.
2. Scans the next 2 048 samples for the peak score.
3. Returns the **first** probe ≥ 50% of that peak.

The direct path always arrives first, so the leading edge is the reliable landmark. Fine alignment (±min(L/8, 512) samples in 64-sample steps, maximising tone separation over 3 groups) then corrects the remaining offset.

---

## 7. Clock drift

The sender's DAC and the receiver's ADC run from different crystals. A mismatch of δ ppm causes:

**Timing drift** across one frame of S samples: Δ = S·δ·10⁻⁶ samples.

| Profile | Frame samples | Drift at 200 ppm | at 400 ppm |
|---|---|---|---|
| Standard | 104 448 | 21 samples | 42 samples |
| Rugged | 131 072 | 26 samples | 52 samples |

Because every frame is re-synchronised on its own marker, drift never accumulates beyond one frame. Within a frame the worst misalignment (42 samples) is only about 1% of a 4 096-sample symbol.

**Frequency offset:** Δf = f·δ·10⁻⁶. At 7.2 kHz and 400 ppm that's 2.9 Hz, about 6.7% of a bin (43 Hz). It causes slight leakage (a few percent of power) but doesn't change which tone wins.

The room simulator tests 50, 200 and 400 ppm (via linear resampling).

---

## 8. Reverberation and symbol length

After each symbol, the room's echoes keep sounding its tones for tens to hundreds of milliseconds. At the start of the next symbol's window, the previous symbol's tail is present in *other* bins of the same group and competes with the new tone.

The fraction of a window contaminated by a tail of duration T_r is roughly T_r / T_sym:

| Profile | Symbol | Share of window hit by a 35 ms early-reflection tail |
|---|---|---|
| Fast | 69.7 ms | 50% |
| Standard | 92.9 ms | 38% |
| Rugged | 139.3 ms | 25% |

Longer symbols let the new tone dominate the integrated power. That's why Rugged (F = 6) survives the "hostile" room and Fast (F = 3) is recommended only when the phones are close in a quiet room.

---

## 9. Speaker and microphone response

- **Below ~1 kHz**, tiny phone speakers produce little output.
- **Above ~6–8 kHz**, speakers roll off and microphones and AGC distort.
- The data band starts at **1 722.7 Hz** (bin 40) and ends at **5 814 Hz** (G = 6) or **7 192 Hz** (G = 8).
- The sync tones (1.2 and 1.55 kHz) sit *below* the data band, where response is strong. Detection scores on the **weaker** sync tone, and a high sync tone would fail exactly when roll-off is worst.

The room simulator models roll-off as cascaded one-pole low-pass stages (each about −3 dB at 3.1 kHz). The "hostile" setting uses 6 stages, about −47 dB at 7.2 kHz, which effectively removes groups 6 and 7. That's another reason the 6-group profiles are more robust.

---

## 10. QR imaging: sampling and blur

### 10.1 Sampling

To decode, each QR module must be classified as dark or light from pixels near its centre. By a Nyquist-style argument, at least **2 pixels per module** is the theoretical minimum for an ideal, perfectly aligned image. Real images are rotated, perspective-distorted and blurred, and practical decoders need about **4 or more**.

Pixels per module (ppm) for a QR occupying fraction φ of the 706-pixel decode square:

```
ppm = φ · 706 / (4·v + 17 + 8)          (v = QR version; +8 for the quiet zone)
```

| φ | v8 | v12 | v20 |
|---|---|---|---|
| 0.62 (good) | 7.7 | 6.0 | 4.2 |
| 0.50 (typical) | 6.2 | 4.8 | 3.4 |
| 0.42 (hard) | 5.2 | 4.1 | 2.8 |

### 10.2 Blur

Defocus and hand shake act like convolution with a point-spread function (PSF). With a Gaussian PSF of σ px and a module of width w px, the contrast at a module centre, next to opposite-coloured neighbours, falls roughly as erf(w / (2√2·σ)):

| w (px/module) | σ = 1.1 px (typical) | σ = 1.5 px (hard) |
|---|---|---|
| 6.2 | ≈ 0.995 | ≈ 0.96 |
| 4.8 | ≈ 0.97 | ≈ 0.89 |
| 3.4 | ≈ 0.88 | ≈ 0.74 |

Add 1–2 px of motion blur and noise, and sub-0.8 contrast codes start failing binarization. That matches the measured cliff: v20 reads 13% in the typical tier and v12 reads 0% in the hard tier.

### 10.3 Why zoom adds real resolution

Phone sensors are 12 MP or more (e.g. 4 000 × 3 000), and the 720p stream is a downscale. Digital zoom crops the sensor *before* downscaling, so at 1.5× the stream's pixels come from a sensor area 1.5× smaller in each dimension. The QR spans 1.5× more stream pixels, and ppm rises by 1.5×. This is genuine resolution, not interpolation, up to the point where the crop reaches the sensor's native resolution.

---

## 11. Screen–camera timing

The screen shows a new QR every 83 ms (12 fps). The camera exposes frames every 33 ms (30 fps), with an exposure time t_e < 33 ms, and the two aren't synchronised.

A capture is **clean** if its exposure falls entirely within one QR's display interval. If the display interval is D and the exposure is t_e, the probability that a random exposure straddles a transition is about t_e / D (plus the screen's own refresh scan-out).

```
D = 83 ms, t_e ≈ 10–20 ms  →  12–24% of captures straddle
```

At about 2.5 captures per displayed code, it is very likely that **at least one** capture of each code is clean. This is why the ETA model uses a **yield** below the per-frame decode rate: 0.70 for v8, against a simulated per-frame rate of 100%.

**Why not faster?** At 20 fps (D = 50 ms) only 1.5 captures per code, with 20–40% straddling, so many codes would never be seen clean. At 30 fps codes and captures alias badly.

---

## 12. Luminance and binarization

**Luminance.** On Android, the camera's YUV420 **Y plane** is luminance (BT.601 luma), so the app copies it directly. On iOS and the web, BGRA pixels are converted with `(R + 2G + B) / 4`, a cheap approximation of 0.299R + 0.587G + 0.114B that favours green, as zxing does.

**Global histogram binarizer** (attempt 1). Builds a 32-bucket luminance histogram of the image, finds the two dominant peaks (dark and light), and places a single threshold in the valley between them. It is ideal for a self-lit, evenly bright screen, very fast, and the best performer in the sweeps.

**Hybrid binarizer** (attempt 3). Computes local thresholds over 8×8-pixel blocks, averaged over 5×5 neighbourhoods. It is robust to glare gradients and uneven light, but slower, and on fine modules it can create noise.

**`pureBarcode`** (attempt 2). Skips finder-pattern detection and assumes the image contains just the code; it samples the grid from the bounding box of dark pixels. It rescues frames where random data forms fake finder patterns (1:1:3:1:1 runs). Because the decode square is tightly cropped around the aim brackets, the QR usually does fill it, which makes this assumption valid.

Every attempt ends with the QR's own Reed-Solomon check, so a wrong binarization fails cleanly rather than returning wrong bytes. The APCF CRC-32 is a second line of defence.

---

## 13. Vibration: baseline tracking

Accelerometer magnitude m = √(x² + y² + z²) includes gravity (≈9.81 m/s²) plus posture changes. A buzz adds a vibration component of a few m/s². The receiver tracks the resting level with an exponential moving average while quiet:

```
b[n] = (1 − α)·b[n−1] + α·m[n],     α = 0.08
```

Its step response reaches 63% after 1/α ≈ 12.5 samples. The update is **frozen while a pulse is active**, so a long buzz doesn't drag the baseline up and cut its own measured length short.

A pulse is active while |m − b| ≥ 1.4 m/s² (`relativeThreshold`). Its duration is classified against the 130 ms midpoint between the 80 ms and 180 ms nominal pulses, and pulses under 25 ms are discarded as knocks.
