# Showcase Guide

A complete plan for demonstrating the app in front of an audience: what to prepare, the exact demo sequence, what to say while it runs, and what to do if something goes wrong. Timings come from the app's own estimate formulas and the simulation results. Rehearse on your actual phones before the day.

Back to the [documentation index](../README.md).

---

## Contents

1. [The one-sentence pitch](#1-the-one-sentence-pitch)
2. [Preparation (the day before)](#2-preparation-the-day-before)
3. [The demo sequence (about 5 minutes)](#3-the-demo-sequence-about-5-minutes)
4. [Talking points while a transfer runs](#4-talking-points-while-a-transfer-runs)
5. [Recovery plan: if something goes wrong](#5-recovery-plan-if-something-goes-wrong)
6. [Expected timings (from the app's formulas)](#6-expected-timings-from-the-apps-formulas)
7. [Five-minute Q&A cheat sheet](#7-five-minute-qa-cheat-sheet)

---

## 1. The one-sentence pitch

> "These two phones have Wi-Fi, Bluetooth and mobile data switched off. We're going to send a photo and a narrated video from one to the other using nothing but the screen and the camera, then a message using only sound."

Switch on **Airplane mode** on both phones in front of the audience. It is the most convincing moment of the demo.

---

## 2. Preparation (the day before)

### Phones

| Check | Why |
|---|---|
| Same APK installed on both phones | The Light frame format is versioned; mismatched builds reject each other's frames |
| Both phones charged above 60% | Full brightness and the camera drain the battery fast |
| Camera, microphone and storage permissions granted | Avoid permission pop-ups on stage. Open Receive → Light and Receive → Sound once each to trigger them |
| Screen protectors clean, camera lens wiped | Smudges blur the QR modules. Focus and sharpness matter most for decoding |
| Screen timeout set to 2+ minutes | The app keeps the screen awake while streaming, but not on other screens |
| Do Not Disturb on | A notification banner over the QR code costs frames |
| Media volume at maximum on the sender | For the Sound demo and for video playback on the receiver |
| Received album cleared | So the audience sees the new item appear in *Adaptive Comm* |

### Rehearse these three transfers at least twice

1. A **5 KB photo** over Light (should finish in about 5 s).
2. The **Speed of light** video (78 KB) over Light (about 40 s).
3. The text **"Hello from sound!"** over Sound on Standard (about 10 s).

Time each one. If the Light transfers are much slower than this, see [Troubleshooting](../operations/TROUBLESHOOTING.md) before the event.

### Venue

- **Lighting:** avoid a bright lamp or window reflecting off the sender's screen. Glare is the most common cause of a stall.
- **Surface:** a table where the receiver can rest their elbows. Steadiness beats everything.
- **Noise:** for Sound, a quiet corner helps. In a loud hall use the **Rugged** profile.
- **Projector (optional):** mirror the *receiver's* screen so the audience sees the HUD counters climb.

---

## 3. The demo sequence (about 5 minutes)

### Step 1: Airplane mode (15 s)

Turn on Airplane mode on both phones and show it.

### Step 2: Light, small photo (30 s)

1. **Sender:** Send → **Demo samples** → a **5 KB** photo (e.g. *Robot lab*, 5 KB) → Continue to send → **Light** → density **Auto** → **Show QR & send**.
2. **Receiver:** Receive → **Light**. Hold 15–25 cm from the sender's screen, QR inside the corner brackets, elbows on the table.
3. Watch the HUD go **SCAN → LOCK → DONE**. It should take 3–5 seconds.
4. The photo appears. Tap it for full screen, then point out the "Saved to Gallery" state.
5. **Sender:** tap **Stop**, then **Receiver shows DONE**.

### Step 3: Light, narrated video (60 s)

1. **Sender:** Send → Demo samples → **Speed of light** (78 KB video) → Light → Auto → Show QR & send.
2. **Receiver:** same as before. The HUD shows about 243 symbols needed.
3. While it runs (about 40 s), explain the fountain idea (Section 4 below).
4. On **DONE**, the video plays **with sound** straight away, which is a strong moment.

### Step 4: Sound (30 s)

1. **Sender:** Send → type **Hello from sound!** → Continue to send → **Sound** → **Standard** → **Play & send**.
2. **Receiver:** Receive → **Sound**. Allow the microphone if asked. Hold the phones 20–50 cm apart, speaker facing the microphone.
3. The receiver shows "Receiving over sound · Standard" and the text appears after about 10 s.
4. Point out that the receiver **detected the speed profile by itself**.
5. Hold the two screens side by side. The sender's **Sending now** and the receiver's **Hearing now** show the same kHz, live.
6. **Silent encore (optional, 20 s):** resend **Meet at gate 3** on **Silent**. The room hears nothing, yet both readouts show about 18.5–19.9 kHz. That's the proof the data is really going through the air.

### Step 5 (optional): Vibration (60 s+)

Only if time allows. Press the phones together firmly and send a single short word. It is slow by design (about 0.5 bytes per second), so it works as a physics demonstration rather than a data link.

### Step 6 (optional): Simulation Lab (60 s)

Home → ⋮ → Developer tools → **Simulation Lab** → scenario *optical-degrades* → run. It shows the adaptive engine detecting the collapsing light channel and switching to sound mid-transfer.

---

## 4. Talking points while a transfer runs

**What the HUD means:**

| HUD item | Say this |
|---|---|
| **SCAN / LOCK / DONE** | "Scanning for codes; locked onto a transfer; file complete." |
| **CAP** | "Camera frames per second, usually about 30." |
| **DEC** | "How many QR codes per second we actually read. It never needs to be every one." |
| **NEW** | "Pieces that gave us new information." |
| **DUP / RED** | "Pieces we already had. Harmless." |
| **x / K symbols** | "The file is split into K pieces. When we have K independent ones, we're done." |

**The fountain analogy.**
> "Imagine filling a glass from a fountain. You don't care *which* drops land in the glass, only that enough of them do. The sender sprays an endless stream of coded pieces, each a different mix of the file. Any K of them, give or take one or two, rebuild the whole file. So if my hand shakes and I miss frames, nothing is lost. I just catch the next ones."

**Why the QR codes are small.**
> "We tested this with a simulated phone camera. A dense QR code gets read about 13% of the time from a hand-held phone; a smaller one gets read almost every time. Sending less per frame but reading nearly every frame is much faster overall."

**Why sound works in a noisy room.**
> "Each sound frame carries error-correcting parity. The receiver also knows which bytes it is unsure about, and that doubles the damage it can repair."

**Why there's no "delivered" tick.**
> "The screen can't hear back from the camera. There's no return channel at all, which is exactly why one screen can feed any number of phones at once."

**One-to-many.** If you have a third phone, point both receivers at the same sender screen at once. Both finish independently.

---

## 5. Recovery plan: if something goes wrong

| What you see | What to do (calmly) | What to say |
|---|---|---|
| Receiver stuck on **SCAN** | Move to about 20 cm; get the whole QR in the brackets; tap the preview to focus; try **2×** zoom; tilt to kill glare | "The camera needs to see the whole code. Let me frame it." |
| **DEC** very low, counter climbs slowly | Rest elbows on the table; move out of a reflection | "Steadiness matters more than anything for a camera." |
| Counter stops at "x / K" | Keep holding. If the sender stopped, tap **Resume streaming** | "Nothing is lost. The receiver keeps every piece it has." |
| Sound: "too damaged" rising | Volume up, speaker towards the mic, move closer, or resend on **Rugged** | "The room is loud, so I'll use the robust profile." |
| Sound: nothing at all | Tap **Enable microphone**; check that the tone meter moves while the sender plays | |
| Silent: the *Silent band 18–20 kHz* meter stays flat | Media volume to max on the sender; swap the phones' roles; otherwise switch the sender to **Audible** | "Not every phone speaker reaches 19 kHz. The audible band always works." |
| Video won't play on an iPhone | Use an **MP4** sample (iOS doesn't play WebM) | |
| Something is truly broken | Switch to the Simulation Lab and explain the design there | "Here's the same pipeline under a simulated channel." |

**Golden rule:** never restart the receiver mid-transfer to "fix" it. Progress survives re-aiming, leaving the screen and camera restarts, but pressing *Clear* discards it.

---

## 6. Expected timings (from the app's formulas)

| Transfer | Channel / profile | Pieces (K) | Expected time |
|---|---|---|---|
| "Hello from sound!" (24 B) | Sound / Standard | 1 | ≈10 s (2.4 s if the first frame lands) |
| "sos" (10 B) | Sound / Rugged | 1 | ≈12 s (3 s if the first frame lands) |
| "Meet at gate 3" (21 B) | Sound / **Silent** (inaudible) | 1 | ≈19 s (4.8 s if the first frame lands) |
| 2 KB sample photo (≈3.4 KB after re-encode) | Light / Auto (160 B) | 21–22 | ≈3 s |
| 5 KB sample photo (≈8.6 KB) | Light / Auto (240 B) | 36–37 | ≈5 s |
| 10 KB sample photo (≈16–18 KB) | Light / Auto (330 B) | 50–55 | ≈8–9 s |
| 20 KB sample photo (≈32–35 KB) | Light / Auto (330 B) | 98–105 | ≈16–17 s |
| Speed of light, 78 KB video | Light / Auto (330 B) | 243 | ≈38 s |
| How QR codes work, 136 KB video | Light / Auto (330 B) | 422 | ≈65 s |

Derivations: [Calculations](../algorithms/CALCULATIONS.md). Photos are re-compressed at send time and grow by about 60–70% ([Known Issue 4.1](../project/KNOWN_ISSUES.md#41-photos-are-re-compressed-and-grow-medium)); the table uses the measured sizes from [Media Pipeline §8](../development/MEDIA_PIPELINE.md#8-measured-sample-costs). Don't send the 5 KB samples by Sound: they end up over the 8 KiB Sound limit.

---

## 7. Five-minute Q&A cheat sheet

| Question | Short answer |
|---|---|
| Is it encrypted? | Not yet. Anyone who can see the screen or hear the sound could decode it. See [Security](../operations/SECURITY.md). |
| How far does it work? | Light: 15–25 cm. Sound: across a table, up to a couple of metres in a quiet room. Vibration: touching. |
| Why not just use Bluetooth? | The point is communication with no radio at all: air-gapped, radio-silent or emergency situations, and one-to-many broadcast with no pairing. |
| How fast is it? | Light: about 1.3–2.5 KB/s in practice. Sound: 11–36 bytes per second audible, 3.4–5 bytes per second silent. |
| Why can't I hear the Silent mode? | It plays one tone at a time at 18.3–19.9 kHz, above most adults' hearing and above nearly all room noise. Same error correction and fountain code as the audible band. See [Sound Channel §14](../channels/SOUND_CHANNEL.md#14-silent-band-near-ultrasonic). |
| Why FSK and not ASK or PSK? | Loudness (ASK) changes with distance and echoes, and phase (PSK) is scrambled by echoes, hand movement and the two phones' unsynchronised clocks. Frequency survives all of that, so the receiver only picks the loudest of 16 tones. See [ADR-10](../architecture/DESIGN_DECISIONS.md#adr-10-multi-tone-fsk-for-sound). |
| How many ms per bit? | Each tone carries 4 bits. Standard plays 8 tones for 93 ms: 2.9 ms per bit raw, 4.6 ms per bit after error correction. Silent plays one tone for 46 ms: 11.6 ms per bit raw, about 25 ms after error correction. |
| Can we see the frequencies? | Yes: **Sending now** on the sender and **Hearing now** on the receiver, in kHz, with a spectrum strip. |
| What if frames are lost? | The fountain code makes lost frames irrelevant. Only the number of good frames matters. |
| Can many phones receive? | Yes, for Light and Sound. Every receiver finishes independently. |
| What is the adaptive part? | The engine scores channels on throughput, reliability, latency, confidence and stability, and switches with hysteresis. See [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md). |
