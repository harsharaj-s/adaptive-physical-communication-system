# Data Formats

Every byte layout the app puts on the air, with real hex dumps. The dumps were produced on 27 September 2026 by running the project's own codecs (`ChatPayloadCodec`, `QrFountainFrameCodec`, `AcousticFrameCodec`, `ReedSolomon`, `PacketCodec`), so they match the implementation exactly.

Back to the [documentation index](../README.md).

---

## Contents

1. [Layering overview](#1-layering-overview)
2. [APCM chat envelope](#2-apcm-chat-envelope)
3. [APCF v3 light frame](#3-apcf-v3-light-frame)
4. [Acoustic fountain frame](#4-acoustic-fountain-frame)
5. [Protocol packet](#5-protocol-packet)
6. [Checksums](#6-checksums)
7. [Session identifiers](#7-session-identifiers)
8. [Legacy formats](#8-legacy-formats)
9. [Size and overhead summary](#9-size-and-overhead-summary)

---

## 1. Layering overview

```
                 ┌──────────────────── APCM envelope ────────────────────┐
                 │ "APCM" │ type │ name │ MIME │        content bytes     │
                 └──────────────────────────────────────────────────────┘
                                   │ split into K blocks of blockLen
          ┌────────────────────────┼─────────────────────────────┐
          ▼ Light                  ▼ Sound                       ▼ Vibration / big Sound
 ┌─────────────────────┐  ┌─────────────────────────┐  ┌──────────────────────────┐
 │ APCF v3 frame       │  │ Acoustic frame          │  │ Protocol packet          │
 │ 22 B hdr │ symbol │ │  │ 9 B hdr │ symbol │CRC16 │  │ 24 B hdr │ chunk │ CRC32 │
 │ CRC-32              │  │ + Reed-Solomon parity   │  │ (ACK / NACK / retry)     │
 └─────────┬───────────┘  └────────────┬────────────┘  └────────────┬─────────────┘
           ▼                           ▼                            ▼
   QR code, byte mode,        MT-FSK tones after a          PWK pulses (vibration)
   EC level L, mask 0         2-frame sync marker           or legacy FSK tones
```

**Byte order:** the APCM envelope has no multi-byte integers. APCF and acoustic frames are **big-endian**. Protocol packets are **little-endian**.

---

## 2. APCM chat envelope

Source: `lib/core/chat/chat_payload_codec.dart`.

### Layout

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | Magic | `41 50 43 4D` = ASCII `APCM` |
| 4 | 1 | Type | Index of `ChatMessageType`: text 0, image 1, video 2, file 3, link 4 |
| 5 | 1 | `nameLen` | 0–255 |
| 6 | `nameLen` | File name | UTF-8 |
| 6 + nameLen | 1 | `mimeLen` | 0–255 |
| 7 + nameLen | `mimeLen` | MIME type | UTF-8 |
| 7 + nameLen + mimeLen | rest | Content | Raw bytes to the end of the envelope (there is no length field) |

**Overhead** = `7 + nameLen + mimeLen`.

### Example 1: text "sos" (31 bytes)

`ChatPayloadCodec.encodeText('sos')` always uses the name `message.txt` and MIME `text/plain`:

```
41 50 43 4D  00  0B  6D 65 73 73 61 67 65 2E 74 78 74  0A  74 65 78 74 2F 70 6C 61 69 6E  73 6F 73
└─ "APCM" ─┘ type len └──────── "message.txt" ───────┘ len └───────── "text/plain" ────┘  └"sos"┘
             =text =11                                  =10
```

4 + 1 + 1 + 11 + 1 + 10 + 3 = **31 bytes**, of which 28 are overhead.

### Example 2: link "https://example.com" (47 bytes)

```
41 50 43 4D  04  08  6C 69 6E 6B 2E 75 72 6C  0D  74 65 78 74 2F 75 72 69 2D 6C 69 73 74
             link =8 └──── "link.url" ─────┘  =13 └────────── "text/uri-list" ──────────┘
68 74 74 70 73 3A 2F 2F 65 78 61 6D 70 6C 65 2E 63 6F 6D
└──────────────────── "https://example.com" ──────────┘
```

### Example 3: photo

A compressed photo is sent with the picked file name (or `photo.jpg`) and MIME `image/jpeg`. A photo called `robot_lab_5kb.jpg` has 7 + 17 + 10 = **34 bytes** of overhead, and its content starts with `FF D8` (the JPEG start-of-image marker).

### Validation (`looksComplete`)

A receiver delivers an envelope only if all of these hold:

1. It starts with `APCM`.
2. The type byte is 0–4.
3. `nameLen` and `mimeLen` fit inside the buffer.
4. The content passes a per-type check:

| Type | Requirement |
|---|---|
| text, link | at least 1 byte |
| image | at least 24 bytes and a JPEG (`FF D8`), PNG (`89 50 4E 47`), GIF (`47 49 46`) or WebP (`52 49 … 57 45` at offsets 0, 1, 8, 9) signature |
| video | at least 512 bytes |
| file | at least 1 byte |

Buffers without the magic are treated as legacy plain UTF-8 text, or as a binary file named `received.bin` if they aren't valid UTF-8.

---

## 3. APCF v3 light frame

Source: `lib/core/physical/fountain/qr_fountain_frame.dart`. One APCF frame is the complete content of one QR code, in QR **byte mode**.

### Layout (big-endian)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | Magic | `41 50 43 46` = `APCF` |
| 4 | 1 | Version | `03`. v3 changed the LT neighbour mapping, so v2 frames are rejected |
| 5 | 1 | Flags | bit 0 = gzip (defined, never set by the sender) |
| 6 | 4 | `sessionId` | See [§7](#7-session-identifiers) |
| 10 | 4 | `symbolIndex` | 0…K−1 systematic, ≥ K repair |
| 14 | 2 | `K` | Number of source blocks |
| 16 | 2 | `blockLen` | Bytes per symbol |
| 18 | 4 | `fileLen` | Envelope length (trims padding on reassembly) |
| 22 | blockLen | Symbol payload | Output of `LtEncoder.symbolAt(symbolIndex)` |
| 22 + blockLen | 4 | CRC-32 | Over bytes 0 … 21 + blockLen |

Constants: `qrFountainHeaderSize = 22`, `qrFountainCrcSize = 4`, `qrFountainOverhead = 26`.

### Example: first frame of "sos" at Auto density (186 bytes)

The 31-byte "sos" envelope is below 7 680 B, so Auto picks `blockLen = 160` and K = ⌈31 / 160⌉ = 1.

```
Header (22 B):
41 50 43 46   03   00   E1 AF 1D FB   00 00 00 00   00 01   00 A0   00 00 00 1F
└── APCF ──┘  v3  flags └─sessionId─┘ └symbolIndex┘  K=1   blk=160  fileLen=31

Payload (160 B): the envelope, then zero padding
41 50 43 4D 00 0B 6D 65 73 73 61 67 65 2E 74 78 74 0A 74 65 78 74 2F 70 6C 61 69 6E 73 6F 73 00 00 00 …(129 × 00)

CRC-32 (4 B):
AA 15 16 79
```

Session ID `E1AF1DFB` = `CRC32(envelope) ^ (160 × 0x9E3779B1)` = `0303135B ^ …`, masked to 32 bits (see [§7](#7-session-identifiers)).

186 framed bytes fit QR **version 8** at error-correction level L (capacity 192 bytes).

### Robustness details

- **Trailing bytes are ignored.** QR byte mode pads to a codeword boundary, so the parser only requires `length ≥ 26 + blockLen`.
- **Rejected when:** the magic or version is wrong, `K < 1`, `blockLen < 1`, the frame is too short, or the CRC doesn't match.
- **Text fallback.** `FQR3:` + base64url(frame) exists for string-only decoders (the web preview sampler). The receiver also tries the raw code units and UTF-8 bytes of a text result.

### Payload efficiency

| blockLen | Framed bytes | QR version (EC-L) | Efficiency = blockLen / framed |
|---|---|---|---|
| 160 | 186 | 8 | 86.0% |
| 240 | 266 | 10 | 90.2% |
| 330 | 356 | 12 | 92.7% |
| 600 | 626 | 17 | 95.8% |

---

## 4. Acoustic fountain frame

Source: `lib/core/physical/acoustic/acoustic_fountain_frame.dart`.

### Layout (big-endian)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | `symbolIndex` | u16 |
| 2 | 2 | `K` | u16, must be ≥ 1 |
| 4 | 1 | `blockLen` | u8; also confirms which profile the frame belongs to |
| 5 | 3 | `fileLen` | u24 (up to 16 MiB) |
| 8 | 1 | `sessionId` | u8: `(millisecondsSinceEpoch ~/ 97) & 0xFF` |
| 9 | L | Symbol payload | L = profile block length (32 / 48 / 64) |
| 9 + L | 2 | CRC-16/CCITT-FALSE | Over bytes 0 … 8 + L |
| 11 + L | P | Reed-Solomon parity | P = 20 or 24 |

Constants: `acousticHeaderSize = 9`, `acousticCrcSize = 2`, `acousticFrameOverhead = 11`. Codeword length = `11 + L + P`.

### Example: "sos" on the Standard profile (99 bytes)

Standard uses L = 64 and P = 24. K = ⌈31 / 64⌉ = 1. The session ID below is `0x5C`:

```
Header (9 B):   00 00   00 01   40    00 00 1F   5C
                sym=0   K=1    L=64  fileLen=31  session

Payload (64 B): 41 50 43 4D 00 0B 6D 65 73 73 61 67 65 2E 74 78 74 0A 74 65 78 74 2F 70
                6C 61 69 6E 73 6F 73 00 … (33 × 00)

CRC-16 (2 B):   98 58

RS parity (24 B):
                F2 15 5B 0F 5D D6 55 86 8C CC 93 4C 82 B9 30 42 BC 6C 95 8B 62 D0 DC 5B
```

Error-correction behaviour of this exact codeword, measured with the real decoder:

| Damage | Result |
|---|---|
| 12 bytes corrupted (the maximum for P = 24 with no hints) | **Repaired** |
| 13 bytes corrupted, no reliability information | Rejected |
| The same 13 bytes, with the demodulator marking them as least reliable | **Repaired** by GMD erasure decoding |

### Profile geometry

| Profile | L | P | Codeword | Bytes per symbol (G/2) | Data symbols ⌈codeword / (G/2)⌉ |
|---|---|---|---|---|---|
| Rugged | 32 | 20 | 63 | 3 | 21 |
| Safe | 48 | 24 | 83 | 3 | 28 |
| Standard | 64 | 24 | 99 | 4 | 25 |
| Fast | 64 | 24 | 99 | 4 | 25 |

On air, each frame is a **2-frame sync marker** (2 048 samples) followed by the data symbols. See [Sound Channel](../channels/SOUND_CHANNEL.md).

### Nibble-to-tone mapping

Group `g` of symbol `s` carries nibble number `s·G + g`. Even nibbles are the **high** half of a byte and odd nibbles the **low** half. For Standard (G = 8), the first symbol carries bytes 0–3:

```
byte0 = 00 → g0 = 0 (bin 40), g1 = 0 (bin 56)
byte1 = 00 → g2 = 0 (bin 72), g3 = 0 (bin 88)
byte2 = 00 → g4 = 0 (bin 104), g5 = 0 (bin 120)
byte3 = 01 → g6 = 0 (bin 136), g7 = 1 (bin 153)
```

The tone bin is `40 + 16·g + value` and its frequency is `bin × 43.066 Hz`. For example, bin 153 is 6 589.1 Hz.

---

## 5. Protocol packet

Source: `lib/core/protocol/packet_codec.dart`.

### Layout (little-endian)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Protocol version (= 1) |
| 1 | 4 | `sessionId` |
| 5 | 4 | `transferId` |
| 9 | 1 | `packetType` |
| 10 | 1 | `channelId`: optical 1, acoustic 2, vibration 3 |
| 11 | 4 | `sequenceNumber` (data starts at 1) |
| 15 | 2 | `payloadLength` |
| 17 | 2 | `totalPackets` (0 = unknown; clamped to 65 535) |
| 19 | 5 | Reserved (zero) |
| 24 | N | Payload |
| 24 + N | 4 | CRC-32 over bytes 0 … 23 + N |

### Packet types

| Value | Type | Value | Type |
|---|---|---|---|
| 0 | discovery | 8 | retransmissionRequest |
| 1 | discoveryResponse | 9 | channelSwitchRequest |
| 2 | channelTest | 10 | channelSwitchAck |
| 3 | channelTestResponse | 11 | heartbeat |
| 4 | negotiation | 12 | transferStatus |
| 5 | data | 13 | transferComplete |
| 6 | ack | 14 | error |
| 7 | nack | | |

### Example: data packet carrying "sos" over vibration (31 bytes)

Header fields: session `0x11223344`, transfer `0xAABBCCDD`, type data, channel vibration, sequence 1, payload 3, total 1.

```
01  44 33 22 11  DD CC BB AA  05  03  01 00 00 00  03 00  01 00  00 00 00 00 00  73 6F 73  84 1B F4 4B
ver └─session──┘ └─transfer─┘ data vib └──seq=1──┘ len=3 tot=1  └─reserved──┘  "sos"    └─CRC-32─┘
```

Notice the little-endian order: `0x11223344` is sent as `44 33 22 11`.

### Hardware packet sizes (MTU)

| Channel | Payload bytes per packet | Source |
|---|---|---|
| Optical | 1 400 | `hardwareOpticalPacketSize` |
| Acoustic | 512 | `hardwareAcousticPacketSize` |
| Vibration | 48 | `hardwareVibrationPacketSize` |
| All (simulation) | 256 | simulation `TransmissionConfig` |

The discovery payload is the two bytes `DC 01` (`hardwareDiscoveryPayload`).

---

## 6. Checksums

| Checksum | Polynomial | Init | Reflect | Final XOR | Check value `"123456789"` | Used by |
|---|---|---|---|---|---|---|
| **CRC-32** (IEEE 802.3) | `0x04C11DB7` (reflected table `0xEDB88320`) | `0xFFFFFFFF` | yes | `0xFFFFFFFF` | **`CBF43926`** | APCF frames, packets, envelope de-duplication, Light session IDs |
| **CRC-16/CCITT-FALSE** | `0x1021` | `0xFFFF` | no | none | **`29B1`** | Acoustic frames |

Both check values were computed with the project's `computeCrc32` and `crc16` and match the published standard values. That confirms the implementations are standard.

**Why two different CRCs?** A Light frame is 186–626 bytes, and the 4-byte CRC-32 is negligible there. A Sound frame carries only 32–64 payload bytes at tens of bytes per second, so 2 bytes matter. Reed-Solomon already rejects most damaged frames, which leaves the CRC-16 to catch rare miscorrections.

---

## 7. Session identifiers

| Channel | Width | Derivation | Consequence |
|---|---|---|---|
| Light | 32 bit | `(CRC32(envelope) ^ (blockLen × 0x9E3779B1)) & 0xFFFFFFFF`, with 0 mapped to 1 | Deterministic: the same file at the same density always gets the same session, so **Resume** and re-sends continue the same fountain |
| Sound | 8 bit | `(millisecondsSinceEpoch ~/ 97) & 0xFF` | Enough to tell overlapping transmissions apart; a new session per send |
| Packets | 32 bit + 32 bit | `Random().nextInt(0xFFFFFFFF)` for session and transfer | Distinguishes transfers for reassembly and de-duplication |

`0x9E3779B1` is the 32-bit golden-ratio constant, the classic multiplicative-hash constant. Multiplying the block length by it spreads the densities across the ID space, so the same file at 160 B and at 330 B gets unrelated sessions.

---

## 8. Legacy formats

These formats are kept for reuse and tests (see [Legacy Modems](../channels/LEGACY_MODEMS.md)).

| Format | Layout |
|---|---|
| **APCS1 text QR** | `APCS1:<id>:<i>/<n>:<base64url chunk>`, chunks of ≤ 1 400 bytes, shown sequentially at 220 ms per frame |
| **CSK light** | Preamble `00 55 AA FF`, then a little-endian u16 length, then data; each byte is shown as a 2×2 mosaic of cells, red `00` / green `01` / blue `10` / white `11`, most significant dibit first |
| **Two-tone FSK** | Preamble bits `10101010`, then packet bytes MSB-first; 1 800 Hz = 0, 3 200 Hz = 1, 18 ms per bit |
| **Vibration PWK** | Preamble bits `0 1 0 1 0 1 1 0`, then packet bytes MSB-first; 80 ms pulse = 0, 180 ms pulse = 1 |

---

## 9. Size and overhead summary

| Message | Envelope | Light (Auto) | Sound (Standard) |
|---|---|---|---|
| "sos" | 31 B | 1 frame × 186 B | 1 block; ≈4 frames × 99 B expected |
| 100-character text | ≈128 B | 1 frame × 186 B | 2 blocks; ≈5 frames expected |
| 5 KB photo | ≈5.1 KB | 33 frames × 186 B | not recommended |
| 78 KB video | ≈80 KB | 243 frames × 356 B (+ ≈2 extra) | not supported (over 8 KiB) |

"Expected" frames for Sound follow the sender's progress target `⌈1.25·K⌉ + 2`. For Light, the receiver needs K plus a couple of repair symbols (see [Fountain Code](../algorithms/FOUNTAIN_CODE.md#7-measured-overhead)).
