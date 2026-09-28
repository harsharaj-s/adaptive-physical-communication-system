# Troubleshooting

Symptoms, their causes, and fixes, grouped by channel. Start with the quick checks in [§1](#1-quick-checks-first). They solve most problems in seconds, which matters during a live demo.

Back to the [documentation index](../README.md).

---

## Contents

1. [Quick checks first](#1-quick-checks-first)
2. [Light](#2-light)
3. [Sound](#3-sound)
4. [Vibration](#4-vibration)
5. [Photos, videos and Gallery](#5-photos-videos-and-gallery)
6. [Install, start-up and permissions](#6-install-start-up-and-permissions)
7. [Web](#7-web)
8. [Developer screens and tests](#8-developer-screens-and-tests)
9. [Reading the HUD to diagnose](#9-reading-the-hud-to-diagnose)
10. [Still stuck?](#10-still-stuck)

---

## 1. Quick checks first

| Check | Why |
|---|---|
| Both phones run the **same build** | Frame formats differ between generations ([Changelog](../project/CHANGELOG.md#compatibility-rule)) |
| The receiver pressed **Receive** and chose the **same channel** as the sender | Each channel listens only for its own signal |
| Permissions granted (camera for Light, microphone for Sound) | See [§6](#6-install-start-up-and-permissions) |
| Light: the receiver is **15–40 cm** away and the QR fills the aim brackets | Pixels per module |
| Sound: sender volume **at maximum**, speaker facing the microphone | Signal strength |
| Battery saver **off** on both phones | It throttles the camera and CPU |

---

## 2. Light

| Symptom | Likely cause | Fix |
|---|---|---|
| HUD stays on **SCAN**, DEC = 0 | QR not fully inside the brackets, out of focus, too far or too close | Move to about 25 cm, fill the brackets, **tap to focus**; try the 1.5× or 2× zoom chip |
| Amber hint "No codes readable…" | About 2 s of captures with nothing decoded | Same as above; also tilt the sender 10–20° to kill glare |
| DEC is low (< 3/s) but not zero | Blur, glare, a dense profile or a weak camera | Sender: switch to **Safe**. Receiver: hold steadier, closer, zoom 2× |
| CAP below 15 fps | Receiver phone throttling (heat, battery saver) | Close other apps; let the phone cool; turn battery saver off |
| High DROP | Decoder busy (normal on slow phones) | Nothing needed; the fountain absorbs it. Safe profile reduces the load |
| Progress climbs, then stops 1–2 symbols short | Normal for small K near the end, or the sender stopped | Wait a few seconds; if the sender stopped, tap **Resume streaming** |
| Sender says "Streaming stopped" but the receiver isn't DONE | The sender tapped Stop too early | **Resume streaming**: same session, the receiver keeps its progress |
| "Paused after the 10-minute safety limit" | The long stream hit the safety cap | **Resume**; for big files use Standard/Auto and hold steadier |
| Two senders in view, slow progress | Mixed frames from two sessions | Point at one screen; up to 3 sessions decode in parallel, but each gets fewer frames |
| Sender screen is dim | iOS (no automatic brightness boost) or a battery-saver cap | Turn brightness up by hand |
| The QR flickers or stutters on the sender | A very old phone that can't render 12 fps | Use **Safe** (8 fps) |
| "Incomplete image/message" | Only with legacy paths; fountain delivers only complete, CRC-checked files | Hold steady until DONE; resend |

---

## 3. Sound

| Symptom | Likely cause | Fix |
|---|---|---|
| Tone meter doesn't move | Microphone permission, wrong screen, sender volume low | Tap **Enable microphone**; volume to maximum; point the speaker at the microphone |
| "Microphone permission required" | Permission denied | Tap **Enable microphone** or allow it in Settings |
| Tones detected, blocks don't climb, "too damaged" rises | SNR too low or heavy echo | Move to 20–50 cm; the sender uses **Rugged** or **Safe** (the receiver follows automatically) |
| Works close, fails at 2 m | High-frequency roll-off, reverberation | Safe or Rugged (6 groups, longer symbols); a smaller, softer room helps |
| Stops one block short | The sender ended its budget or was stopped | Play again: a new session starts, so keep the sender playing until the receiver shows DONE |
| A photo sent by Sound never arrives | The envelope is over 8 KiB and took the legacy path ([Known Issue 2.2](../project/KNOWN_ISSUES.md#22-sound-messages-over-8-kib-silently-use-a-path-the-receiver-cant-decode-high)) | Send it by **Light**; for Sound use text or a 2 KB photo |
| The sender shows "sent" but nothing arrived | Sound has no return path, so "sent" only means the sender played the frames | Check the receiver's screen |
| No sound from the sender | Media volume at zero, silent mode, Bluetooth headphones connected | Turn media volume up; disconnect Bluetooth audio. On **Silent**, hearing nothing is normal: watch the receiver's *Silent band* meter instead |
| Receiver hears the sender only on speakerphone-style phones | Some phones filter the voice microphone | Try the other phone as the receiver; put the phones closer |
| **Silent:** the *Silent band 18–20 kHz* meter stays near zero | One phone's speaker or microphone doesn't pass 19 kHz, media volume low, or Bluetooth audio connected ([Known Issue 2.5](../project/KNOWN_ISSUES.md#25-the-silent-band-depends-on-each-phones-19-khz-response-medium-by-design)) | Media volume to maximum; disconnect Bluetooth; swap roles; otherwise switch to **Audible** |
| **Silent:** the meter moves but no frames decode | Too far apart, phones moving, or a very loud crowd | 10–50 cm apart, hold still, or pick **Silent Robust** |
| Sender's **Sending now** shows a kHz value but the receiver's **Hearing now** shows **—** | The tones aren't reaching the receiver's microphone: volume, distance, a covered speaker or microphone, Bluetooth audio, or (around 19 kHz) a phone that doesn't pass the Silent band | Same fixes as the rows above. Whistle near the receiver: if **Hearing now** follows the whistle, the microphone works and the problem is on the sender's side |
| **Hearing now** matches the sender's kHz but nothing decodes | The tones arrive, but echoes, motion or noise corrupt them | Move closer, hold both phones still, or pick a slower speed (**Rugged**, **Safe** or **Silent Robust**) |
| **Hearing now** shows a steady frequency with no sender playing | A fan, charger whine, monitor or another app making a tone | Harmless unless it sits inside the band in use: 1.2–7.2 kHz for Audible, 18.3–19.9 kHz for Silent. If it does, move away from the source or switch band |
| **Silent:** faint ticks at the start and end of each burst | The speaker distorts at maximum volume | Lower the volume one step; the bursts already fade in and out |
---

## 4. Vibration

| Symptom | Likely cause | Fix |
|---|---|---|
| Nothing decodes | Phones not touching, soft surface absorbing vibration | Stack the phones back-to-back on a hard table |
| Bits wrong or garbage text | Hand movement or knocks during the transfer | Don't touch the phones while buzzing |
| Takes minutes | Normal: ≈0.5 B/s | Keep messages to one or two words |
| Sender retransmits while still buzzing | Airtime longer than the ACK timeout ([Known Issue 2.3](../project/KNOWN_ISSUES.md#23-vibration-airtime-exceeds-the-acknowledgement-timeout-medium)) | Short messages only |
| Not available | Web, or a device without a motor or accelerometer | Use a phone |

---

## 5. Photos, videos and Gallery

| Symptom | Likely cause | Fix |
|---|---|---|
| "Could not read this photo" | An unsupported or corrupt image format | Use JPG/PNG, or take a new picture |
| "Large file" dialog | Over 512 KiB | Pick something smaller; Light at ≈2 KB/s needs minutes for large files |
| Photo arrives bigger than the sample size | Send-time re-compression ([Known Issue 4.1](../project/KNOWN_ISSUES.md#41-photos-are-re-compressed-and-grow-medium)) | Expected; it's still fast on Light |
| Text I typed with a photo was sent alone | Known Issue 4.2 | Send the photo and the text separately |
| "Gallery permission denied" | Photos permission refused | Allow it in Settings, then tap **Save to Gallery** |
| "Not enough storage" | Phone full | Free space, then **Save to Gallery** |
| "Format not supported by the gallery" | Rare formats (e.g. WebM on some iPhones) | The message still plays inside the app |
| Video doesn't play | Codec not supported by the phone's player | MP4 (H.264/AAC) plays everywhere; WebM may not on iOS |
| Can't find saved media | It's in the album **Adaptive Comm** | Open the Gallery/Photos app → Albums |

---

## 6. Install, start-up and permissions

| Symptom | Fix |
|---|---|
| "App not installed" / signatures don't match | Uninstall the previous build first (debug vs release signing) |
| Blocked by Play Protect | Tap "Install anyway" (sideloaded demo builds aren't Play-signed) |
| Old icon after an update | Uninstall and reinstall, or restart the launcher |
| Camera permission prompt never appears | It was denied permanently: Settings → Apps → Adaptive Comm → Permissions |
| App shows a dark screen with the logo for a long time | First launch on a slow phone; wait a few seconds. If it persists, reinstall |

See [Permissions and Privacy](PERMISSIONS_AND_PRIVACY.md) and [Build and Release](BUILD_AND_RELEASE.md).

---

## 7. Web

| Symptom | Fix |
|---|---|
| Camera never starts | Serve over **HTTPS** or `localhost`; allow the camera in the browser's site settings |
| Microphone blocked | Same; some browsers need a user click before audio starts |
| No Vibration option | Not supported on the web |
| Logo splash stays up | Flutter failed to load; open the browser console, check that `flutter_bootstrap.js` is served |

---

## 8. Developer screens and tests

| Symptom | Explanation |
|---|---|
| Simulation `optical-degrades` or `burst-loss` fails | Known cumulative-ACK issue ([Known Issue 3.1](../project/KNOWN_ISSUES.md#31-acks-are-treated-as-cumulative-high-for-the-protocol-path)); see [Simulation Lab](../development/SIMULATION_LAB.md) |
| Simulation progress bars stay at 0% | Known UI quirk |
| `flutter test` treats the platform as Android on Windows | Flutter's test default; expected |
| One test skipped | The full density table runs only with `$env:OPTICAL_SWEEP = "1"` |
| Gradle cache errors on Windows | `$env:GRADLE_USER_HOME = "$env:USERPROFILE\.gradle"` |

---

## 9. Reading the HUD to diagnose

**Light:**

| Pattern | Meaning | Action |
|---|---|---|
| CAP ≈ 30, DEC ≈ 6–9, NEW rising | Healthy | Wait |
| CAP ≈ 30, DEC ≈ 0 | Nothing readable | Aim, focus, distance, glare |
| CAP < 15 | Receiver throttled | Cool down, close apps |
| DEC high, NEW flat, DUP rising | Seeing the same symbols (the sender stopped or restarted with old indices) | Check the sender is still streaming; **Resume** |
| RED rising slightly near the end | Normal: dependent symbols near full rank | Wait |

**Sound:**

| Pattern | Meaning | Action |
|---|---|---|
| Tone meter strong, blocks climbing | Healthy | Wait |
| Tone meter strong, "repaired" high, "rejected" low | Noisy but Reed-Solomon copes | Fine |
| "Rejected" climbing | Too much damage per frame | Closer, quieter, or a more rugged profile |
| Tone meter weak | Too far or too quiet | Volume up, closer |

---

## 10. Still stuck?

1. Restart both apps, and try the **same** transfer with a short text first.
2. Try **Light Safe** with the phones 25 cm apart. It works on nearly any camera.
3. Open **Developer tools → Hardware Channels** to test each channel on its own and read the logs.
4. Check [Known Issues](../project/KNOWN_ISSUES.md) and the [FAQ](../getting-started/FAQ.md).
5. Report it on the GitHub repository with the phone models, channel, profile, distance and a screenshot of the HUD.
