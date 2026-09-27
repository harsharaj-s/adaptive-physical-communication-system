# References

The papers, standards, libraries and tools the project builds on. Algorithms were re-implemented in Dart from these sources; no third-party codec source was copied (see the licence note at the end).

Back to the [documentation index](../README.md).

---

## Contents

1. [Fountain and erasure codes](#1-fountain-and-erasure-codes)
2. [Reed-Solomon and finite fields](#2-reed-solomon-and-finite-fields)
3. [Signal processing and acoustic modems](#3-signal-processing-and-acoustic-modems)
4. [QR codes and screen–camera links](#4-qr-codes-and-screencamera-links)
5. [Checksums and hashing](#5-checksums-and-hashing)
6. [Adaptive and reliable transport](#6-adaptive-and-reliable-transport)
7. [Platform and library documentation](#7-platform-and-library-documentation)
8. [Dependencies used by the app](#8-dependencies-used-by-the-app)
9. [Tools used to build assets](#9-tools-used-to-build-assets)
10. [Licence note](#10-licence-note)

---

## 1. Fountain and erasure codes

| Reference | Used for |
|---|---|
| M. Luby, "LT Codes," *Proc. 43rd IEEE FOCS*, 2002 | The LT fountain idea, degree distributions, the robust soliton the project moved away from |
| J. W. Byers, M. Luby, M. Mitzenmacher, A. Rege, "A Digital Fountain Approach to Reliable Distribution of Bulk Data," *ACM SIGCOMM*, 1998 | The rateless broadcast model |
| A. Shokrollahi, "Raptor Codes," *IEEE Trans. Information Theory* 52(6), 2006 | Background; a [roadmap](ROADMAP.md) research idea |
| RFC 6330, *RaptorQ Forward Error Correction Scheme for Object Delivery*, IETF, 2011 | Comparison point for overhead |
| D. J. C. MacKay, *Information Theory, Inference, and Learning Algorithms*, ch. 50 "Digital Fountain Codes", Cambridge University Press, 2003 | The dense random-matrix bound P(fail) ≤ 2^−m |

## 2. Reed-Solomon and finite fields

| Reference | Used for |
|---|---|
| I. S. Reed, G. Solomon, "Polynomial Codes over Certain Finite Fields," *J. SIAM* 8(2), 1960 | The code itself |
| E. R. Berlekamp, *Algebraic Coding Theory*, McGraw-Hill, 1968; J. L. Massey, "Shift-Register Synthesis and BCH Decoding," *IEEE Trans. IT*, 1969 | Berlekamp–Massey |
| G. D. Forney, "On Decoding BCH Codes," *IEEE Trans. IT*, 1965 | Forney's error-value formula |
| G. D. Forney, "Generalized Minimum Distance Decoding," *IEEE Trans. IT* 12(2), 1966 | GMD retries with erasures |
| S. Lin, D. J. Costello, *Error Control Coding*, 2nd ed., Pearson, 2004 | Errors-and-erasures decoding, GF(2^8) arithmetic |
| "Reed–Solomon codes for coders," Wikiversity | Practical implementation reference (polynomial 0x11D, syndromes from α^0) |

## 3. Signal processing and acoustic modems

| Reference | Used for |
|---|---|
| G. Goertzel, "An Algorithm for the Evaluation of Finite Trigonometric Series," *American Mathematical Monthly* 65(1), 1958 | Single-bin tone detection |
| A. V. Oppenheim, R. W. Schafer, *Discrete-Time Signal Processing*, 3rd ed., Pearson, 2009 | DFT orthogonality, windowing, processing gain |
| J. G. Proakis, M. Salehi, *Digital Communications*, 5th ed., McGraw-Hill, 2008 | M-ary FSK, non-coherent detection, symbol synchronisation |
| ggwave (G. Gerganov), open-source data-over-sound library | Inspiration for multi-tone FSK over phone speakers and microphones |
| Chirp / quiet-js projects | Prior art for audible and near-ultrasonic data over sound |

## 4. QR codes and screen–camera links

| Reference | Used for |
|---|---|
| ISO/IEC 18004:2015, *QR Code bar code symbology specification* | Versions, capacities, EC levels, masks, the 4-module quiet zone |
| T. Hao, R. Zhou, G. Xing, "COBRA: Color Barcode Streaming for Smartphone Systems," *ACM MobiSys*, 2012 | Screen–camera streaming; frame-rate vs capture-rate issues |
| S. D. Perli, N. Ahmed, D. Katabi, "PixNet: Interference-Free Wireless Links Using LCD-Camera Pairs," *ACM MobiCom*, 2010 | Early screen–camera data links; blur and perspective as the limiting factors |
| W. Hu, H. Gu, Q. Pu, "LightSync: Unsynchronized Visual Communication over Screen-Camera Links," *ACM MobiCom*, 2013 | Why each code is held for ≥ 2 camera exposures |
| "TXQR" (divan) and "qrfile"-style fountain QR demos | Prior art for fountain-coded animated QR transfers |
| ZXing project documentation | Binarizer behaviour, `PURE_BARCODE` hint |

## 5. Checksums and hashing

| Reference | Used for |
|---|---|
| ITU-T V.42 / IEEE 802.3 CRC-32 (reflected polynomial 0xEDB88320) | Light frames, packets, de-duplication; check value CBF43926 |
| CRC-16/CCITT-FALSE (polynomial 0x1021, init 0xFFFF) | Sound frames; check value 29B1 |
| R. N. Williams, "A Painless Guide to CRC Error Detection Algorithms," 1993 | Parameterised CRC definitions |
| A. Appleby, MurmurHash3 `fmix32` finaliser | The counter-mode PRNG that picks LT neighbours |
| Golden-ratio constant 0x9E3779B1 (Knuth multiplicative hashing) | Mixing the block size into the Light session ID |

## 6. Adaptive and reliable transport

| Reference | Used for |
|---|---|
| RFC 9293, *Transmission Control Protocol*, IETF, 2022 | Sliding windows, cumulative vs selective ACKs (see [Known Issues 3.1](KNOWN_ISSUES.md#31-acks-are-treated-as-cumulative-high-for-the-protocol-path)) |
| RFC 2018, *TCP Selective Acknowledgment Options*, IETF, 1996 | The per-sequence ACK fix proposed in the [Roadmap](ROADMAP.md) |
| Multi-criteria decision making (weighted-sum model) | The channel scoring formula |

## 7. Platform and library documentation

- Flutter documentation: platform channels, isolates, `TransferableTypedData`, assets, web initialization (`flutter-first-frame`).
- Android developers: adaptive icons (108 dp canvas, 66 dp safe zone), themed/monochrome icons (API 33), the SplashScreen API (API 31), runtime permissions, `WindowManager.LayoutParams.screenBrightness`.
- Apple Human Interface Guidelines: app icon sizes, launch screens, privacy usage descriptions.
- W3C Web App Manifest: icons and the `maskable` purpose (80% safe zone).

## 8. Dependencies used by the app

From `pubspec.yaml`:

| Package | Role |
|---|---|
| `camera` | Camera preview and YUV/BGRA frame stream (Light receive) |
| `zxing2` | QR decoding |
| `qr` | QR encoding (byte mode, EC level, mask) |
| `record` | Microphone PCM stream (Sound receive) |
| `audioplayers` | WAV playback (Sound send) |
| `vibration`, `sensors_plus` | Motor control and accelerometer (Vibration) |
| `permission_handler` | Camera and microphone runtime permissions |
| `wakelock_plus` | Keep the sender's screen on while streaming |
| `image` | Photo decode/resize/JPEG encode |
| `file_picker` | Picking photos, videos and files |
| `video_player` | Playing received videos |
| `gal` | Saving to the photo Gallery |
| `path_provider` | Temporary files for playback and saving |
| `url_launcher` | Opening received links |
| `collection`, `web`, `cupertino_icons` | Utilities, web interop, icons |
| `flutter_lints` (dev) | Lint rules |

## 9. Tools used to build assets

| Tool | Used by |
|---|---|
| Python 3 + Pillow | `tool/make_app_icon.py`, `tool/make_sample_media.py`, `tool/make_explainer_videos.py` |
| `imageio-ffmpeg` (bundled ffmpeg: x264, libvpx-vp9, AAC, Opus) | Size-targeted two-pass video encodes |
| Windows System.Speech (Microsoft Zira voice) | Offline narration for the explainer videos |

## 10. Licence note

The fountain QR design was inspired by public descriptions of fountain-coded QR streaming. It was **re-implemented from the papers above**, and no code from AGPL or other copyleft projects was copied. The photos used for the bundled samples were supplied by the project author. The explainer videos and the app logo are generated entirely by the scripts in `tool/`.
