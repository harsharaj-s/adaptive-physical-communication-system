# Build and Release

How to produce installable builds for Android, iOS and the web, how versioning and signing work, and a checklist before handing a build to anyone. For setting up the toolchain in the first place, see [Installation](../getting-started/INSTALLATION.md).

Back to the [documentation index](../README.md).

---

## Contents

1. [Before any build](#1-before-any-build)
2. [Android](#2-android)
3. [Release signing (Android)](#3-release-signing-android)
4. [iOS](#4-ios)
5. [Web](#5-web)
6. [Versioning](#6-versioning)
7. [Icons, splash and generated assets](#7-icons-splash-and-generated-assets)
8. [Release checklist](#8-release-checklist)
9. [Build troubleshooting](#9-build-troubleshooting)

---

## 1. Before any build

```powershell
flutter --version          # Flutter 3.41.1 / Dart 3.11.0 used for this project
flutter pub get
flutter analyze            # expect: No issues found!
flutter test               # expect: 87 passed, 1 skipped
```

Never release a build that fails analysis or tests.

---

## 2. Android

### 2.1 Release APK (sideloading, demos)

```powershell
# Windows: keep Gradle's cache in your profile (avoids permission problems)
$env:GRADLE_USER_HOME = "$env:USERPROFILE\.gradle"
flutter build apk --release
```

Output: `build\app\outputs\flutter-apk\app-release.apk` (a universal APK, about 58 MB with the bundled samples).

Smaller per-architecture APKs:

```powershell
flutter build apk --release --split-per-abi
# app-arm64-v8a-release.apk is the one for almost every modern phone
```

Install on a connected phone:

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Or copy the APK to the phone and open it (allow "Install unknown apps" for your file manager).

### 2.2 App Bundle (Google Play)

```powershell
flutter build appbundle --release
# build\app\outputs\bundle\release\app-release.aab
```

Play requires a real release signing key ([§3](#3-release-signing-android)) and a final `applicationId`.

### 2.3 Build configuration

| Setting | Value | File |
|---|---|---|
| `namespace` / `applicationId` | `com.adaptive.physicalcomm.adaptive_physical_communication` (marked TODO) | `android/app/build.gradle.kts` |
| `minSdk` / `targetSdk` / `compileSdk` | Flutter defaults (`flutter.minSdkVersion` etc.) | Same |
| Java / Kotlin target | 17 | Same |
| Release signing | **Debug key** (so `flutter run --release` works) | Same |
| App label | "Adaptive Comm" | `AndroidManifest.xml` |
| Icons | `mipmap-*` + adaptive `mipmap-anydpi-v26` | `android/app/src/main/res` |

---

## 3. Release signing (Android)

The debug key is fine for demos. To publish, or to let users update without uninstalling, create a real key once and **keep it safe**: losing it means you can never update the app on Play.

1. Create a keystore (outside the repository):

   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\apcs-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias apcs
   ```

2. Create `android/key.properties` (**never commit it**; add it to `.gitignore`):

   ```properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=apcs
   storeFile=C:\\Users\\<you>\\apcs-release.jks
   ```

3. In `android/app/build.gradle.kts`, load it and use it for `release`:

   ```kotlin
   import java.util.Properties
   import java.io.FileInputStream

   val keystoreProperties = Properties().apply {
       val f = rootProject.file("key.properties")
       if (f.exists()) load(FileInputStream(f))
   }

   android {
       signingConfigs {
           create("release") {
               keyAlias = keystoreProperties["keyAlias"] as String?
               keyPassword = keystoreProperties["keyPassword"] as String?
               storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
               storePassword = keystoreProperties["storePassword"] as String?
           }
       }
       buildTypes {
           release { signingConfig = signingConfigs.getByName("release") }
       }
   }
   ```

4. Choose a final `applicationId` (e.g. `com.<yourname>.adaptivecomm`) **before** the first public release. It can never change afterwards.

Phones that have the debug-signed build installed must uninstall it before installing a release-signed one (the signatures differ).

---

## 4. iOS

Requires a Mac with Xcode and an Apple developer account.

```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace        # set Team and Bundle Identifier under Signing & Capabilities
flutter build ipa --release        # build/ios/ipa/*.ipa
```

| Item | Value |
|---|---|
| Display name | "Adaptive Physical Communication" (`CFBundleDisplayName`; shortened under the icon by iOS) |
| Usage strings | Camera, microphone, photo library (add and read), motion; see [Permissions and Privacy](PERMISSIONS_AND_PRIVACY.md) |
| Icons | `ios/Runner/Assets.xcassets/AppIcon.appiconset` (15 sizes, no alpha) |
| Launch screen | Dark background + logo (`LaunchScreen.storyboard`, `LaunchImage.imageset`) |

For a quick device test without TestFlight: connect the iPhone and run `flutter run --release`.

---

## 5. Web

```powershell
flutter build web --release
# build\web  → serve with any static server
```

- The **camera only works on HTTPS or `localhost`** (browser rule). For a phone on the same network, serve over HTTPS (e.g. a reverse proxy with a certificate).
- The web build can **send** Light (show QR codes) and **receive** Light with the camera. Vibration isn't available. Sound depends on the browser's audio and microphone support.
- The page shows the logo on the brand background until Flutter paints its first frame.

Local test:

```powershell
flutter run -d chrome
```

---

## 6. Versioning

`pubspec.yaml` holds `version: 1.0.0+1`:
- `1.0.0` is the user-visible version (`versionName` / `CFBundleShortVersionString`).
- `+1` is the build number (`versionCode` / `CFBundleVersion`), which must increase for every store upload.

`AppBrand.version` in `lib/ui/widgets/app_logo.dart` (shown in the About dialog) should be kept in step with `pubspec.yaml`.

Protocol compatibility is separate from the app version: two phones must share the same frame generation (see the [Changelog](../project/CHANGELOG.md#compatibility-rule)).

---

## 7. Icons, splash and generated assets

| Asset | Generator | Re-run when |
|---|---|---|
| App icons (Android, iOS, web), splash logos, in-app logo | `python tool/make_app_icon.py` | Changing the logo or brand colours |
| Demo photos and videos | `python tool/make_sample_media.py [photo_dir]` | Changing samples |
| Explainer videos only | `python tool/make_explainer_videos.py [stem …]` | Editing a topic |

The splash background colour `#0B1220` appears in `tool/make_app_icon.py`, `android/app/src/main/res/values/colors.xml`, `ios/Runner/Base.lproj/LaunchScreen.storyboard`, `web/index.html` and `web/manifest.json`. Change it everywhere together. See [Media Pipeline](../development/MEDIA_PIPELINE.md) for the sample generators.

---

## 8. Release checklist

- [ ] `flutter analyze` clean; `flutter test` green
- [ ] Version and build number bumped in `pubspec.yaml`; `AppBrand.version` matches
- [ ] Release signing configured (store builds) and `key.properties` **not** committed
- [ ] Final `applicationId` / bundle identifier
- [ ] Installed on **two real phones**; Light 2 KB photo and one video transfer; Sound text on Standard; Vibration "hi"
- [ ] Permissions prompt correctly on a fresh install (camera, microphone, photos)
- [ ] Launcher icon, splash and About dialog look right in light and dark system themes
- [ ] [Known Issues](../project/KNOWN_ISSUES.md) reviewed; nothing new and High open

---

## 9. Build troubleshooting

| Problem | Fix |
|---|---|
| Gradle fails with "access denied" or cache lock errors on Windows | Set `$env:GRADLE_USER_HOME = "$env:USERPROFILE\.gradle"`; close Android Studio; `flutter clean` |
| "SDK location not found" | Run `flutter doctor`; set `sdk.dir` in `android/local.properties` or `ANDROID_HOME` |
| Install fails with "signatures do not match" | Uninstall the old build first (debug vs release key) |
| `INSTALL_FAILED_OLDER_SDK` | The phone is below `minSdk`; use a newer phone |
| iOS: "No signing certificate" | Set the Team in Xcode → Runner → Signing & Capabilities |
| Web camera shows nothing | Serve over HTTPS or use `localhost`; allow camera access in the browser |
| Icons didn't change on the phone | The launcher caches icons: uninstall and reinstall, or restart the launcher |

More runtime problems: [Troubleshooting](TROUBLESHOOTING.md).
