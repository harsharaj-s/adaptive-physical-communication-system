# Permissions and Privacy

Every permission the app asks for, why it needs it, when it asks, and what happens if you say no. It also describes what data the app handles and where that data goes (in short: nowhere except the other phone, through the air in front of you).

Back to the [documentation index](../README.md).

---

## Contents

1. [Privacy summary](#1-privacy-summary)
2. [Android permissions](#2-android-permissions)
3. [iOS usage descriptions](#3-ios-usage-descriptions)
4. [Web](#4-web)
5. [When permissions are requested](#5-when-permissions-are-requested)
6. [If a permission is denied](#6-if-a-permission-is-denied)
7. [Data handling](#7-data-handling)
8. [Physical privacy](#8-physical-privacy)

---

## 1. Privacy summary

- **No network in the data path.** The app declares **no `INTERNET` permission** in its main manifest (Flutter adds one only to debug builds for hot reload). Messages move only as light, sound or vibration between phones in the same room.
- **No accounts, no analytics, no ads, no cloud.**
- **Nothing is stored** except what you choose to keep: received photos and videos are saved to your Gallery, and the chat history lives in memory until the app closes.
- **Anyone nearby can receive a Light or Sound broadcast.** There is no encryption ([Security](SECURITY.md)). Treat it like speaking out loud in a room.

---

## 2. Android permissions

From `android/app/src/main/AndroidManifest.xml`:

| Permission | Type | Why | Used by |
|---|---|---|---|
| `CAMERA` | Runtime (dangerous) | Read the sender's QR codes | Light receive |
| `RECORD_AUDIO` | Runtime (dangerous) | Hear the sender's tones | Sound receive |
| `MODIFY_AUDIO_SETTINGS` | Normal | Route audio for recording and playback | Sound |
| `VIBRATE` | Normal | Drive the vibration motor | Vibration send |
| `WAKE_LOCK` | Normal | Keep the screen on while streaming QR codes | Light send |
| `WRITE_EXTERNAL_STORAGE` (max SDK 29) | Runtime on Android ≤ 10 only | Save received media to the Gallery on old Android versions | Gallery saving |

Features `android.hardware.camera` and `android.hardware.microphone` are declared **not required**, so the app installs on devices without them (those channels are then unavailable).

Not needed:
- The **accelerometer** needs no permission on Android.
- **Screen brightness** is changed only for this app's window (`WindowManager.LayoutParams.screenBrightness` through the `apcs/optical_display` channel), which needs no permission. It is restored when streaming stops.
- **Gallery on Android 10+** uses MediaStore through `gal`, with no storage permission.

---

## 3. iOS usage descriptions

From `ios/Runner/Info.plist`. iOS shows these texts in the permission prompts:

| Key | Text shown to the user |
|---|---|
| `NSCameraUsageDescription` | "Camera is used to receive optical communication signals from nearby devices." |
| `NSMicrophoneUsageDescription` | "Microphone is used to receive acoustic communication signals from nearby devices." |
| `NSPhotoLibraryAddUsageDescription` | "Received photos and videos are saved to your photo library." |
| `NSPhotoLibraryUsageDescription` | "Received photos and videos are saved to the Adaptive Comm album." |
| `NSMotionUsageDescription` | "Motion sensors detect vibration patterns from a physically coupled nearby device." |

---

## 4. Web

Browsers ask for the camera and microphone the first time they're used, and only on **HTTPS or `localhost`** pages. There is no vibration motor access for this purpose and no Gallery saving on the web.

---

## 5. When permissions are requested

The app asks **only when a feature needs it**, never at start-up:

| Permission | Asked when | Code |
|---|---|---|
| Camera | You start receiving by **Light** | `HardwareOpticalChannel` → `Permission.camera.request()` |
| Microphone | You start receiving by **Sound** | `hardware_channels.dart` → `Permission.microphone.request()`, then `AudioRecorder.hasPermission()` |
| Photos / Gallery | The first photo or video is saved (automatically on receipt, or with **Save to Gallery**) | `GallerySaver` → `Gal.requestAccess(toAlbum: true)` |
| Motion (iOS) | Normally never: iOS gives raw accelerometer data without a prompt. The usage string is declared in case the system asks | `sensors_plus` accelerometer stream |

Sending by Light needs no permission (it only draws on the screen). Sending by Sound needs none either (it only plays audio).

---

## 6. If a permission is denied

| Denied | Effect | How to recover |
|---|---|---|
| Camera | Light receive shows no camera preview ("Camera permission denied" in the developer logs) | Settings → Apps → Adaptive Comm → Permissions → Camera, then reopen Receive |
| Microphone | Sound receive shows "Microphone permission required" and an **Enable microphone** button | Tap the button, or Settings → Apps → Adaptive Comm → Permissions → Microphone |
| Photos | The message still appears in the chat; the status reads "Photo received — Gallery permission denied". Nothing is lost | Allow photos in Settings, then tap **Save to Gallery** |

Other channels keep working when one permission is denied.

---

## 7. Data handling

| Data | Where it lives | How long |
|---|---|---|
| Messages you send | Memory (chat list); encoded into QR frames / audio / vibration | Until the app closes |
| Messages you receive | Memory (chat list) | Until the app closes, or you clear the chat |
| Received photos/videos | Also written to the Gallery album **Adaptive Comm** | Until you delete them |
| Temporary files | App temp directory: `rx_img_*.jpg`, video playback files, `APC_*` Gallery staging files (deleted right after saving) | Cleared by the OS or on reinstall |
| Camera frames | Luminance copied into memory for decoding, then discarded; never saved | Milliseconds |
| Microphone audio | Streamed through the decoder, never saved | Milliseconds |
| Accelerometer samples | Processed live, never saved | Milliseconds |
| Logs | In memory (developer screens) | Until the app closes |

No data is sent to any server, and there is no crash reporting or telemetry.

---

## 8. Physical privacy

Because the channels are physical, so is the privacy:

- **Light** can be read by any camera that sees the sender's screen, including one filming from across a room at high zoom. Shield the screen if the content is sensitive.
- **Sound** is audible to everyone nearby and can be recorded and decoded later.
- **Vibration** needs physical contact, so it's the most private channel, but also by far the slowest.

For confidential content, wait for the encryption item on the [Roadmap](../project/ROADMAP.md), or encrypt the file before sending it.
