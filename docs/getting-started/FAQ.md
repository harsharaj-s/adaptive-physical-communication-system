# Frequently Asked Questions

Short answers to the questions people ask most, with links to the full explanations.

Back to the [documentation index](../README.md).

---

## General

**What does the app do?**
It sends text, links, photos, videos and small files from one phone to another using only light (a QR-code animation on the screen, read by the other phone's camera), sound (tones from the speaker, heard by the microphone) or vibration (motor pulses felt by the accelerometer).

**Does it use the Internet, Wi-Fi, Bluetooth or NFC?**
No. The Android release manifest doesn't even request the `INTERNET` permission. The code keeps an explicit list of excluded transports, and a test (`test/physical_only_test.dart`) checks that exactly three physical channels exist. See [Permissions and Privacy](../operations/PERMISSIONS_AND_PRIVACY.md).

**Which platforms are supported?**
Android and iOS support all three channels. Chrome (web) supports Light (receive via webcam) and Sound. Vibration needs a phone.

**Do both phones need the app?**
Yes, and the **same build**. The Light frame format has a version byte, and other versions are rejected on purpose.

**Can one phone send to several phones at once?**
Yes, for Light and Sound. The sender broadcasts, and every receiver finishes on its own. Vibration is one-to-one because the phones must touch.

---

## Light channel

**How close should the phones be?**
15–25 cm, with the whole QR code inside the receiver's corner brackets. The receiver starts at 1.5× zoom, so you don't need to be very close.

**Why does the QR code change so fast?**
Each code carries one *symbol* of a fountain code: 160–600 bytes plus a 26-byte header. The screen shows 12 codes per second (8 on Safe). See [Light Channel](../channels/LIGHT_CHANNEL.md).

**Why doesn't the receiver need to read every code?**
Because of the fountain code: any K codes (plus one or two) rebuild a file of K pieces. See [Fountain Code](../algorithms/FOUNTAIN_CODE.md).

**Why are the QR codes so small compared with the maximum a QR can hold?**
A QR version 40 holds about 2.9 KB, but a hand-held phone camera can't resolve its modules. The simulations showed about 100% reads at version 8, 81% at version 12 and 13% at version 20, so small codes finish much faster overall.

**What does "Auto" density do?**
It picks 160, 240 or 330 bytes per frame, choosing the sparsest code that keeps the transfer to 48 symbols or fewer. Envelopes up to 7 680 B use 160; up to 11 520 B use 240; anything larger uses 330.

**The sender keeps streaming after the receiver shows DONE. Is that a bug?**
No. The screen can't know when the camera has finished, because there is no return channel. Tap **Stop** once the receiver shows DONE. A safety cap stops the stream after 10 minutes.

**What if I stop too early?**
Tap **Resume streaming**. The sender continues with *new* symbols from where it stopped, and the receiver keeps all its progress.

**Does it make the screen brighter?**
Yes, on Android. The sender sets its window brightness to full while streaming and restores it afterwards. No special permission is needed.

---

## Sound channel

**What does it sound like?**
A series of chirpy chords between about 1.2 and 7.2 kHz. Each frame starts with a two-tone sync burst.

**How fast is it?**
Rugged 10.8, Safe 18.1, Standard 27.0 and Fast 35.8 bytes per second of payload. A short text takes 7–21 s depending on profile. See [Sound Channel](../channels/SOUND_CHANNEL.md).

**Does the receiver need to pick the same speed?**
No. The receiver listens for all four profiles at once and locks onto the one the sender uses.

**How does it cope with noise?**
Three layers:
1. Reed-Solomon parity repairs up to 12 wrong bytes per frame, or up to 24 bytes the receiver has flagged as unsure.
2. A CRC-16 rejects anything the repair got wrong.
3. The fountain code makes frames that are lost outright irrelevant.

**Can I send a photo over sound?**
Only a very small one. A 2 KB photo takes about 1.7 minutes on Standard. Use Light for media.

**Why is there an 8 KiB limit?**
Messages over 8 KiB fall back to the older packet protocol, which the fountain receiver doesn't decode. Keep sound messages under about 2 KB. See [Known Issues](../project/KNOWN_ISSUES.md).

---

## Vibration channel

**How does vibration carry data?**
A short buzz (80 ms) is a 0, a long buzz (180 ms) is a 1. The receiver measures each buzz with its accelerometer. See [Vibration Channel](../channels/VIBRATION_CHANNEL.md).

**Why is it so slow?**
Motors spin up and down slowly and accelerometers sample at tens to a couple of hundred hertz, so each bit takes about a quarter of a second. It is a demonstration of physical coupling, suitable for a word or two.

---

## Photos, videos and the Gallery

**Are received photos saved automatically?**
Yes. Photos and videos are saved to the Gallery in the album **Adaptive Comm**. The received card has a Save / Retry button if saving fails. Each message is saved only once.

**Why was my photo made smaller?**
Before sending, photos are resized to at most 960 px on the long side and JPEG-compressed to at most 120 KB. See [Media Pipeline](../development/MEDIA_PIPELINE.md).

**Where do the demo samples come from?**
They are bundled in the app (`assets/samples/`): 16 photos (2, 5, 10 and 20 KB) and 9 short videos with sound, including 8 narrated educational explainers generated by scripts in `tool/`.

**Why won't a video play on my iPhone?**
iOS doesn't support WebM. Use the MP4 samples.

---

## Security and privacy

**Is the data encrypted?**
No. Anyone who can see the screen or hear the sound can decode the message. See [Security](../operations/SECURITY.md).

**Does the app collect or upload anything?**
No. There is no network code in the data path and no analytics. Received items stay on the device.

---

## Development

**How do I run the tests?**
`flutter test`. See [Testing](../development/TESTING.md).

**How were the design numbers chosen?**
From headless simulations. A camera model renders QR codes with blur, perspective, glare and noise; a room model adds echoes, speaker roll-off, clock drift and noise. See [Testing](../development/TESTING.md) and [Design Decisions](../architecture/DESIGN_DECISIONS.md).

**How do I add a new channel?**
Implement `CommChannel` and register it in the channel manager. See [API Reference](../development/API_REFERENCE.md) and [Contributing](../development/CONTRIBUTING.md).
