# UI Guide

This guide describes the Flutter UI layer of the Adaptive Physical Communication System: how screens are connected, what state each screen reads from `AppController` and the global notifiers, which controller methods each user action calls, what every widget in `lib/ui/widgets/` does, how the full-screen QR overlay works, and how the responsive layout helpers are defined. It is written for developers who need to change or extend the UI. All constants below are copied from the code; where the code does something surprising, it is called out in [Known UI quirks](#12-known-ui-quirks) rather than smoothed over.

Back to the [documentation index](../README.md).

Related documents: [Architecture](../architecture/ARCHITECTURE.md), [API reference](API_REFERENCE.md), [Media pipeline](MEDIA_PIPELINE.md), and the channel guides for [Light](../channels/LIGHT_CHANNEL.md), [Sound](../channels/SOUND_CHANNEL.md) and [Vibration](../channels/VIBRATION_CHANNEL.md). The end-user view of the same screens is in the [User Guide](../getting-started/USER_GUIDE.md).

---

## Contents

1. [File map](#1-file-map)
2. [Navigation map](#2-navigation-map)
3. [App shell (`lib/main.dart`)](#3-app-shell-libmaindart)
4. [State management pattern](#4-state-management-pattern)
5. [Main screens](#5-main-screens)
6. [Developer tools screens](#6-developer-tools-screens)
7. [Widgets (`lib/ui/widgets/`)](#7-widgets-libuiwidgets)
8. [Models (`lib/ui/models/`)](#8-models-libuimodels)
9. [Theme and responsive layout](#9-theme-and-responsive-layout)
10. [The full-screen QR overlay](#10-the-full-screen-qr-overlay)
11. [Accessibility and back navigation](#11-accessibility-and-back-navigation)
12. [Known UI quirks](#12-known-ui-quirks)
13. [How to add a new screen](#13-how-to-add-a-new-screen)
14. [How to add a new channel option to the UI](#14-how-to-add-a-new-channel-option-to-the-ui)

---

## 1. File map

| Area | File | Contents |
|---|---|---|
| Shell | `lib/main.dart` | `AdaptiveCommApp`, theme, `AppProvider`, `_InheritedApp`, overlay `Stack` |
| Controller | `lib/application/app_controller.dart` | `AppController extends ChangeNotifier` (single state hub) |
| Screens | `lib/ui/screens/home_screen.dart` | `HomeScreen` |
| | `lib/ui/screens/send_compose_screen.dart` | `SendComposeScreen`, `_SamplePickerSheet`, `_AttachmentPreview` |
| | `lib/ui/screens/send_transmit_screen.dart` | `SendTransmitScreen`, `_ReadyBody`, `_OpticalTxView`, `_SoundTxView`, `_VibrateTxView`, `_ResultBody`, `_PulsingIcon` |
| | `lib/ui/screens/receive_screen.dart` | `ReceiveScreen`, `_ListeningBanner`, `_LightListenView`, `_ZoomChips`, `_SoundListenView`, `_LevelMeter`, `_VibrateListenView` |
| | `lib/ui/screens/dev_menu_screen.dart` | `DevMenuScreen` |
| | `lib/ui/screens/simulation_screen.dart` | `SimulationScreen` (Simulation Lab) |
| | `lib/ui/screens/hardware_screen.dart` | `HardwareScreen` (Hardware Channels) |
| | `lib/ui/screens/transfer_screen.dart` | `TransferScreen` (Legacy Messages) |
| | `lib/ui/screens/performance_screen.dart` | `PerformanceScreen` (Performance Comparison) |
| Widgets | `lib/ui/widgets/*.dart` | 18 files (including `app_logo.dart`), see [section 7](#7-widgets-libuiwidgets) |
| Models | `lib/ui/models/compose_payload.dart`, `physical_channel_mode.dart` | `ComposePayload`, `PhysicalChannelMode` |
| Theme | `lib/ui/theme/app_layout.dart` | Breakpoints, `PageContainer`, `SectionCard`, `StatusChip`, `EmptyState`, banners |
| UI state notifiers (core) | `lib/core/platform/platform_capabilities.dart`, `acoustic_receiver_state.dart`, `acoustic_transmitter_state.dart`, `vibration_transmitter_state.dart` | Global `ChangeNotifier` singletons used by the UI |

---

## 2. Navigation map

The app uses the imperative `Navigator` API only. There are no named routes, no `routes:` table and no `pushReplacement`. Every screen is pushed with `Navigator.push(context, MaterialPageRoute(builder: (_) => …))`. Choices in between screens are made with modal bottom sheets and dialogs.

```
MaterialApp(home: HomeScreen)
│   builder: Stack[ Navigator , OpticalActiveOverlay ]   ← overlay sits above every route
│
HomeScreen
├── [Send]  push ─► SendComposeScreen
│                   ├── [Image]/[Video] ─► FilePicker.platform.pickFiles (system UI)
│                   │                        └─ dialog "Large file" (if > 512 KB)
│                   ├── [Link] ─► dialog "Add link"
│                   ├── [Demo samples] ─► showModalBottomSheet(_SamplePickerSheet)
│                   └── [Continue to send]
│                         └─► showPhysicalModePicker("Choose transmission mode")
│                               └─ push ─► SendTransmitScreen(mode, payload)
│                                          (PopScope blocks pop while transmitting)
│
├── [Receive] push ─► ReceiveScreen
│                   └─ post-frame: showPhysicalModePicker("Choose receive mode")
│                        ├─ dismissed ─► Navigator.pop (back to Home)
│                        └─ chosen    ─► startListening(channel)
│                      [Change mode] icon ─► stopListening() + picker again
│                      image tap ─► showDialog(full-screen InteractiveViewer)
│
└── [⋮ Developer tools] push ─► DevMenuScreen
                                ├── push ─► SimulationScreen      ("Simulation Lab")
                                ├── push ─► HardwareScreen        ("Hardware Channels")
                                ├── push ─► TransferScreen        ("Legacy Messages")
                                │           ├─ [tune] ─► bottom sheet _ConnectionPanel
                                │           └─ [+]    ─► bottom sheet attach menu (ChatInputBar)
                                └── push ─► PerformanceScreen     ("Performance Comparison")
```

Leaving a screen is always a plain `Navigator.pop`. `SendTransmitScreen` returns to `SendComposeScreen` (the compose text is kept because the compose state object is still alive).

---

## 3. App shell (`lib/main.dart`)

`main()` calls `runApp(const AdaptiveCommApp())`. `AdaptiveCommApp.build` returns:

```
AppProvider(create: () => AppController())
└── MaterialApp(
      title: 'Adaptive Physical Communication',
      debugShowCheckedModeBanner: false,
      theme: …,                       // see section 9
      home: const HomeScreen(),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [ child ?? SizedBox.shrink(), const OpticalActiveOverlay() ],
      ),
    )
```

- **`AppProvider`** is a `StatefulWidget` that creates the controller once in `initState` and calls `_controller.dispose()` in `dispose`.
- **`AppProvider.of(context)`** looks up `_InheritedApp` with `dependOnInheritedWidgetOfExactType`, so the caller registers a dependency. It asserts `'AppProvider not found'` if missing.
- **`_AppProviderState.build`** wraps `_InheritedApp` in a `ListenableBuilder(listenable: _controller)`. `_InheritedApp.updateShouldNotify` always returns `true`.
- **The `builder` `Stack`** places `OpticalActiveOverlay` above the `Navigator`, so the transmit QR covers every route. See [section 10](#10-the-full-screen-qr-overlay).

The `AppController` constructor sets the global callback `onOpticalTransmitCancel = requestCancelTransfer;` which is what the overlay's **Stop** button calls.

---

## 4. State management pattern

### 4.1 One controller, one inherited widget

`AppController` is the only application-level `ChangeNotifier` created by the UI. Screens obtain it with `AppProvider.of(context)` and normally wrap their body in `ListenableBuilder(listenable: app, builder: …)`.

Because `_InheritedApp` is rebuilt on every `notifyListeners()` and `updateShouldNotify` returns `true`, **any widget that calls `AppProvider.of(context)` inside `build` is rebuilt on every controller notification**, with or without its own `ListenableBuilder`. The `MaterialApp` itself is *not* rebuilt, because `ListenableBuilder` passes the same `widget.child` instance each time and Flutter short-circuits identical child widgets. `PerformanceScreen` relies on this implicit rebuild; it has no `ListenableBuilder`.

Screens that need the controller outside `build` (for example in `dispose`) cache it: `ReceiveScreen` stores it in `_app` in a post-frame callback, and `HardwareScreen` stores it in `didChangeDependencies`.

### 4.2 Fine-grained notifiers for high-rate state

High-frequency updates (QR frames, camera metrics, microphone levels) do not go through `AppController.notifyListeners()`. They use separate notifiers so that only the small widget that displays them rebuilds:

| Notifier | Defined in | Type | Updated by | Listened to by |
|---|---|---|---|---|
| `opticalTransmitterState` | `core/platform/platform_capabilities.dart` | `OpticalTransmitterState` | Fountain QR / CSK modems (current bitmap, frame index, session, confidence) | `OpticalActiveOverlay`, `OpticalFountainQrOverlay`, `OpticalCskOverlay`, `_OpticalTxView`, `_LightListenView` (progress text), `HardwareScreen._OpticalSection` |
| `app.opticalMetricsNotifier` | `core/physical/optical_modem.dart` (`OpticalMetricsNotifier`) | per optical channel, may be `null` | Fountain QR receiver (`OpticalTransferMetrics`) | `_LightListenView` HUD and progress label, `_OpticalTxView` |
| `acousticReceiverState` | `core/platform/acoustic_receiver_state.dart` | `AcousticReceiverState` | Microphone callback (levels, phase, fountain progress) | `_SoundListenView`, `AcousticRxProgressCard`, `_ListeningBanner` (reads it directly) |
| `acousticTransmitterState` | `core/platform/acoustic_transmitter_state.dart` | `AcousticTransmitterState` | Sound fountain transmitter | `_SoundTxView`, `AcousticTxProgressCard` |
| `vibrationTransmitterState` | `core/platform/vibration_transmitter_state.dart` | `VibrationTransmitterState` | Vibration channel (motor state, accelerometer signal) | `_VibrateTxView`, `_VibrateListenView`, `HardwareScreen._VibrationSection` |
| `GallerySaver.instance` | `core/media/gallery_saver.dart` | `GallerySaver` | Save start / success / error | `_GallerySaveButton` |

Where the metrics notifier may not exist yet (the optical channel is created lazily), the UI falls back to the controller: `app.opticalMetricsNotifier ?? app`.

Several producers already throttle themselves: `AcousticReceiverState.setLevels` ignores changes of 0.02 or less, `setFountainProgress` only notifies when a value changes, and the acoustic channel limits UI level updates to one every 80 ms.

### 4.3 Rules of thumb

- Read controller state inside a `ListenableBuilder(listenable: app)` builder.
- For anything that updates more than a few times per second, listen to the specific notifier instead, and keep the listening subtree small.
- Never call `AppProvider.of(context)` in `dispose`; cache the controller earlier.
- Controller methods that start work set `app.running` to `true`; screens disable their buttons with `onPressed: app.running ? null : …`.

---

## 5. Main screens

### 5.1 `HomeScreen` (`home_screen.dart`)

**Purpose:** landing page with the two primary actions.

| Item | Detail |
|---|---|
| Constants | `appName = AppBrand.name` ('Adaptive Physical Communication'), `appTagline = AppBrand.tagline` ('Send messages without internet') |
| State read | None from the controller. Shows `physicalOnlyPolicySummary` (max 3 lines, ellipsis) and `platformCapabilityLabel` from `platform_capabilities.dart`. |
| Layout | `SafeArea` → `PageContainer` → `SingleChildScrollView`. Spacing is proportional to the screen: `size.height * 0.05` above the logo, `size.height * 0.06` above the buttons, `size.height * 0.04` below them. The logo is `AppLogo(size: (size.width * 0.3).clamp(96, 148))`. |
| Key widgets | `AppLogo` (see [§7](#7-widgets-libuiwidgets)); private `_ActionButton` (icon, label, subtitle, colour, `onTap`): `Material` with 12% tinted background, radius 20, `CircleAvatar` radius 28. |

| User action | Result |
|---|---|
| **ⓘ** (`IconButton`, tooltip `'About'`) | `showAppAboutDialog`: Flutter's About dialog with the logo, name, version and licences |
| **⋮** (`IconButton`, tooltip `'Developer tools'`) | `push` `DevMenuScreen` |
| **Send** (`'Compose and transmit a message'`, primary colour) | `push` `SendComposeScreen` |
| **Receive** (`'Listen for incoming messages'`, `Colors.tealAccent`) | `push` `ReceiveScreen` |

### 5.2 `SendComposeScreen` (`send_compose_screen.dart`)

**Purpose:** build a `ComposePayload` from typed text, a link, a picked file or a demo sample, then choose a channel.

| Item | Detail |
|---|---|
| Local state | `_textController`, `ComposePayload? _attachment` |
| Constant | `_maxHardwareBytes = 512 * 1024` (large-file warning threshold) |
| State read from controller | None. The screen does not touch `AppController`. |
| App bar | `'Compose message'` |
| Key widgets | `TextField` (hint `'Type a message, paste a link…'`, 4–8 lines), `_AttachChip` (`ActionChip`) ×4, `_AttachmentPreview` card, `FilledButton.icon` `'Continue to send'` |

| User action | What happens |
|---|---|
| **Image** chip | `_pickFile(FileType.image, ChatMessageType.image)`: `FilePicker.platform.pickFiles(withData: true)`, then `compressImageForTransfer(data)`. On `ImageTransferException` a `SnackBar` shows `e.message`. `.png/.webp/.gif` names are renamed to `.jpg` and the MIME becomes `image/jpeg`. |
| **Video** chip | `_pickFile(FileType.video, ChatMessageType.video)`; no transcoding. |
| Either picker, result > 512 KB | `AlertDialog` `'Large file'` with **Cancel** / **Use anyway**. (The size in the message uses the original `bytes.length`.) |
| **Link** chip | `_promptLink()`: `AlertDialog` `'Add link'` (hint `'https://example.com'`, **Cancel** / **Add**). Prefixes `https://` if the text does not start with `http`, and clears the text field. |
| **Demo samples** chip | `_pickSample()`: `showModalBottomSheet(isScrollControlled: true, showDragHandle: true)` with `_SamplePickerSheet`; the chosen `SampleMedia` is loaded with `sample.load()`. |
| **✕** on the preview (tooltip `'Remove attachment'`) | `_attachment = null` |
| **Continue to send** | `_buildPayload()`; if `null` or `isEmpty`, `SnackBar('Enter a message or attach content')`. Otherwise `showPhysicalModePicker(title: 'Choose transmission mode', subtitle: 'How should this message travel to nearby devices?')`, then `push` `SendTransmitScreen(mode: mode, payload: payload)`. |

`_buildPayload()` rules, in order:

1. If there is an attachment **and** non-empty text **and** the attachment is an image or video, return a **text** payload (the attachment is dropped).
2. Otherwise, if there is an attachment, return it.
3. If the text is empty, return `null`.
4. If `_looksLikeUrl(text)` (starts with `http://`, `https://`, `www.`, or matches `^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}`), return a **link** payload (`https://` prefixed if the text does not start with `http`).
5. Otherwise return a **text** payload.

`_mimeForExtension` maps `jpg/jpeg`, `png`, `gif`, `webp`, `mp4`, `mov` (`video/quicktime`), `webm`; anything else becomes `application/<ext>`.

**`_SamplePickerSheet`** loads `loadSampleMediaCatalog()` and every sample's byte length once (`late final Future`), in a `DraggableScrollableSheet(expand: false, initialChildSize: 0.7, maxChildSize: 0.95)`. It shows a spinner until loaded, then a header `'Demo samples'`, the note `'Built-in test files. Anything here works over Light; keep Sound to about 2 KB.'`, and two groups, `'Photos'` and `'Videos with sound'`. Each `ListTile` has a 48×48 leading preview (`Image.asset` for photos, a `play_circle_outline` icon for videos), `sample.title`, and the subtitle `'<bytes/1024 to 1 dp> KB · <EXT>'`. Tapping pops the sheet with the sample.

### 5.3 `SendTransmitScreen` (`send_transmit_screen.dart`)

**Purpose:** channel-specific send UI. Inputs: `PhysicalChannelMode mode`, `ComposePayload payload`.

**Local phase machine** (`enum _TxPhase { ready, transmitting, success, stopped, error }`):

```
ready ──[action button]──► transmitting ──► success   (Sound, Vibrate: sendPhysicalMessage returned true)
                                  │      ├─► stopped   (Light: returned true OR app.cancelRequested)
                                  │      ├─► ready     (non-Light and app.cancelRequested)
                                  │      └─► error     (returned false; message = app.statusMessage)
stopped ──[Resume streaming]──► transmitting
error   ──[Retry]──► ready
```

**Initialisation** (post-frame in `initState`): `app.configurePhysicalFlow(role: EndpointRole.sender, channel: widget.mode.channelId)`, and for Light `app.setOpticalTxProfile(OpticalTxProfile.auto)`. The density therefore resets to **Auto** every time the screen opens; the Sound profile is not reset.

**State read:** `app.opticalTxProfile`, `app.acousticTxProfile`, `app.acousticEtaSeconds(bytes)`, `app.statusMessage`, `app.cancelRequested`, `app.running`, `app.senderSnapshot`, `app.opticalTransferMetrics`, `app.opticalMetricsNotifier`, plus `opticalTransmitterState`, `acousticTransmitterState`, `vibrationTransmitterState`.

**Scaffold:** title `'Send via ${mode.label}'`; leading `IconButton(Icons.close, tooltip: 'Cancel')` → `_cancel()`. For Light while transmitting, the scaffold and app bar backgrounds are `Colors.white` with `Colors.black87` foreground (the overlay covers them anyway). The body is a `ListenableBuilder(listenable: app)` → `PageContainer` → `Column[ Expanded(_buildBody), _buildBottomActions ]`. Bottom actions are hidden only for Light while transmitting.

**Ready body (`_ReadyBody`):**

| Element | Light | Sound | Vibrate |
|---|---|---|---|
| Heading (`_readyTitle`) | `'Ready to transmit via QR'` | `'Ready to play'` | `'Ready to vibrate'` |
| Subtitle | `mode.subtitle` | `mode.subtitle` | `mode.subtitle` |
| Payload card | `payload.preview` + estimate line (below) | `payload.preview` | `payload.preview` |
| Tips card | `'Tips for a smooth transfer'` + 4 bullets + `'QR density'` `SegmentedButton<OpticalTxProfile>` over `OpticalTxProfile.values` | `'Tips for a smooth transfer'` + 3 bullets + `AcousticProfilePicker` + estimate line | none |
| Extra | | | `StatusChip('Contact required — 1:1 only', Icons.touch_app, StatusTone.warning)` because `!mode.supportsBroadcast` |

- **Light estimate line** (only when `payload.byteSize > 0`):
  `'${(byteSize / 1000).toStringAsFixed(byteSize >= 100000 ? 0 : 1)} KB · Fountain QR · ${opticalTxProfile.resolveFor(byteSize).blockLen} B/frame · ~${opticalTxProfile.estimatedSeconds(byteSize)}s'`.
  `estimatedSeconds` is `ceil((K + 2) / (txFps × expectedCaptureYield))`, with `expectedCaptureYield` 0.7 (≤ 160 B), 0.65 (≤ 240 B), 0.55 (≤ 330 B), otherwise 0.35.
- **Sound estimate line** (only when `payload.byteSize > 0`): `'${byteSize} B · ~${app.acousticEtaSeconds(byteSize)}s'`, where `acousticEtaSeconds` is `ceil(AcousticFountainModem.expectedSymbols(k) × profile.frameSeconds())`, `k = max(1, ceil(bytes / blockLen))` and `expectedSymbols(k) = ceil(1.25·k) + 2`.
- Both lines use `payload.byteSize` (the raw content), not the APCM envelope that is actually sent, so they slightly under-count (by the envelope header, and for demo photos by any size change from send-time recompression).
- `SegmentedButton.onSelectionChanged` → `app.setOpticalTxProfile(set.first)`; `AcousticProfilePicker.onChanged` → `app.setAcousticTxProfile`.

**Bottom actions:**

| Phase | Buttons | Calls |
|---|---|---|
| `ready` | `FilledButton.icon` with `_actionLabel`: `'Show QR & send'` (`Icons.grid_view_rounded`), `'Play & send'` (`Icons.play_arrow_rounded`), `'Start vibration'` (`Icons.vibration`) | `_startTransmit()` → `app.sendPhysicalMessage(payload: widget.payload, channel: widget.mode.channelId)` |
| `transmitting` (Sound, Vibrate) | `OutlinedButton.icon` `'Cancel transmission'` | `_cancel()` → `app.requestCancelTransfer()` then `Navigator.pop` |
| `success` | `FilledButton` `'Done'` | `Navigator.pop` |
| `stopped` | `OutlinedButton` `'Receiver shows DONE'`, `FilledButton.icon` `'Resume streaming'` | `Navigator.pop`; `_startTransmit()` again (the fountain modem resumes the same session with new symbol indices) |
| `error` | `OutlinedButton` `'Back'`, `FilledButton` `'Retry'` | `Navigator.pop`; `setState(_phase = ready)` |

**Result bodies (`_ResultBody`):** `'Sent successfully'` (`Icons.check_circle`, `lightGreenAccent`), `'Streaming stopped'` (`Icons.stop_circle_outlined`, `lightBlueAccent`), `'Send failed'` (`Icons.error_outline`, `redAccent`), each with `app.statusMessage` (or the captured `_errorMessage`) as subtitle.

**Transmitting bodies:**

- `_OpticalTxView`: `ListenableBuilder` over `Listenable.merge([opticalTransmitterState, app.opticalMetricsNotifier ?? app])`; text `'Streaming… tap Stop when the receiver shows DONE'` (or `app.statusMessage`), `'Point the receiver camera at this screen'`, and a compact `OpticalTransferHud`. The full-screen overlay is drawn on top, so this view is normally hidden.
- `_SoundTxView`: `ListenableBuilder(acousticTransmitterState)`; `_PulsingIcon(Icons.graphic_eq, lightBlueAccent, active: app.running || tx.playing)`, `'Playing acoustic tones…'`, the "keep playing" hint, `AcousticTxProgressCard(onCancel: app.cancelAcousticTransmit)`, and a `LinearProgressIndicator` from `app.senderSnapshot!.progress!.progressPercent` when not playing (protocol-path fallback).
- `_VibrateTxView`: `ListenableBuilder(vibrationTransmitterState)`; `_PulsingIcon(Icons.vibration, purpleAccent)`, `'Vibrating…'` / `'Transmitting…'`, `'Hold phones together — vibration is contact-only (1:1)'`.

`_PulsingIcon` is a `ScaleTransition` 1.0 → 1.15, 900 ms, `Curves.easeInOut`, repeating in reverse while `active`, `CircleAvatar` radius 52.

**Back handling:** see [section 11](#11-accessibility-and-back-navigation).

### 5.4 `ReceiveScreen` (`receive_screen.dart`)

**Purpose:** pick a receive channel, show the live listening UI, then show the received content.

| Local state | Meaning |
|---|---|
| `PhysicalChannelMode? _mode` | `null` until the picker returns; a spinner `Scaffold` is shown meanwhile |
| `AppController? _app` | cached for `dispose` |
| `String? _lastPresentedId` | id of the last incoming message already shown |
| `ChatMessage? _displayedMessage` | message currently on screen (`null` = listening view) |

**Lifecycle:**

1. `initState` → post-frame: cache `_app`, call `_pickMode()`.
2. `_pickMode()` → `showPhysicalModePicker(title: 'Choose receive mode', subtitle: 'How should this device listen for messages?')`. `null` → `Navigator.pop`. Otherwise reset `_displayedMessage` / `_lastPresentedId` and `await app.startListening(mode.channelId)`.
3. `dispose` → `_app?.stopListening()`.

**Showing messages:** `_resolveVisibleMessage(app)` reads `app.latestIncomingMessage`. If its id differs from `_lastPresentedId`, it schedules a post-frame `setState` that records the id and sets `_displayedMessage`, and returns the new message immediately so it is visible in the same frame. Otherwise it returns `_displayedMessage`.

**Layout:** `ListenableBuilder(listenable: app)` → `Scaffold(title: 'Receive via ${mode.label}', actions: [IconButton(Icons.tune, tooltip: 'Change mode')])` → `PageContainer` → `Column`:

- `_ListeningBanner` (always).
- If a message is showing: `Expanded(_ReceivedMediaPane)` (a `SingleChildScrollView` around `ReceivedContentView(compact: false)`), a caption (`'Playing received video — still listening for more'`, `'Photo received — still listening for more'` or `'Still listening — send another message anytime'`) and `OutlinedButton.icon('Clear & keep listening')`.
- Otherwise: `Expanded(_ListeningBody)`, which switches on the mode.

| User action | Calls |
|---|---|
| **Change mode** | `app.stopListening()` then `_pickMode()` |
| **Clear & keep listening** | `app.prepareForNextMessage()` then `_displayedMessage = null` |
| Tap camera preview | `app.opticalChannel?.focusAt(Offset(dx/width, dy/height))`, both clamped to 0..1 |
| Zoom chip | `channel.setZoom(z)` then `setState` |
| **Enable microphone** | `app.retryAcousticListening()` |

**`_ListeningBanner`** computes `listening = app.hardwareChannelsActive && !app.running` and returns a `_BannerBox` (tinted container, radius 14, 12% fill, 30% border). The first matching row wins:

| Sound mode condition | Title | Subtitle |
|---|---|---|
| message showing | `'Message received — still listening'` | `app.statusMessage` |
| phase `decoded` | `'Sound message decoded'` | `app.statusMessage` |
| phase `tonesDetected` | `'Tones detected — decoding…'` | `'Hold phones close until message appears'` |
| phase `permissionDenied` | `'Microphone blocked'` | `'Tap Enable microphone below'` |
| phase `starting` | `'Starting microphone…'` | `app.statusMessage` |
| listening and `app.acousticMicActive` | `'Mic live — listening for tones'` | `'Hold within ~30 cm of sender in a quiet room'` |
| listening | `'Waiting for microphone…'` | `app.statusMessage` |
| otherwise | `'Starting…'` | `app.statusMessage` |

| Light / Vibrate condition | Title | Subtitle |
|---|---|---|
| message showing | `'Message received — still listening'` | `app.statusMessage` |
| `app.opticalQrChunkProgress` = `(r, t)` with `r < t` | `'Receiving fountain QR $r / $t symbols'` | `'Keep camera aimed at the sender QR'` |
| listening | `'Listening on ${mode.label}'` | `mode.subtitle` |
| otherwise | `'Starting…'` | `app.statusMessage` |

**`_LightListenView`:** an `Expanded` `LayoutBuilder` → `ClipRRect(radius 16)` → `Stack(fit: expand)` of:

1. `GestureDetector(onTapUp: focusAt…)` around `OpticalCameraPreview(controller: app.opticalChannel?.cameraController, height: constraints.maxHeight)`;
2. `const OpticalAimGuide()`;
3. `Positioned(top: 8, right: 8, _ZoomChips)`;
4. `Positioned(left: 12, right: 12, bottom: 12)` → `ListenableBuilder(metricsListenable)` → `OpticalTransferHud(metrics: app.opticalTransferMetrics)`.

Below the preview, a `ListenableBuilder(Listenable.merge([opticalTransmitterState, metricsListenable]))` shows `OpticalTransferCompleteCard` when `m.complete && m.payloadBytes > 0`; otherwise a `LinearProgressIndicator` (`m.progress` when `symbolsNeeded > 0`, else `opticalTransmitterState.confidence`) and one label:

| Condition | Label |
|---|---|
| `m.locked && m.stalled` | `'Progress kept (${collected} / ${needed}) — re-aim: whole QR inside the square, hold steady'` |
| `m.locked` | `'Decoding — ${collected} / ${needed} symbols · keep steady'` |
| `confidence > 0.05` | `'Reading QR…'` |
| otherwise | `'Hold 15–25 cm away, whole QR inside the square · tap to refocus'` |

**`_ZoomChips`:** `static const _levels = [1.0, 1.5, 2.0, 3.0]`. Hidden (`SizedBox.shrink`) when there is no optical channel or `channel.maxZoom <= 1.01`. Levels outside `[minZoom − 0.01, maxZoom + 0.01]` are filtered out. The chip with `(channel.zoom - z).abs() < 0.05` is drawn white with black text. Labels are `'1x'`, `'1.5x'`, `'2x'`, `'3x'`. The container is `Colors.black` at 55% alpha, radius 20. The default zoom, `HardwareOpticalChannel.defaultReceiveZoom = 1.5`, is applied by the channel, not the widget.

**`_SoundListenView`:** `ListenableBuilder(acousticReceiverState)`. Status text, first match wins:

| Condition | Status |
|---|---|
| phase `permissionDenied` | `'Microphone permission required'` |
| phase `starting` | `'Starting microphone…'` |
| `rx.transferActive` | `'Receiving — ${collected} of ${needed} blocks'` |
| phase `tonesDetected` | `'Tones detected — decoding message'` |
| phase `decoded` | `'Message decoded — ready for next'` |
| phase `decoding` | `'Decoding tones…'` |
| mic live and `inputLevel < 0.03` | `'Mic live — waiting for audio (speak or play tones nearby)'` |
| mic live | `'Mic live — listening for sender tones'` |
| otherwise | `'Tap Enable microphone if listening does not start'` |

Then `_MicPulseIcon(active: micLive, detecting: tone > 0.12)` (1200 ms repeating scale up to 1.08, amber when detecting, light blue when active, `white38` otherwise), a help paragraph, `const AcousticRxProgressCard()`, two `_LevelMeter`s (`'Mic input'` from `rx.inputLevel`, `'Tone signal'` from `rx.toneStrength`, amber above 0.12; each an 8 px `LinearProgressIndicator` with a rounded percentage), a mic status row (`'Microphone streaming'` / `'Microphone not active'`), and `FilledButton.icon('Enable microphone')` when permission is denied or the mic is not live. `micLive` comes from `app.acousticMicActive`.

**`_VibrateListenView`:** `ListenableBuilder(vibrationTransmitterState)`; `'Detecting vibration…'`, the contact hint, and `'Signal ${(lastMagnitude * 100).toStringAsFixed(0)}%'` when `lastMagnitude > 0`. The vibration channel publishes `lastMagnitude` as `(|magnitude − baseline| / 6).clamp(0, 1)`.

---

## 6. Developer tools screens

### 6.1 `DevMenuScreen` (`dev_menu_screen.dart`)

App bar `'Developer tools'`, an explanatory line (`'These tools are for development and testing. The main app uses Send / Receive on the home screen.'`) and four `_DevTile`s (`Card` + `ListTile` with a tinted `CircleAvatar`):

| Tile title | Subtitle | Pushes |
|---|---|---|
| `'Simulation Lab'` | `'Virtual endpoints with adaptive channel switching'` | `SimulationScreen` |
| `'Hardware Channels'` | `'Test optical, acoustic, and vibration directly'` | `HardwareScreen` |
| `'Legacy Messages'` | `'Original transfer screen with logs and pairing'` | `TransferScreen` |
| `'Performance Comparison'` | `'Compare fixed vs adaptive strategies'` | `PerformanceScreen` |

### 6.2 `SimulationScreen` (`simulation_screen.dart`)

| Item | Detail |
|---|---|
| State read | `app.running`, `app.scenarioId`, `app.availableScenarios`, `app.senderSnapshot`, `app.receiverSnapshot`, `app.liveLogs`, `app.lastSimResult` |
| App bar | `'Simulation Lab'`; action `TextButton.icon` `'Run All Scenarios'` when wide, `'Run All'` on phones |
| Controls (`_Controls`) | `SectionCard('Scenario', Icons.science)` with a `DropdownButtonFormField<String>` (width 320 when wide, full width on phones; keyed by `ValueKey(app.scenarioId)`), **Run Simulation** / **Running…**, **Clear Logs** |
| Layout | Wide: `Row` of `EndpointPanel('Sender (A)')`, `EndpointPanel('Receiver (B)')`, `LogPanel`. Phone: `Column` with flex 2 / 2 / 3. |
| Result | `StatusChip('SUCCESS'/'FAILED')` from `app.lastSimResult` |

| Action | Calls |
|---|---|
| Dropdown change | `app.setScenario(v)` |
| **Run Simulation** | `app.runSimulation()` |
| **Clear Logs** | `app.clearLogs()` |
| **Run All Scenarios** / **Run All** | `app.runAllScenarios()` |

All actions are disabled while `app.running`.

### 6.3 `HardwareScreen` (`hardware_screen.dart`)

**Purpose:** raw channel tests. A `StatefulWidget` with `_messageController` (initial text `'HELLO'`). `dispose` calls `_app?.stopHardwareChannels()`.

| Section | Content |
|---|---|
| Not supported | `SectionCard('Not Available')` with `'Physical channels require a phone or Chrome browser on a laptop.'` |
| Banner | `PlatformCapabilityBanner` |
| `'Status'` | `app.statusMessage`; camera/TX line (`'Camera: active (receiver mode)'`, `'TX ready — camera off in sender mode'`, `'Channels off — tap Start, Test, or Send to activate.'`); a three-line channel explanation |
| `'Role & Message'` | `SegmentedButton<EndpointRole>` (**Sender** / **Receiver**), `TextField` `'Custom message'` |
| `_OpticalSection` | `'Optical Channel'` / `'QR code TX · Camera RX'`; `StatusChip` (`'QR TX i/n'`, `'QR TX'`, `'RX n%'` or `'Camera off'`) from `opticalTransmitterState`; `CameraPreview` when the camera is streaming, else an `EmptyState` |
| `_AcousticSection` | `'Acoustic Channel'` / `'Speaker TX · Microphone RX'` |
| `_VibrationSection` (phones only) | `'Vibration Channel'` / `'Phone only — motor TX · accelerometer RX'`; shows `'Accelerometer: x.x'` from `vibrationTransmitterState` |
| Log panel | `LogPanel` in a `SizedBox` of height 180 on phones, 220 otherwise |

Wide layouts place the optical section beside a column of acoustic and vibration sections.

| Button | Calls |
|---|---|
| Role segment | `app.setRole(sel)`, then `app.restartHardwareChannels()` if channels are active |
| **Test QR** | `app.testOpticalFlash()` |
| **Test Vibrate** (phones) | `app.testVibration()` |
| **Send Message** | `app.sendHardwareMessage(_messageController.text)` |
| **Send HELLO** | `app.sendHardwareHello()` |
| **Start** / **Stop** / **Restart** | `app.startHardwareChannels()` / `app.stopHardwareChannels()` / `app.restartHardwareChannels()` |
| App bar clear icon (tooltip `'Clear logs'`) | `app.clearLogs()` |

### 6.4 `TransferScreen` — Legacy Messages (`transfer_screen.dart`)

**Purpose:** the original chat-style screen using the protocol path (`sendChat`), with Simulation / Live and Broadcast / 1:1 switches.

| Item | Detail |
|---|---|
| Local state | `_messageController`, `_scrollController`, `_lastMessageCount` |
| Listener | `app.addListener(_onAppChanged)` in a post-frame callback; auto-scrolls (280 ms, `Curves.easeOutCubic`) when `chatMessages.length` grows. Removed in `dispose` inside a `try/catch`. |
| App bar | Title `'Messages'` with a subtitle `'<Sender/Receiver> · <Hardware/Simulation>[ · Broadcast| · 1:1] · <platformCapabilityLabel>'`; `IconButton(Icons.tune, tooltip: 'Connection & logs')`; `PopupMenuButton` with **Clear chat** / **Clear logs** |
| `_RoleModeBar` | `SegmentedButton`s: role (**Send** / **Receive**), mode (**Sim** / **Live**, Live disabled when `!isPhysicalChannelSupported`), and in Live mode transfer mode (**Broadcast** / **1:1**). Stacked on phones; a `Wrap` with widths 240 / 180 / 260 otherwise. A 3 px progress bar while busy. |
| `_ConnectionStatusBanner` | Live mode only. States: `'Receiving…'`/`'Sending…'`, `'Message received'` (within 8 s of `lastIncomingAt`), `'Listening (broadcast)'`/`'Listening'`, `'Broadcast ready'`/`'Sender ready'`, `'Channels starting…'`. A 9 s `Timer` forces a rebuild so the "recently received" state expires. |
| Camera preview | `OpticalCameraPreview` (height 160 on phones, 200 otherwise) for a Live receiver with active channels |
| `_ChatArea` | Empty state with `PairingInstructionsCard` and a five-step `'How to send'` card, or a `ListView.builder` of `_AnimatedIncomingBubble(ChatBubble)` (320 ms fade + slide; green glow for messages within 2 s of `lastIncomingAt`) |
| `_LivePairingHint` | One-line role/mode hint in Live mode |
| `ChatInputBar` | Enabled when not busy and (sender or simulation). Hint `'Receiver mode — waiting for incoming messages'` for a Live receiver. |
| `_ConnectionPanel` (bottom sheet) | `DraggableScrollableSheet` (initial 0.85 wide / 0.92 phone, min 0.5, max 0.95) with status, `PlatformCapabilityBanner`, **Start channels** / **Stop** (Live), **Send HELLO**, two `EndpointPanel`s (side by side at height 280 when wide; stacked at height 160 each on phones) and a `LogPanel` (220 wide / 180 phone) |

| Action | Calls |
|---|---|
| Role / mode / transfer-mode segments | `app.setRole`, `app.setMode`, `app.setTransferMode` |
| Send text | `app.sendChatText(text)` |
| Attach image / video / file | `FilePicker` → optional `'Large file'` dialog (limit 512 KB in Live, 2 MB in Simulation; buttons **Cancel** / **Send anyway**) → `app.sendChat(type:, payload:, fileName:, mimeType: 'application/<ext>')` |
| **Start channels** / **Stop** | `app.startHardwareChannels(forRole: app.role)` / `app.stopHardwareChannels()` |
| **Send HELLO** (sender only) | `app.sendChatText('HELLO')` |
| **Clear chat** / **Clear logs** | `app.clearChat()` / `app.clearLogs()` |

This is the only screen that can send generic files (`FileType.any`).

### 6.5 `PerformanceScreen` (`performance_screen.dart`)

| Item | Detail |
|---|---|
| State read | `app.running`, `app.comparisonResults` (rebuilt implicitly through `AppProvider.of`) |
| Header | `SectionCard('Baseline Comparison', 'Fixed-channel vs adaptive strategy (simulation)')` with **Run Comparison** / **Running…** → `app.runPerformanceComparison()` |
| Results | `EmptyState('Run comparison to see results')` until results exist. Wide: `GridView` with 3 columns on desktop, 2 on tablet, `childAspectRatio: 1.3`, spacing 12. Phone: `ListView.separated` with 8 px gaps. |
| `_ResultCard` | `strategyLabel(result.strategy)`, then Duration (ms), Throughput (kbps = /1000), Goodput (KB/s = /1024), Packet Loss (%), Retransmissions, Channel Switches |

---

## 7. Widgets (`lib/ui/widgets/`)

**Repaint boundaries:** no file under `lib/` uses `RepaintBoundary`. Rendering cost is controlled instead by small `ListenableBuilder` subtrees and by `CustomPainter.shouldRepaint`. If profiling shows the QR overlay repainting neighbouring layers, wrapping `QrBitmapView` in a `RepaintBoundary` is the obvious first experiment; it is not done today.

| Widget | File | Purpose | Inputs | Used in |
|---|---|---|---|---|
| `AppLogo` | `app_logo.dart` | The app logo from `assets/branding/`: the full launcher tile, or `markOnly` (transparent; its white centre needs a dark surface) | `double size = 48`, `bool markOnly = false` | `HomeScreen`, `DevMenuScreen` About tile, About dialog |
| `BrandedTitle` | `app_logo.dart` | App bar title with the logo mark (34 px) before the text, optional subtitle | `String title`, `Widget? subtitle` | App bars of every screen except the Light-transmitting phase of `SendTransmitScreen` (white bar) |
| `showAppAboutDialog` / `AppBrand` | `app_logo.dart` | About dialog with licences; `AppBrand` holds the name, short name, tagline, version and asset paths | `BuildContext` | `HomeScreen` ⓘ, `DevMenuScreen` |
| `AcousticRxProgressCard` | `acoustic_transfer_hud.dart` | Sound receive progress (blocks, frames, damaged) | none (reads `acousticReceiverState`) | `ReceiveScreen._SoundListenView` |
| `AcousticTxProgressCard` | `acoustic_transfer_hud.dart` | Sound playback progress with **Stop** | `VoidCallback? onCancel` | `SendTransmitScreen._SoundTxView` |
| `AcousticProfilePicker` | `acoustic_transfer_hud.dart` | Sound speed chips | `AcousticTxProfile selected`, `ValueChanged<AcousticTxProfile> onChanged`, `bool enabled = true` | `SendTransmitScreen._ReadyBody` |
| `ChatBubble` | `chat_bubble.dart` | Chat message bubble | `ChatMessage message` | `TransferScreen` |
| `ChatInputBar` | `chat_input_bar.dart` | Text field, attach sheet, send button | `controller`, `enabled`, `onSend`, `onPickImage`, `onPickVideo`, `onPickFile`, `hintText = 'Type a message…'` | `TransferScreen` |
| `EndpointPanel` | `endpoint_panel.dart` | Transfer dashboard for one endpoint | `String title`, `DashboardSnapshot? snapshot`, `String? emptyMessage` | `SimulationScreen`, `TransferScreen` |
| `LogPanel` | `log_panel.dart` | `'LIVE LOGS'` list | `List<LogEntry> logs`, `String? emptyMessage` | `SimulationScreen`, `HardwareScreen`, `TransferScreen` |
| `showPhysicalModePicker` | `mode_picker_sheet.dart` | Light / Sound / Vibrate bottom sheet | `BuildContext`, `required String title`, `String? subtitle` → `Future<PhysicalChannelMode?>` | `SendComposeScreen`, `ReceiveScreen` |
| `OpticalActiveOverlay` | `optical_active_overlay.dart` | Chooses the fountain or CSK overlay while transmitting | none | `main.dart` builder |
| `OpticalFountainQrOverlay` | `optical_fountain_qr_overlay.dart` | Full-screen white field, QR and **Stop** | none | `OpticalActiveOverlay` |
| `OpticalCskOverlay` | `optical_csk_overlay.dart` | Legacy 2×2 colour mosaic with **Cancel** | none | `OpticalActiveOverlay` |
| (re-export) | `optical_qr_overlay.dart`, `optical_flash_overlay.dart` | Each contains only `export 'optical_csk_overlay.dart';` | — | Not imported anywhere |
| `OpticalAimGuide` | `optical_aim_guide.dart` | Corner brackets for the decoder crop | `Color color = Colors.white70` | `ReceiveScreen._LightListenView` |
| `OpticalCameraPreview` | `optical_camera_preview.dart` | Camera preview or `'Starting camera…'` | `CameraController? controller`, `double height = 120` | `ReceiveScreen`, `TransferScreen` |
| `OpticalTransferCompleteCard` | `optical_transfer_complete_card.dart` | Green `'Transfer complete'` card | `OpticalTransferMetrics metrics`, `VoidCallback? onDismiss` | `ReceiveScreen._LightListenView` |
| `OpticalTransferHud` | `optical_transfer_hud.dart` | Live Light metrics strip | `OpticalTransferMetrics metrics`, `bool compact = false` | `ReceiveScreen` (full), `SendTransmitScreen._OpticalTxView` (compact) |
| `QrBitmapView` | `qr_bitmap_view.dart` | Pixel-snapped QR painter | `QrBitmap bitmap`, `int quietModules = 4` | `OpticalFountainQrOverlay` |
| `ReceivedContentView` | `received_content_view.dart` | Received text / link / image / video / file card plus Gallery button | `ChatMessage message`, `bool compact = false` | `ReceiveScreen._ReceivedMediaPane` |

### 7.1 `acoustic_transfer_hud.dart`

- **`AcousticRxProgressCard`**: a `ListenableBuilder(acousticReceiverState)` that returns `SizedBox.shrink()` unless `rx.transferActive` (`needed > 0 && collected < needed`). Shows `'Receiving over sound'` or `'Receiving over sound · ${rx.profileLabel}'`, the percentage `round(transferFraction × 100)`, an 8 px bar, `'${collected} of ${needed} blocks · ${framesRepaired} frames read'` plus `' · ${framesRejected} too damaged'` when non-zero, and `'Keep the sender playing until this completes.'` It deliberately shows blocks, not bytes (see the class doc comment).
- **`AcousticTxProgressCard`**: a `ListenableBuilder(acousticTransmitterState)` that hides unless `tx.playing`. Header `'Playing ${totalBytes} B · ${profileLabel}'` with a `TextButton('Stop')` when `onCancel != null`. The bar is indeterminate while `fraction == 0`; `fraction = symbolsSent / symbolsPlanned` clamped to 1, where the planned count is `ceil(1.25·K) + 2`, so the bar stays full while the rateless stream continues. Footer `'Turn the volume up and point the speaker at the other phone. About ${estimateSeconds.round()}s if it is heard cleanly.'`
- **`AcousticProfilePicker`**: title `'Sound speed'`; a `Wrap` of `ChoiceChip`s over `AcousticTxProfile.values.reversed` (so **Fast, Standard, Safe, Rugged**), each labelled `'${label} · ${netBytesPerSecond().round()} B/s'` (36, 27, 18 and 11 B/s); caption `'${selected.conditionHint}. The receiving phone detects the speed by itself.'` Chips are disabled when `enabled` is false.

### 7.2 `chat_bubble.dart` and `chat_input_bar.dart`

- **`ChatBubble`**: max width 82% of the screen. Outgoing bubbles use `primaryContainer`; incoming use `tertiaryContainer` at 55% with a green border, a sensor avatar and a `'Received'` label. The footer shows `HH:mm`, a status icon and label (`'Sending…'`, `'Sent'`, `'Delivered'`/`'Received'`, `'Failed'`) and the size. Text and links are `SelectableText`; images are `Image.memory` (height 200, tap for a full-screen `InteractiveViewer` dialog); videos and files are attachment cards.
- **`ChatInputBar`**: `Material(elevation: 8)` with an attach `IconButton` (tooltip `'Attach'`), a 1–4 line `TextField` (submits on enter), and a circular send `FilledButton`. The attach sheet offers **Photo / Image**, **Video** and **Document / File**.

### 7.3 `endpoint_panel.dart` and `log_panel.dart`

- **`EndpointPanel`**: `EmptyState('Waiting for transfer')` when `snapshot == null`; otherwise the title, a `StatusChip` with `transferStateLabel(state)` (success for `completed`, error for `failed`, warning for `degraded`/`switchingChannel`/`recovering`, info otherwise), Channel, Score, Confidence, Throughput (kbps), Packet Loss (red above 10%), Latency, a progress bar with Progress/Packets/Retries, a `'CHANNELS'` score-bar list and a `'SWITCH EVENTS'` list (`'A → B @ pkt n'`).
- **`LogPanel`**: `'LIVE LOGS'` header with a count chip; `EmptyState('Logs will appear here during transfer')` when empty; otherwise a `ListView.builder` of monospace 12 px lines prefixed `[CATEGORY]`, coloured `WARNING` amber, `ERROR` red, `DECISION` green, `SWITCH` purple, `ADAPT` cyan, `TRANSFER` light blue, anything else blue.

### 7.4 `mode_picker_sheet.dart`

`showPhysicalModePicker` opens `showModalBottomSheet<PhysicalChannelMode>(showDragHandle: true)` with the title, optional subtitle, one `_ModeTile` per `availablePhysicalModes` (so Vibrate is absent on web), and the footer `'Tip: Light uses fountain QR — hold phones 15–25 cm apart.'` Each `_ModeTile` shows the mode's icon (tinted `amberAccent`, `lightBlueAccent` or `purpleAccent`), label, subtitle, and for non-broadcast modes `'1:1 only — phones must touch'` in orange. Tapping pops the sheet with the mode; dismissing returns `null`.

### 7.5 Optical overlays

- **`OpticalActiveOverlay`**: `ListenableBuilder(opticalTransmitterState)`; `SizedBox.shrink()` when not transmitting, `OpticalFountainQrOverlay` when `isFountainQr` (`modemId == 'fountain_qr'`), otherwise `OpticalCskOverlay`.
- **`OpticalFountainQrOverlay`**: re-checks `transmitting && isFountainQr`; while `tx.qrBitmap == null` it paints a plain white `ColoredBox`. Otherwise a white `Material` → `SafeArea` → `Column`: header `'Streaming… tap Stop when the receiver shows DONE'`, a tabular-figure status line `'${profileLabel} · ${fountainBlockLen} B/frame · ${kb} KB · K=${fountainK} · frame ${chunkIndex}'` (KB = `fountainFileLen / 1000`, one decimal below 10 KB; the KB part is omitted when the length is 0), an `Expanded` centred `QrBitmapView` with 4 px horizontal padding, and a full-width black `FilledButton.icon('Stop')` that calls `onOpticalTransmitCancel?.call()`.
- **`OpticalCskOverlay`**: black `Material` with a pill `'CSK light TX — byte $index / $total'`, a 2×2 grid of `ColoredBox`es from `cskCells` (black during guard intervals), the caption `'Receiver camera reads red / green / blue / white cells'`, and a **Cancel** button at top-left calling `onOpticalTransmitCancel`. The current Send screens never select the CSK modem.

### 7.6 `OpticalAimGuide`

An `IgnorePointer` + `CustomPaint` filling its parent. It draws four L-shaped brackets around a centred square of side `size.shortestSide − 2 × 20` (`inset = 20.0`), with arms `len = 36.0` long, `strokeWidth = 3`, round caps. Nothing is drawn if the side is `<= 72`. `shouldRepaint` only compares the colour, so it never repaints with the camera.

### 7.7 `OpticalCameraPreview`

Shows `'Starting camera…'` (12 px) in a box of the given height while the controller is `null` or not initialised; otherwise `ClipRRect(radius 8)` around `CameraPreview`. It does not start or stop the camera; that is the channel's job.

### 7.8 `OpticalTransferCompleteCard`

Green container (12% fill, 45% border, radius 14), title `'Transfer complete'`, optional close button when `onDismiss` is set (no caller sets it), and `'${kb} KB in ${secs}s (${rate} KB/s)'` with KB = `payloadBytes / 1000` (no decimals from 100 KB) and seconds to one decimal; the rate part is omitted when it is 0.

### 7.9 `OpticalTransferHud`

A black container at 72% alpha with a `white24` border (padding 10×8 compact, 12×10 full):

- Row 1: `_LockChip` (`'DONE'` light green when `complete`, `'LOCK'` light blue when `locked`, otherwise `'SCAN'` `white54`), `'SID <hex>'` when a session exists, and `metrics.profileLabel` on the right (`'K=<K>'` once a decoder exists, otherwise the receiver profile label).
- Row 2 (`Wrap`): `CAP` (0 dp), `DEC` (1 dp), `DROP`, `GOOD` (`x.x KB/s`), and in full mode `NEW/DUP/RED`.
- When `symbolsNeeded > 0`: a 4 px bar and `'${collected} / ${needed} symbols · ${blockLen} B'`.
- When `stalled`: an amber row, `'Progress kept. '` (only if locked) + `'No codes readable — whole QR inside the square at 15–25 cm, hold steady, tap to refocus, or try 2x zoom'`.

Numbers use `FontFeature.tabularFigures()` so the strip does not jitter as digits change. The modem computes `stalled` as `!complete && captureFps > 2 && staleSeconds >= 4`.

### 7.10 `QrBitmapView` (pixel snapping)

```
available     = constraints.biggest.shortestSide            (logical px)
availablePx   = available × devicePixelRatio                 (device px)
totalModules  = bitmap.size + quietModules × 2               (quiet zone 4 → +8)
modulePx      = floor(availablePx / totalModules)            (whole device pixels)
if modulePx < 1 → SizedBox.shrink()
sideLogical   = modulePx × totalModules / devicePixelRatio
```

The widget sizes itself to exactly `sideLogical`, so every module is an integer number of device pixels. `_QrBitmapPainter` fills the square white, then draws dark modules with `isAntiAlias = false`, merging each horizontal run of dark modules into a single `drawRect` (far fewer draw calls than one per module). `shouldRepaint` returns true only when the `bitmap` instance, `modulePx` or `quietModules` changes, so the painter repaints once per new QR frame (up to 12 per second) and never in between. The bitmap itself is built by the modem off the paint path and published with `opticalTransmitterState.setFountainQrBitmap`.

### 7.11 `ReceivedContentView`

`Card` (padding 12 compact / 20 full) with a header row (type icon, type label `'Text message'`/`'Link'`/`'Image'`/`'Video'`/`'File'`, size as `B`/`KB`/`MB` with 1024 steps), the content, and `_GallerySaveButton` when `GallerySaver.canSave(message) && GallerySaver.instance.isSupported`.

| Private widget | Behaviour |
|---|---|
| Text | `SelectableText`, 16 px, line height 1.5 |
| `_LinkContent` | Underlined `SelectableText` and `FilledButton.icon('Open link')` → `launchUrl(uri, mode: LaunchMode.externalApplication)`; snackbars `'Invalid URL'` / `'Could not open link'` |
| `_ImageContent` | Writes the bytes to `<temp>/rx_img_<ms>.jpg` and shows `Image.file` (height 220 compact / 420 full, `BoxFit.contain`, high filter quality); falls back to `Image.memory` if the file cannot be written or decoded; final fallback `'Could not display image — data may be incomplete'`. Tap → `showDialog` with a black `Dialog` containing `InteractiveViewer(Image.memory)` (pinch zoom). |
| `_VideoPlayerWidget` | Writes `<temp>/rx_video_<ms>.<mp4|webm|mov>`, `VideoPlayerController.file`, then `initialize`, `setLooping(true)`, `setVolume(1.0)`, `play()`. Shows an `AspectRatio` player (16:9 if unknown) with a play overlay while paused, an `IconButton.filled` play/pause, and `'mm:ss / mm:ss'`. A controller listener calls `setState` on every tick. Error: `'Could not play video (N bytes)'`. |
| `_FileContent` | File icon, `fileName ?? 'Received file'`, size. No open/save action. |
| `_GallerySaveButton` | `ListenableBuilder(GallerySaver.instance)`: disabled `'Saved to Gallery · Adaptive Comm'` (green tick) → disabled `'Saving to Gallery…'` (spinner) → `FilledButton.tonalIcon` `'Save to Gallery'`, or `'Retry save'` with the orange error text below. Tapping calls `saver.save(message)`. |

The controller auto-saves photos and videos on arrival (`_autoSaveToGallery`), and `GallerySaver` de-duplicates by message id, so the button normally shows the saving/saved state straight away.

---

## 8. Models (`lib/ui/models/`)

### 8.1 `ComposePayload`

An immutable description of an outgoing message, produced by `SendComposeScreen` and consumed by `SendTransmitScreen` and `AppController.sendPhysicalMessage`.

| Member | Meaning |
|---|---|
| `ChatMessageType type` | text, image, video, file or link |
| `Uint8List data` | Content bytes (for text and link, `text.codeUnits`) |
| `String? text` | Text or URL for text/link payloads |
| `String? fileName`, `String? mimeType` | For attachments |
| `int get byteSize` | `data.length` |
| `String get preview` | Text, URL, or file name, falling back to `'Link'`, `'Image'`, `'Video'`, `'File'` |
| `Uint8List toEnvelope()` | `ChatPayloadCodec.encodeText(text)` / `encodeLink(text)` when `text` is set, otherwise `ChatPayloadCodec.encode(type:, data:, fileName:, mimeType:)` |
| `bool get isEmpty` | For text/link: trimmed `text` is empty; otherwise `data.isEmpty` |

For images, the controller does not call `toEnvelope()`; `_prepareEnvelope` re-runs `compressImageForTransfer` and encodes with `fileName ?? 'photo.jpg'` and `image/jpeg`. See [Media pipeline](MEDIA_PIPELINE.md).

### 8.2 `PhysicalChannelMode`

`enum PhysicalChannelMode { light, sound, vibrate }` with the extension `PhysicalChannelModeX`:

| Getter | light | sound | vibrate |
|---|---|---|---|
| `label` | `'Light'` | `'Sound'` | `'Vibrate'` |
| `subtitle` | `'Animated QR — camera to screen, no Wi‑Fi (hold 15–25 cm)'` | `'Speaker tones — text and small files, across a room'` | `'Contact-only — short text, phones pressed together'` |
| `icon` | `Icons.flashlight_on` | `Icons.volume_up_rounded` | `Icons.vibration` |
| `channelId` | `CommChannelId.optical` | `CommChannelId.acoustic` | `CommChannelId.vibration` |
| `supportsBroadcast` | `true` | `true` | `false` |
| `isAvailable` | `isPhysicalChannelSupported` | `isPhysicalChannelSupported` | `isVibrationSupported` |

Top-level helpers: `availablePhysicalModes` (values filtered by `isAvailable`) and `channelIdToPhysicalMode(CommChannelId)` (currently unused). `isPhysicalChannelSupported` is true on Android, iOS and web; `isVibrationSupported` only on Android and iOS.

---

## 9. Theme and responsive layout

### 9.1 Theme (`lib/main.dart`)

| Setting | Value |
|---|---|
| Colour scheme | `ColorScheme.fromSeed(seedColor: Color(0xFF3B82F6), brightness: Brightness.dark)` |
| Material 3 | `useMaterial3: true` |
| Font | `fontFamily: 'Roboto'` |
| App bar | `AppBarTheme(centerTitle: false)` |
| Filled buttons | `RoundedRectangleBorder(borderRadius: 12)` |
| Cards | `CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: 16))` |
| Inputs | `InputDecorationTheme(border: OutlineInputBorder(borderRadius: 12), filled: true)` |

Channel accent colours used across the UI: Light `Colors.amberAccent`, Sound `Colors.lightBlueAccent`, Vibrate `Colors.purpleAccent`, success `Colors.lightGreenAccent`.

### 9.2 Breakpoints and helpers (`lib/ui/theme/app_layout.dart`)

| Name | Definition |
|---|---|
| `enum ScreenSize` | `phone`, `tablet`, `desktop` |
| `AppBreakpoints.phone` | `600` |
| `AppBreakpoints.tablet` | `1024` |
| `screenSizeOf(context)` | `width < 600` → `phone`; `width <= 1024` → `tablet`; otherwise `desktop` (width from `MediaQuery.sizeOf`) |
| `isWideLayout(context)` | `screenSizeOf(context) != ScreenSize.phone` |
| `pagePadding(context)` | `EdgeInsets.all` of 16 (phone), 20 (tablet), 24 (desktop) |
| `PageContainer` | `Align(topCenter)` → `ConstrainedBox(maxWidth: 1400)` → `Padding(pagePadding)` |
| `SectionCard` | `Card` with 16 px padding; header row with optional 22 px primary icon, bold title, optional `white70` subtitle, optional `trailing`; 12 px gap before `child` |
| `StatusChip` | Compact `Chip`; `StatusTone` sets colours: success (green 15% / `greenAccent`), warning (amber / `amberAccent`), error (red / `redAccent`), info (blue / `lightBlueAccent`), neutral (`white12` / `white70`) |
| `PlatformCapabilityBanner` | Chips for `platformCapabilityLabel`, Optical, Acoustic, Vibration (phones), `'No internet'`, plus `platformCapabilitySummary` |
| `EmptyState` | Centred icon + message + optional subtitle; switches to a compact form (24 px icon, 8 px padding, 2 lines, no subtitle) when `maxHeight < 130` |
| `PairingInstructionsCard` | `SectionCard('Broadcast & Pairing', 'One sender can reach many receivers')` listing `hardwarePairingSteps` |

Where layouts change with size:

| Screen | Phone | Tablet / desktop |
|---|---|---|
| `SimulationScreen` | Stacked panels, flex 2/2/3; `'Run All'` | Three columns; `'Run All Scenarios'`; dropdown width 320 |
| `PerformanceScreen` | `ListView` | `GridView`, 2 columns (tablet) or 3 (desktop) |
| `HardwareScreen` | Sections stacked; log height 180 | Optical beside acoustic/vibration; log height 220 |
| `TransferScreen` | Stacked segmented buttons; camera 160; panels stacked | `Wrap` of segmented buttons; camera 200; panels side by side |

The main flow screens (Home, Compose, Transmit, Receive) use `PageContainer` but otherwise lay out the same at every size.

---

## 10. The full-screen QR overlay

The transmit QR must be full-screen, white and above everything, regardless of which route is showing. It is implemented outside the `Navigator`:

1. `MaterialApp.builder` wraps the navigator in `Stack(fit: StackFit.expand, children: [child, const OpticalActiveOverlay()])`. Because it is inside `MaterialApp`, the overlay inherits `MediaQuery`, `Theme` and `Directionality`, but it is not a route.
2. `OpticalActiveOverlay` listens to `opticalTransmitterState`. When `transmitting` is false it renders `SizedBox.shrink()`, so it takes no space and receives no taps.
3. When the fountain modem starts (`FountainQrModem.transmit`), it calls `opticalTransmitterState.setTransmitting(true)`, then `setFountainSession(sessionId:, k:, blockLen:, fileLen:, profileLabel:)`, then for each frame `setFountainQrBitmap(bitmap:, index: symbolIndex + 1, total: K)`. Until the first bitmap arrives the overlay is a plain white box. The first frame is held for `frameMs + 250` ms to give the receiver time to focus. The overlay rebuilds for each frame; `QrBitmapView` repaints only when the bitmap instance changes.
4. The overlay's **Stop** button calls the global `onOpticalTransmitCancel`, which the `AppController` constructor wires to `requestCancelTransfer()`. That sets `_cancelRequested = true` and calls `opticalTransmitterState.setTransmitting(false)` (which also clears the bitmap and session) and `vibrationTransmitterState.setTransmitting(false)`.
5. The modem loop (`while (_txActive && opticalTransmitterState.transmitting && elapsed < maxStreamDuration)`) exits, restores brightness and remembers the next symbol index for resume; `_sendDirectEnvelope` sets the status line (`'Streaming stopped (…)'` or the 10-minute safety-cap text) and restores the channels; `SendTransmitScreen` moves to `_TxPhase.stopped`.

Consequences to keep in mind:

- Everything in the navigator (app bar, dialogs, bottom sheets, snackbars) is **underneath** the overlay while it is visible. Anything the user must reach during streaming has to live in the overlay itself.
- The system back gesture still reaches the `Navigator`, so the `PopScope` in `SendTransmitScreen` still works while the overlay is up.
- The overlay also appears for any other optical transmission, for example **Test QR** on the Hardware screen.

---

## 11. Accessibility and back navigation

### 11.1 Back navigation

| Screen | Behaviour |
|---|---|
| `SendTransmitScreen` | `PopScope(canPop: _phase != _TxPhase.transmitting)`. A back gesture while transmitting is refused and `onPopInvokedWithResult` calls `_cancel()`, which runs `app.requestCancelTransfer()` and then `Navigator.pop(context)`. The app-bar **✕** (tooltip `'Cancel'`) and **Cancel transmission** call the same `_cancel()`. In every other phase, back pops normally. |
| `ReceiveScreen` | Normal pop. `dispose` calls `stopListening()`, which stops all hardware channels. Dismissing the initial mode picker pops the screen. |
| `HardwareScreen` | Normal pop; `dispose` calls `stopHardwareChannels()`. |
| Others | Normal pop; no cleanup. |

### 11.2 Accessibility

- Every icon-only `IconButton` has a tooltip, which Flutter also exposes as the semantic label: `'Developer tools'`, `'Cancel'`, `'Change mode'`, `'Remove attachment'`, `'Clear logs'`, `'Connection & logs'`, `'Attach'`.
- Received text and links are `SelectableText`, so users can select, copy and use system text actions.
- State is always shown as text as well as colour (SCAN/LOCK/DONE, banner titles, `Microphone streaming` / `Microphone not active`), so the UI does not rely on colour alone.
- HUD numbers use tabular figures to stay readable while updating.
- No widget uses `Semantics` or `semanticLabel` explicitly, and there is no custom text-scaling logic. Gaps worth knowing: the zoom chips are plain `GestureDetector`s (not announced as buttons), tap-to-focus has no semantic action, the video play/pause `IconButton.filled` has no tooltip, and `_ModeTile` / `_ActionButton` rely on their text children for semantics.
- The home screen's policy text is clipped at `maxLines: 3` with an ellipsis, so large text sizes truncate it.

---

## 12. Known UI quirks

These are behaviours found by reading the code. They are documented here so that nobody is surprised; fixing them is a separate task.

| Where | Behaviour |
|---|---|
| `SendTransmitScreen._cancel` → `AppController.requestCancelTransfer` | Cancelling a **Sound** send (the **✕**, **Cancel transmission** or back) does not stop the acoustic modem. `requestCancelTransfer` never calls `cancelAcousticTransmit()`, and the modem's `shouldContinue` checks only the channel's own `_running`. The tones continue after the screen closes until the symbol budget `max(6K, K + 24)` is used up. Only the card's **Stop** (`app.cancelAcousticTransmit`) stops it at once. |
| `SendTransmitScreen._startTransmit` | For Sound, pressing **Stop** ends the stream normally, so the screen shows **Sent successfully** (and the chat entry is marked `delivered`), even though the sender cannot know whether anyone received it. Only Light gets the **Streaming stopped** / **Resume streaming** result. |
| `ReceiveScreen._resolveVisibleMessage` | `_pickMode()` resets `_lastPresentedId` to `null`, so on opening Receive (or after **Change mode**) the most recent incoming message still in `app.chatMessages` from an earlier session is shown immediately. |
| `_LightListenView` | `OpticalTransferCompleteCard` is only rendered in the listening view, which is replaced by the received-content pane as soon as the message is delivered (within one 80 ms poll). In practice it is only visible briefly, or when a completed file fails envelope validation. |
| `SimulationScreen` | **Run All Scenarios** writes its result (`'N/9 scenarios passed'`) only to `app.statusMessage`, which this screen does not display, and does not update `lastSimResult` or the logs. |
| `HardwareScreen` | Does not set `app.mode`. On a fresh launch the mode is `OperationMode.simulation`, so **Send Message** / **Send HELLO** (which call `sendChat`) run a simulation instead of a hardware transfer until the mode is switched to Live (for example in Legacy Messages) or a Send/Receive flow has run. |
| `SendComposeScreen` | No generic file picker; text plus a photo/video sends only the text; strings like `see.you` are sent as links. |
| `ReceivedContentView` | Temporary `rx_img_*` / `rx_video_*` files are written for each display and never deleted. On web, `dart:io` file writes fail, so images fall back to `Image.memory` and videos show the error placeholder. |
| `TransferScreen.dispose` | Calls `AppProvider.of(context)` in `dispose`, guarded by `try/catch`. |
| `optical_qr_overlay.dart`, `optical_flash_overlay.dart`, `channelIdToPhysicalMode` | Unused. |

---

## 13. How to add a new screen

1. **Create the file** in `lib/ui/screens/`, for example `my_screen.dart`, with a `StatelessWidget` (or a `StatefulWidget` if it owns controllers or timers).
2. **Get the controller** with `final app = AppProvider.of(context);` inside `build`, and wrap the body in `ListenableBuilder(listenable: app, builder: (context, _) { … })` to follow the existing convention.
3. **For high-rate data**, listen to the specific notifier (`opticalTransmitterState`, `acousticReceiverState`, `app.opticalMetricsNotifier ?? app`, and so on) in a small `ListenableBuilder` around just the widgets that show it.
4. **Lay out** with `Scaffold` → `PageContainer` → your content. Use `SectionCard`, `StatusChip`, `EmptyState` and `PlatformCapabilityBanner` from `app_layout.dart`, and branch on `isWideLayout(context)` or `screenSizeOf(context)` for tablet/desktop layouts.
5. **Add controller methods** to `AppController` for any new behaviour. Set `_running` around long work, call `notifyListeners()` after each state change, and disable buttons with `onPressed: app.running ? null : …`.
6. **Make it reachable** with `Navigator.push(context, MaterialPageRoute(builder: (_) => const MyScreen()))`. For a developer tool, add a `_DevTile` in `DevMenuScreen`; for a primary feature, add an `_ActionButton` to `HomeScreen`.
7. **Clean up hardware** if the screen starts a channel: cache the controller in `initState` (post-frame) or `didChangeDependencies`, and stop the channel in `dispose` (as `ReceiveScreen` and `HardwareScreen` do). Do not call `AppProvider.of` in `dispose`.
8. **Guard transmissions** with the `PopScope` pattern from `SendTransmitScreen` if leaving mid-transfer would leave hardware running, and make sure the cancel path actually stops the channel (see the Sound quirk above).
9. **Keep everything reachable during Light streaming** in mind: nothing in your screen is visible while the overlay is up.
10. **Test**: add a widget test under `test/` (see `widget_test.dart` for the home-screen smoke test) and run `flutter analyze`.

---

## 14. How to add a new channel option to the UI

### 14.1 A new value for an existing option (for example a new Light density or Sound speed)

1. Add the constant to the core profile class: `OpticalTxProfile` in `lib/core/physical/optical_tx_profile.dart`, or `AcousticTxProfile` in `lib/core/physical/acoustic/acoustic_tx_profile.dart`.
2. Add it to the class's `values` list. The order matters: `SegmentedButton<OpticalTxProfile>` shows `OpticalTxProfile.values` in order; `AcousticProfilePicker` shows `AcousticTxProfile.values.reversed`, and `AcousticTxProfile.slower` walks `values` from slowest to fastest.
3. For Sound, add a case to `conditionHint` (the default case returns `'Normal room, across a table'`).
4. Check that `label` is short enough: the Light segments use 12 px text inside a four-way `SegmentedButton`.
5. No UI code changes are needed; the pickers, the estimate lines (`estimatedSeconds`, `acousticEtaSeconds`) and the HUD labels read from the profile. For Light, also check `expectedCaptureYield` for the new `blockLen`.

### 14.2 A new setting on the transmit screen (for example a toggle)

1. Add private state, a getter and a setter to `AppController`. The setter must push the value into the channel (as `setOpticalTxProfile` calls `_opticalChannel?.setTxProfile`) and call `notifyListeners()`. Also apply it in `_ensureChannelInitialized`, because channels are created lazily.
2. In `_ReadyBody` (`send_transmit_screen.dart`), render the control inside the matching `if (mode == PhysicalChannelMode.…)` card, reading `app.<getter>` and calling `app.<setter>`. `_ReadyBody` is inside the screen's `ListenableBuilder`, so it updates automatically.
3. If the setting changes timing, update the estimate line in the same card.
4. If it should reset each time the screen opens, set it in `initState`'s post-frame callback next to `setOpticalTxProfile(OpticalTxProfile.auto)`.

### 14.3 A new physical channel mode

Most sites use exhaustive `switch` expressions, so adding an enum value makes `flutter analyze` point at every place that needs a case. The full list:

1. **Core:** add a `CommChannelId` value and its channel implementation; see [Architecture](../architecture/ARCHITECTURE.md) and [API reference](API_REFERENCE.md).
2. **`PhysicalChannelMode`** (`physical_channel_mode.dart`): add the enum value and cases for `label`, `subtitle`, `icon`, `channelId`, `supportsBroadcast`, `isAvailable`, and `channelIdToPhysicalMode`.
3. **`_ModeTile`** (`mode_picker_sheet.dart`): add an accent colour.
4. **`SendTransmitScreen`**: `_actionIcon`, `_actionLabel`, `_readyTitle`, `_TransmittingBody` (add a `_…TxView`), and any tips/options card in `_ReadyBody`. Decide how the Light-only `stopped` phase logic in `_startTransmit` applies.
5. **`ReceiveScreen`**: `_ListeningBody` (add a `_…ListenView`) and, if it needs its own wording, a branch in `_ListeningBanner`.
6. **`AppController`**: routing in `sendPhysicalMessage` / `_sendDirectEnvelope`, `startOne` and the stop loop in `startHardwareChannels`, `_ensureChannelInitialized`, `_initHardwareForRole`, `stopHardwareChannels`, `_pollHardwareReceiver`, `_pollDirectEnvelopes`, `_resetPhysicalReceiveCaches`, and `requestCancelTransfer` (make sure cancel really stops the new transmitter).
7. **UI state:** if the channel needs live feedback, add a notifier in `lib/core/platform/` following `AcousticReceiverState` and listen to it with a small `ListenableBuilder`.
8. **Docs and tests:** update the [User Guide](../getting-started/USER_GUIDE.md) and this guide, and extend `test/physical_only_test.dart`, which currently checks that exactly three physical channels exist.
