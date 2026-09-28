# Installation and First Run

This guide takes you from a clean machine to the app running on a phone, in Chrome, and in the test suite. It covers Windows (the primary development machine for this project), macOS and Linux.

Back to the [documentation index](../README.md).

---

## Contents

1. [What you need](#1-what-you-need)
2. [Install Flutter](#2-install-flutter)
3. [Get the project](#3-get-the-project)
4. [Verify the code before touching a phone](#4-verify-the-code-before-touching-a-phone)
5. [Run on an Android phone](#5-run-on-an-android-phone)
6. [Run on an iPhone (macOS only)](#6-run-on-an-iphone-macos-only)
7. [Run in Chrome (web)](#7-run-in-chrome-web)
8. [Windows-specific notes](#8-windows-specific-notes)
9. [Project layout at a glance](#9-project-layout-at-a-glance)
10. [Next steps](#10-next-steps)

---

## 1. What you need

### Software

| Tool | Version used by the project | Notes |
|---|---|---|
| Flutter SDK | **3.41.1** (stable) | `flutter --version` |
| Dart SDK | **3.11.0** (bundled with Flutter) | `pubspec.yaml` requires `sdk: ^3.11.0` |
| Android SDK + platform tools | Recent, via Android Studio | Needed for APKs and `adb` |
| Java | 17 | The Android build uses `JavaVersion.VERSION_17` |
| Xcode | Recent | Only for iOS builds (macOS only) |
| Google Chrome | Any recent version | For the web build |
| Git | Any | |
| Python 3 + `imageio-ffmpeg` + Pillow | Optional | Only to regenerate demo media (see [Media Pipeline](../development/MEDIA_PIPELINE.md)) |

### Hardware

- **Two phones** for real transfers. Android is the best-tested platform.
- A USB cable per phone (or wireless debugging).
- Optional: a laptop with a webcam and Chrome can act as a Light or Sound *receiver*.

---

## 2. Install Flutter

1. Download the Flutter SDK from [flutter.dev](https://docs.flutter.dev/get-started/install) and unzip it to a path without spaces, e.g. `C:\src\flutter`.
2. Add `flutter\bin` to your `PATH`.
3. Run the doctor and fix anything it reports:

```powershell
flutter doctor -v
```

4. Accept the Android licences:

```powershell
flutter doctor --android-licenses
```

---

## 3. Get the project

```powershell
git clone https://github.com/harsharaj-s/adaptive_physical_communication_system.git
cd adaptive_physical_communication_system
flutter pub get
```

Clone into a short path without spaces (for example `C:\dev` on Windows); see [Windows-specific notes](#8-windows-specific-notes).

`flutter pub get` downloads every package listed in `pubspec.yaml`: camera, qr, zxing2, record, audioplayers, vibration, sensors_plus, permission_handler, wakelock_plus, image, file_picker, video_player, gal, path_provider, url_launcher and web.

---

## 4. Verify the code before touching a phone

```powershell
flutter analyze     # static analysis — should report "No issues found!"
flutter test        # full test suite — every test should pass
```

The tests include headless simulations of a phone camera and a room. When they pass, the Light and Sound pipelines work end to end on your machine. See [Testing](../development/TESTING.md) for details.

---

## 5. Run on an Android phone

1. On the phone, enable **Developer options**: Settings → About phone → tap *Build number* seven times.
2. Enable **USB debugging** in Developer options.
3. Connect the phone and accept the "Allow USB debugging?" prompt.
4. Check that Flutter sees it:

```powershell
flutter devices
```

5. Run it:

```powershell
flutter run                 # debug build, hot reload
flutter run --release       # release build, realistic performance
```

> **Use `--release` for any real transfer test.** Debug builds run the QR decoder and the audio DSP far slower, which gives a misleading picture of decode rates.

### Installing a pre-built APK instead

If someone gives you `app-release.apk`:

1. Copy it to the phone (USB, a cable to a laptop, or any file transfer).
2. Open it in the phone's Files app.
3. Allow "Install unknown apps" for that Files app when Android asks.
4. Tap **Install**.

Or, with the phone connected:

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

**Install the same build on both phones.** The Light frame format is versioned (`APCF` v3), and frames from a different version are rejected on purpose.

---

## 6. Run on an iPhone (macOS only)

```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # set your Team under Signing & Capabilities
flutter run --release
```

The first launch asks for camera, microphone, motion and photo permissions as each feature is used. The usage texts are in `ios/Runner/Info.plist`.

---

## 7. Run in Chrome (web)

```powershell
flutter run -d chrome
```

- **Light:** the web app can *receive* by webcam. A canvas sampler reads a 640×640 centre patch.
- **Sound:** send and receive both work, through the laptop's speaker and microphone.
- **Vibration:** not available (browsers have no vibration receiver).

Chrome asks for camera and microphone permission. Serve over `localhost` or HTTPS, because browsers block the camera on plain HTTP.

---

## 8. Windows-specific notes

- **Gradle download timeouts.** If the first Android build fails with "Connection timed out" while downloading the Gradle distribution, point Gradle at your normal cache:

```powershell
$env:GRADLE_USER_HOME = "$env:USERPROFILE\.gradle"
flutter build apk --release
```

- **Long paths.** Keep the project path short. Enable long paths if Git complains: `git config --system core.longpaths true`.
- **Antivirus.** Real-time scanning of `build\` and `%USERPROFILE%\.gradle` can make Android builds much slower. Consider excluding them.

---

## 9. Project layout at a glance

```
lib/            Dart source (UI, controller, modems, protocol, simulation)
test/           Unit, integration and simulation tests (+ camera and room models)
assets/samples/ Demo photos and narrated explainer videos bundled in the app
tool/           Python media generators and Dart debug scripts
android/ ios/ web/  Platform projects
docs/           This documentation
```

Full breakdown: [Architecture](../architecture/ARCHITECTURE.md#8-source-tree).

---

## 10. Next steps

- Try a transfer: [User Guide](USER_GUIDE.md).
- Prepare a demo: [Showcase Guide](SHOWCASE_GUIDE.md).
- Produce a release APK: [Build and Release](../operations/BUILD_AND_RELEASE.md).
