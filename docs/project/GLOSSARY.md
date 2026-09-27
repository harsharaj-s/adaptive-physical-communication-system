# Glossary

The terms and abbreviations used across the documentation and the code, in alphabetical order. Where a term maps to a class or constant, the code name is given in backticks.

Back to the [documentation index](../README.md).

---

| Term | Meaning |
|---|---|
| **ACK / NACK** | Acknowledgement / negative acknowledgement packets in the protocol path. A NACK asks for one missing sequence number to be resent |
| **Adaptive engine** | `AdaptiveDecisionEngine`: scores channels and decides whether to switch. See [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md) |
| **APCF** | *Adaptive Physical Communication Fountain* frame: the binary payload of each Light QR code (magic `APCF`, version 3, 22-byte header, CRC-32) |
| **APCM** | *Adaptive Physical Communication Message* envelope: `APCM` + type + name + MIME + data. Carried by every channel |
| **APCS** | The project name, *Adaptive Physical Communication System* |
| **APCS1** | The first-generation text QR format (base64 carousel), now legacy |
| **α (alpha)** | The primitive element 0x02 of GF(256). All non-zero field elements are powers of α |
| **Auto density** | The Light profile that picks 160/240/330-byte blocks so a transfer needs at most about 48 symbols |
| **Berlekamp–Massey** | The algorithm that finds the Reed-Solomon error-locator polynomial from the syndromes |
| **Bin** | One frequency slot of an N-point analysis: bin *b* is at *b* × 44 100 / 1 024 ≈ *b* × 43.07 Hz |
| **Binarizer** | The zxing2 stage that turns a grey image into black and white modules (`GlobalHistogramBinarizer`, `HybridBinarizer`) |
| **Block / blockLen** | One fixed-size piece of the file in a fountain transfer (Light 160–600 B, Sound 32–64 B) |
| **Broadcast** | One sender, any number of receivers, no replies. Light and Sound always work this way |
| **Burst** | 2–4 Sound frames played back-to-back from one generated WAV |
| **CAP / DEC / DROP / GOOD** | Light HUD figures: camera captures/s, successful QR decodes/s, frames skipped while the decoder was busy, and goodput in KB/s |
| **Carousel** | Repeating the same N frames in a loop (the old approach); needs every *specific* frame, unlike a fountain |
| **Chien search** | Finding the roots of the error-locator polynomial by trying every field element |
| **Codeword** | A Reed-Solomon block: data bytes + parity bytes (e.g. 99 bytes for Standard) |
| **CRC-16 / CRC-32** | Cyclic redundancy checks: CRC-16/CCITT-FALSE on Sound frames, CRC-32 (IEEE) on Light frames and packets |
| **CSK** | Colour-shift keying: data sent as coloured screen flashes. Legacy |
| **Degraded** | A channel whose score is below 0.65 |
| **Degree** | The number of source blocks XOR-ed into one repair symbol |
| **Density** | How many bytes one QR carries; more bytes means a larger QR version with smaller modules |
| **Envelope** | See APCM |
| **Erasure** | A Reed-Solomon symbol known to be unreliable; it costs half as much parity to repair as an unknown error |
| **ETA** | Estimated transfer time: `ceil((K + 2) / (fps × yield))` for Light |
| **EV** | Exposure value; −0.7 EV means about 40% less light, used to keep QR edges sharp |
| **Finder pattern** | The three large squares in QR corners (1:1:3:1:1 ratio) used to locate the code. Also the centre of the app logo |
| **Forney algorithm** | Computes error magnitudes once the error positions are known |
| **Fountain code** | A rateless code: the sender can produce unlimited distinct symbols, and any ≈K of them rebuild the file |
| **fps** | Frames per second (Light display rate: 12, Safe 8) |
| **FSK / MT-FSK** | Frequency-shift keying / multi-tone FSK: data carried by which tone(s) are playing |
| **Gauss-Jordan elimination** | Row reduction used by the LT decoder over GF(2) (XOR arithmetic) |
| **GF(2), GF(256)** | Galois (finite) fields with 2 and 256 elements. GF(2) is used for fountain coding, GF(256) for Reed-Solomon (polynomial 0x11D) |
| **GMD** | Generalised minimum-distance decoding: retry Reed-Solomon while erasing the 4, 8, 12… least-confident bytes |
| **Goertzel algorithm** | Measures the power at one frequency bin cheaply; used for every tone decision |
| **Goodput** | Useful payload bytes per second, excluding overhead and duplicates |
| **Group** | 16 adjacent tone bins carrying one nibble (4 bits) in MT-FSK |
| **Hysteresis** | The 0.15 score margin an alternative channel must beat before a switch |
| **Isolate** | A Dart thread with its own memory; QR decoding runs in one so the UI stays smooth |
| **K** | The number of source blocks in a fountain transfer |
| **Leading edge** | The first sample where the sync-marker score reaches 50% of its peak; defines Sound frame timing |
| **LT code** | Luby Transform code, the fountain code family used here (systematic, with custom degree rules) |
| **Marker** | The two-tone (bins 28 and 36) sync burst at the start of every Sound frame |
| **Maskable icon** | A web icon with a full-bleed background, so the platform can crop it to any shape |
| **Module** | One black or white square of a QR code |
| **NEW / DUP / RED** | Light HUD counters: symbols that added rank, repeated indices, linearly dependent symbols |
| **Nibble** | 4 bits; one MT-FSK group carries one nibble per symbol |
| **Overhead** | Extra symbols beyond K needed to decode (mean 0–2.2 here) |
| **Parity (P)** | Reed-Solomon check bytes per frame (20 or 24) |
| **Processing gain** | The SNR improvement from integrating a tone over many samples: 10·log10(L/2) dB |
| **Profile** | A named parameter set: Light Auto/Safe/Standard/Fast; Sound Rugged/Safe/Standard/Fast |
| **pureBarcode** | A zxing2 hint that reads the grid from the black bounding box, rescuing frames with fake finder patterns |
| **Quiet zone** | The white margin (4 modules) around a QR code |
| **Rank** | The number of independent symbols the LT decoder holds; decoding completes at rank = K |
| **Reed-Solomon (RS)** | The error-correcting code on each Sound frame |
| **Resume streaming** | Restarting a Light send with the same session ID and new symbol indices; the receiver keeps its progress |
| **Session ID** | Identifies one transfer. Light: derived from the content CRC and block size (32-bit). Sound: time-based (8-bit) |
| **SNR** | Signal-to-noise ratio in dB |
| **Symbol** | One fountain unit: a source block (systematic) or an XOR of several (repair). For MT-FSK, one tone-chord time slot |
| **Syndrome** | The Reed-Solomon codeword evaluated at α^0…α^(P−1); all zero means no detected errors |
| **Systematic** | The first K fountain symbols are the source blocks themselves |
| **Unicast** | One sender, one receiver, with ACKs (protocol path only) |
| **Yield** | The fraction of displayed Light frames the camera typically decodes (0.70 / 0.65 / 0.55 / 0.35 by density) |
| **zxing2** | The pure-Dart port of the ZXing barcode library, used to decode QR codes |
