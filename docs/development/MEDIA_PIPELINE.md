# Media Pipeline

How photos, videos, links and text travel from the compose screen, through the envelope, across a channel and into the receiver's chat and Gallery. It also covers how the bundled demo samples were made and how to add new ones.

Back to the [documentation index](../README.md).

---

## Contents

1. [Overview](#1-overview)
2. [Composing a message](#2-composing-a-message)
3. [Photo compression](#3-photo-compression)
4. [The APCM envelope](#4-the-apcm-envelope)
5. [Receiving and displaying](#5-receiving-and-displaying)
6. [Saving to the Gallery](#6-saving-to-the-gallery)
7. [Bundled samples](#7-bundled-samples)
8. [Measured sample costs](#8-measured-sample-costs)
9. [Regenerating or adding samples](#9-regenerating-or-adding-samples)
10. [Choosing media for a demo](#10-choosing-media-for-a-demo)

---

## 1. Overview

```
Compose screen ──► ComposePayload ──► AppController.sendPhysicalMessage
  text / link / photo / video / sample        │
                                              ├─ photo: compressImageForTransfer (again)
                                              ▼
                                 ChatPayloadCodec.encode → APCM envelope
                                              │
                          Light / Sound / Vibration (see the channel docs)
                                              │
                                              ▼
Receiver: envelope bytes ─► ChatPayloadCodec.decodeIncoming ─► ChatMessage
                                              │
                        chat bubble + ReceivedContentView (image viewer / video player)
                                              │
                                   GallerySaver (auto-save, album "Adaptive Comm")
```

| Area | File |
|---|---|
| Compose UI, file picker, sample sheet | `lib/ui/screens/send_compose_screen.dart` |
| Outgoing payload model | `lib/ui/models/compose_payload.dart` |
| Photo compression | `lib/core/media/image_compress.dart` |
| Envelope codec | `lib/core/chat/chat_payload_codec.dart` |
| Message model | `lib/core/chat/chat_message.dart` |
| Sample catalogue | `lib/core/media/sample_media.dart` |
| Gallery saving | `lib/core/media/gallery_saver.dart` |
| Viewer / player | `lib/ui/widgets/received_content_view.dart`, `chat_bubble.dart` |
| Sample generators | `tool/make_sample_media.py`, `tool/make_explainer_videos.py` |

---

## 2. Composing a message

`SendComposeScreen._buildPayload()` decides what gets sent:

| Input | Resulting payload |
|---|---|
| Text only | `text`, envelope name `message.txt`, MIME `text/plain` |
| Text that looks like a URL (`http://`, `https://`, `www.` or `name.tld`) | `link`, name `link.url`, MIME `text/uri-list`. Adds `https://` if missing |
| Photo from the picker | Compressed immediately (see [§3](#3-photo-compression)), renamed to `.jpg`, MIME `image/jpeg` |
| Video from the picker | Sent as is, MIME from the extension (`mp4`, `mov`, `webm`) |
| Sample | Loaded from the asset bundle, file name and MIME from the catalogue |
| Photo/video **and** text | **Only the text is sent** (see [Known Issues](../project/KNOWN_ISSUES.md)) |

**Large file warning.** Anything over **512 KiB** (`_maxHardwareBytes`) triggers a "Large file" dialog ("Physical channels work best under 512 KB…") with *Cancel* or *Use anyway*.

After the user taps **Send**, the mode picker asks for Light, Sound or Vibration, and `SendTransmitScreen` calls `AppController.sendPhysicalMessage`.

---

## 3. Photo compression

`compressImageForTransfer(bytes, maxWidth: 960, maxHeight: 960, quality: 78, maxBytes: 120 KiB)`:

```
decode (package:image)
  └─ undecodable? JPEG magic FF D8 → pass through (or _recompressKnownJpeg if > 120 KiB)
                   otherwise → ImageTransferException("Could not read this photo…")
resize so the long side ≤ 960 px (linear interpolation)
encode JPEG q78
while > 120 KiB and q > 40: q −= 8 and re-encode       (78 → 70 → 62 → 54 → 46 → 38)
still > 120 KiB and long side > 640: resize to 640, JPEG q65
verify the output is a displayable image (JPEG/PNG/GIF/WebP magic)
```

- **Always JPEG.** PNG, WebP and GIF inputs become JPEG; transparency is flattened by the encoder.
- **It runs twice for picked photos:** once in the compose screen and again in `AppController._prepareEnvelope`. It also runs for **samples**, even though they were already sized. Re-encoding an already-small, low-quality JPEG at q78 makes it **larger** (about +60–70% for the bundled samples; see [§8](#8-measured-sample-costs)). This is a known issue.
- The 120 KiB cap means a worst-case photo takes about 57 s on Light (K = 373 at 330-byte blocks).

---

## 4. The APCM envelope

Every channel carries the same self-describing envelope:

```
"APCM" | type (1) | nameLen (1) | name (UTF-8) | mimeLen (1) | mime (UTF-8) | data
```

| `type` | Value | `data` |
|---|---|---|
| text | 0 | UTF-8 text |
| image | 1 | JPEG/PNG/GIF/WebP bytes |
| video | 2 | MP4/WebM/MOV bytes |
| file | 3 | Raw bytes |
| link | 4 | UTF-8 URL |

Overhead = 7 + name + MIME bytes: 31 bytes total for "sos". The length fields are one byte each, so names and MIME types are limited to 255 bytes. Byte-level details: [Data Formats §2](../architecture/DATA_FORMATS.md).

**Completeness check (`looksComplete`).** Before decoding, the receiver checks that the structure is intact and the payload plausible:

| Type | Accepted when |
|---|---|
| text, link, file | Data is non-empty |
| image | `isDisplayableImage`: starts with a JPEG, PNG, GIF or WebP signature, ≥ 24 bytes |
| video | ≥ 512 bytes |

If the magic is present but the check fails, the status reads "Incomplete image/message (N B) — hold camera steady until all QR frames scan". With the fountain paths this essentially never happens, because an envelope is delivered only after a CRC-verified, complete decode.

Non-APCM bytes fall back to plain UTF-8 text (legacy "HELLO" messages) or, if not valid UTF-8, a `file` named `received.bin`.

---

## 5. Receiving and displaying

`AppController._addIncomingChat(raw)`:
1. `ChatPayloadCodec.decodeIncoming(raw, isOutgoing: false)` produces a `ChatMessage` with status `delivered`.
2. The message is appended to the chat, and the status line changes to "Photo received (N bytes) — displaying" or "Video received (N bytes) — playing".
3. Photos and videos are **auto-saved** to the Gallery on Android/iOS (see [§6](#6-saving-to-the-gallery)).

Display:

| Content | Widget | Detail |
|---|---|---|
| Photo in chat | `ChatBubble` | `Image.memory`; tap opens a pinch-zoom (`InteractiveViewer`) dialog |
| Photo, received view | `ReceivedContentView` | Written to a temp file `rx_img_<ms>.jpg` and displayed from it (falls back to `Image.memory`); tap for full-screen zoom |
| Video | `ReceivedContentView` | Written to a temp file, then played with `VideoPlayerController.file` |
| Link | `ReceivedContentView` | Opens in the external browser via `launchUrl` |
| File | Chat bubble | Name and size |

---

## 6. Saving to the Gallery

`GallerySaver` is a `ChangeNotifier` singleton built on the `gal` package.

| Aspect | Behaviour |
|---|---|
| Platforms | Android and iOS only (`isSupported`) |
| What | `image` and `video` messages with data |
| Album | **Adaptive Comm** |
| Permission | `Gal.hasAccess(toAlbum: true)`, else `Gal.requestAccess` |
| Method | Write a temp file `APC_<timestamp>.<ext>`, then `Gal.putImage` / `Gal.putVideo`; the temp file is always deleted |
| Extension | From the MIME type or file name: jpg/png/webp/gif for photos; mp4/webm/mov for videos |
| De-duplication | One `Future` per message ID (`putIfAbsent`), so the auto-save and the manual **Save to Gallery** button never save twice |
| Errors | "Gallery permission denied", "Not enough storage", "Format not supported by the gallery", "Could not save to gallery". A failure clears the entry so the user can retry |

The received-content view shows a **Save to Gallery** button, a spinner while saving, and "Saved to Gallery · Adaptive Comm" when done.

---

## 7. Bundled samples

`assets/samples/` is declared in `pubspec.yaml` and listed at runtime with `AssetManifest`, so any file dropped into those folders appears automatically.

**Catalogue rules (`SampleMedia`):**
- Recognised extensions: `jpg`/`jpeg`, `png` (images), `mp4`, `webm` (videos).
- The **title** is the file stem with the `_<N>kb` budget suffix removed, underscores turned into spaces, and the first letter capitalised. "qr" is shown as "QR". Example: `how_qr_codes_work_140kb.mp4` → "How QR codes work".
- `budgetKb` is parsed from the same suffix.
- Sort order: images first, then by title, then by budget.

**Photos**: four subjects × four budgets:

| Subject | 2 KB | 5 KB | 10 KB | 20 KB |
|---|---|---|---|---|
| Cat sketch | 2 047 B | 5 099 B | 10 073 B | 20 248 B |
| Future city | 2 032 B | 5 084 B | 10 230 B | 20 184 B |
| Night sky | 2 012 B | 5 114 B | 10 079 B | 20 444 B |
| Robot lab | 2 038 B | 5 097 B | 10 166 B | 20 143 B |

**Videos**: narrated explainers plus a sync test clip:

| File | Size | Codec | Content |
|---|---|---|---|
| `countdown_beeps_30kb.mp4` | 22 921 B | H.264 + AAC | 5 s test pattern with a beep every second (A/V sync check) |
| `speed_of_light_80kb.webm` | 80 014 B | VP9 + Opus | Explainer, the smallest with sound |
| `binary_numbers_130kb.mp4` | 126 994 B | H.264 + AAC | Explainer |
| `morse_code_130kb.mp4` | 131 899 B | H.264 + AAC | Explainer with real Morse beeps |
| `why_we_have_seasons_140kb.mp4` | 138 109 B | H.264 + AAC | Explainer |
| `how_qr_codes_work_140kb.mp4` | 139 179 B | H.264 + AAC | Explainer |
| `photosynthesis_140kb.mp4` | 139 937 B | H.264 + AAC | Explainer |
| `how_sound_travels_150kb.mp4` | 148 517 B | H.264 + AAC | Explainer |
| `the_water_cycle_160kb.mp4` | 161 179 B | H.264 + AAC | Explainer |

All explainers are 320×180 at 12 fps with mono narration.

---

## 8. Measured sample costs

Computed with the app's own code paths: send-time re-compression (q78), the envelope, the Auto density rule, the Light ETA formula, and Sound on the Standard profile.

**Photos** (the four subjects are within a few hundred bytes of each other, so ranges are shown):

| Tier | On disk | After send-time re-encode | Envelope | Light (Auto) | Sound (Standard) |
|---|---|---|---|---|---|
| 2 KB | ≈2.0 KB | 3.3–3.5 KB | 3 338–3 497 B | 160 B blocks, K = 21–22, **≈3 s** | K = 53–55, 69–71 frames, **≈2.7–2.8 min** |
| 5 KB | ≈5.1 KB | 8.5–8.7 KB | 8 530–8 730 B | 240 B blocks, K = 36–37, **≈5 s** | Over the 8 KiB limit → legacy path |
| 10 KB | ≈10.1 KB | 16.2–17.9 KB | 16 227–17 969 B | 330 B blocks, K = 50–55, **≈8–9 s** | Too large |
| 20 KB | ≈20.2 KB | 32.1–34.5 KB | 32 140–34 557 B | 330 B blocks, K = 98–105, **≈16–17 s** | Too large |

**Videos** (sent byte-for-byte, no re-encoding):

| File | Envelope | K (330 B) | Light ETA |
|---|---|---|---|
| Countdown beeps | 22 961 B | 70 | ≈11 s |
| Speed of light | 80 055 B | 243 | ≈38 s |
| Binary numbers | 127 034 B | 385 | ≈59 s |
| Morse code | 131 935 B | 400 | ≈61 s |
| Why we have seasons | 138 154 B | 419 | ≈64 s |
| How QR codes work | 139 222 B | 422 | ≈65 s |
| Photosynthesis | 139 977 B | 425 | ≈65 s |
| How sound travels | 148 560 B | 451 | ≈69 s |
| The water cycle | 161 220 B | 489 | ≈75 s |

These are typical-camera ETAs; a good camera at 25 cm is often faster, and a weak one slower.

---

## 9. Regenerating or adding samples

**Requirements:** Python 3, `pip install pillow imageio-ffmpeg` (bundles an ffmpeg binary). The narrated videos also need Windows, because they use the built-in System.Speech voices (Microsoft Zira).

```powershell
python tool/make_sample_media.py [photo_dir]        # photos (if photo_dir exists) + all videos
python tool/make_explainer_videos.py                # all explainers
python tool/make_explainer_videos.py morse_code     # one explainer by stem
```

**Photos (`fit_jpeg`).** Start at a 640 px long side. Binary-search the JPEG quality (5–92) for the largest file ≤ budget. Accept if quality ≥ 45; otherwise shrink the image by 8% and retry. The output is baseline (non-progressive), 4:2:0, optimised Huffman tables, with EXIF orientation applied and transparency flattened onto white.

**Explainer videos.** Each topic is data: a list of scenes, each pairing one narration line with a named "painter" function.
1. Every line is spoken offline by Windows TTS at 16 kHz and trimmed of silence.
2. Each scene lasts as long as its line (plus gaps). The Morse topic adds 660 Hz beeps timed to the drawing.
3. Chimes at the start and end and a quiet pad chord are mixed in.
4. Frames are drawn with Pillow at 2× supersampling, with 0.3 s cross-fades between scenes.
5. `encode()` does the size-targeted encode.

**`encode()` bitrate targeting:**

```
budget     = target_kb × 1024
total kbps = budget × 8 / 1000 / duration × 0.96
video kbps = total − audio kbps − 3 (MP4) or − 1 (WebM)
two-pass encode; if the file is over budget: video kbps × budget / size × 0.97, retry (up to 8 times)
```

- MP4: x264 `veryslow`, Main profile, `-tune animation`, keyframe every 120 frames, `+faststart`, AAC mono at 16 kHz with a 6 kHz cutoff for speech (20 kbps).
- WebM: VP9 `good`/`cpu-used 1`, Opus in `voip` mode (10 kbps).

**Adding your own file.** Drop `something_<N>kb.jpg|png|mp4|webm` into `assets/samples/images/` or `videos/` and rebuild. The catalogue picks it up automatically. Keep videos under about 150 KB for a demo-friendly Light transfer (about 70 s).

---

## 10. Choosing media for a demo

| Goal | Pick | Why |
|---|---|---|
| Instant "wow" | Any **2 KB** or **5 KB** photo over Light | Completes in 3–5 s |
| Show density switching | 5 KB, then 10 KB photo | The HUD shows K and the block size change (240 → 330) |
| Show a video | **Countdown beeps** (≈11 s) or **Speed of light** (≈38 s) | Short enough to hold attention |
| Show Sound with media | A 2 KB photo on **Fast** in a quiet room | ≈2 min; everything else is too long for sound |
| Show resilience | Any video; cover the camera mid-transfer | Progress holds, then continues |

See the [Showcase Guide](../getting-started/SHOWCASE_GUIDE.md) for the full demo script.
