# Vibration Channel

The Vibration channel sends bits by **buzzing** the sender's vibration motor and **feeling** the buzzes with the receiver's accelerometer, while the two phones are pressed together. It is the slowest channel by far. The aim is to show that data can cross even a purely mechanical coupling, with the same packet protocol and CRC protection as the other channels.

> **Status: experimental, not reliable yet.** This page describes the design. The bit codec passes its unit tests, but on real phones vibration transfers usually fail or never finish. The Simulation Lab doesn't prove it works either: its `vibration-coupled` scenario ends up sending over the simulated optical channel ([Simulation Lab quirk 1](../development/SIMULATION_LAB.md#10-known-quirks)). See [Known Issues §2.8](../project/KNOWN_ISSUES.md#28-vibration-transfers-are-unreliable-on-real-phones-high) for the likely causes. Use Light or Sound for real messages and demonstrations.

Back to the [documentation index](../README.md).

---

## Contents

1. [Overview](#1-overview)
2. [Source files](#2-source-files)
3. [Modulation: pulse-width keying](#3-modulation-pulse-width-keying)
4. [Transmitter](#4-transmitter)
5. [Receiver](#5-receiver)
6. [Framing and the packet protocol](#6-framing-and-the-packet-protocol)
7. [Timing and throughput](#7-timing-and-throughput)
8. [Channel metrics reported to the engine](#8-channel-metrics-reported-to-the-engine)
9. [Limitations and tips](#9-limitations-and-tips)

---

## 1. Overview

```
SENDER                                         RECEIVER
packet bytes (24 B header + payload + CRC-32)  packet bytes → PacketCodec.decode (CRC-32)
  │ preamble 0 1 0 1 0 1 1 0 + bits MSB-first    ▲ preamble search, header → length, full packet
  ▼                                               │
bit 0 → 80 ms buzz ; bit 1 → 180 ms buzz          │ pulse length ≥ 130 ms → 1, else 0
gap 60 ms (+50 ms motor settle)                   │ pulse = |‖a‖ − baseline| ≥ 1.4 m/s²
  ▼                                               │
vibration motor ═════ phones pressed together ════ accelerometer (x, y, z)
```

| Property | Value |
|---|---|
| Topology | One-to-one (physical contact) |
| Data path | Protocol path (`ReliableTransport` + `PacketCodec`) |
| Packet payload (MTU) | 48 bytes |
| Status | Experimental: unreliable on real phones |
| Speed | ≈4.2 bit/s ≈ 0.5 B/s (nominal) |
| Platforms | Android and iOS (not web) |

---

## 2. Source files

| Area | File |
|---|---|
| Channel (motor TX, accelerometer RX) | `lib/core/channels/vibration_channel.dart` (`HardwareVibrationChannel`) |
| Bit codec | `lib/core/physical/physical_codecs.dart` (`VibrationBitCodec`) |
| UI state | `lib/core/platform/vibration_transmitter_state.dart` |
| Packet format | `lib/core/protocol/packet_codec.dart` |
| MTU | `lib/core/physical/hardware_phy_config.dart` (`hardwareVibrationPacketSize = 48`) |

---

## 3. Modulation: pulse-width keying

Information is carried by the **duration** of each buzz, not its strength. Motor strength varies between phones and with how they're held, but duration can be timed reliably.

| Parameter (`VibrationBitCodec`) | Default |
|---|---|
| `shortPulseMs` (bit 0) | 80 ms |
| `longPulseMs` (bit 1) | 180 ms |
| `gapMs` | 60 ms |
| `preamble` | `0 1 0 1 0 1 1 0` |
| `detectionThreshold` (absolute) | 12.0 m/s² |
| `relativeThreshold` (against baseline) | 1.4 m/s² |
| Decision boundary | (80 + 180) / 2 = **130 ms** |

- `bytesToBits` produces the preamble followed by each byte **MSB-first**.
- `decodePulseDuration(d) = d ≥ 130 ? 1 : 0`.
- The 100 ms difference between the two pulse lengths leaves ±50 ms of timing tolerance for motor spin-up, spin-down and sensor sampling jitter.

---

## 4. Transmitter

`HardwareVibrationChannel.transmit(packet)`:

1. It requires `start()` to have run (otherwise it throws `StateError`), and skips on non-mobile platforms.
2. `bits = codec.bytesToBits(packet)`.
3. For each bit:
   - `vibrationTransmitterState.setVibrating(true)`, so the UI's icon pulses.
   - `_vibrateFor(duration)`:
     - If the motor supports amplitude control: `Vibration.vibrate(pattern: [0, d], intensities: [0, 255])` (full intensity).
     - Otherwise: `Vibration.vibrate(duration: d)`.
     - On an exception: `Vibration.vibrate(pattern: [0, d])`.
     - With no motor at all: `HapticFeedback.heavyImpact()`.
     - Then wait **d + 50 ms** (motor settle).
   - `setVibrating(false)`; wait `gapMs` = 60 ms.
4. Finally: `Vibration.cancel()` and clear the transmitting state.

**Real bit periods:** bit 0 = 80 + 50 + 60 = **190 ms**, bit 1 = 180 + 50 + 60 = **290 ms**.

---

## 5. Receiver

`HardwareVibrationChannel._processAccelerometer(event)` runs for every accelerometer sample:

```
mag       = sqrt(x² + y² + z²)                          (m/s², includes gravity ≈ 9.8)
signal%   = clamp(|mag − baseline| / 6, 0, 1)           → UI meter and confidence
active    = |mag − baseline| ≥ 1.4

if !active and no pulse in progress:
    baseline ← 0.92·baseline + 0.08·mag                  (tracks gravity and posture while quiet)

rising edge  (active, no pulse)  → pulseStart = now
falling edge (!active, pulse)    → duration = now − pulseStart
                                   if duration ≥ 25 ms: bit = duration ≥ 130 ? 1 : 0
                                   once ≥ 24 bits are buffered: try to decode packets
```

**Baseline filter.** The update `b ← 0.92 b + 0.08 m` is an exponential moving average with α = 0.08. Its time constant is about 1/α ≈ 12.5 samples, which follows slow changes (tilting the phone) but not a 80–180 ms buzz. The baseline is frozen while a pulse is active, so the buzz doesn't pull it upward. It starts at 9.8 m/s².

**Noise rejection.** Pulses shorter than 25 ms (knocks, taps) are ignored.

### Packet extraction (`_tryDecodePackets`)

1. Find the preamble in the bit buffer. If there is none and more than 64 bits are buffered, drop the oldest quarter.
2. Extract the 24-byte header right after the preamble and read `payloadLength` (little-endian, offset 15). If it exceeds 512, the header is garbage: skip one bit past this preamble and retry later.
3. Wait until `24 + payloadLength + 4` bytes of bits are present.
4. `packetCodec.decode(bytes)` checks the version and the CRC-32.
   - Success: queue the packet and consume the preamble plus the packet bits.
   - Failure: skip one bit past the preamble (it may have been a false match inside data).

The packets are then collected by `AppController`'s 80 ms poll and reassembled (see [Architecture §6](../architecture/ARCHITECTURE.md#6-receive-sequence-in-detail)).

---

## 6. Framing and the packet protocol

Vibration always uses the **protocol path**:

- The envelope is split into 48-byte payload chunks, each with a 24-byte header and a CRC-32, so **76 bytes per packet** on air.
- `ReliableTransport` with the hardware config: ACK timeout 20 000 ms, 8 retries, window 4.
- In unicast mode the receiver ACKs. The reply channel is the packet's own channel unless it was optical, so vibration packets are ACKed by vibration.

See [Data Formats §5](../architecture/DATA_FORMATS.md#5-protocol-packet) and [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md).

---

## 7. Timing and throughput

Average bit period, assuming equally likely 0s and 1s: (190 + 290) / 2 = **240 ms**, i.e. about **4.17 bit/s**, or about **0.52 B/s** raw.

| Message | Envelope | Packet on air | Bits (incl. 8 preamble) | Time |
|---|---|---|---|---|
| "hi" | 9 B | 9 + 28 = 37 B | 304 | ≈73 s |
| "ok" | 9 B | 37 B | 304 | ≈73 s |
| "hello" | 12 B | 40 B | 328 | ≈79 s |
| 48-byte payload (a full packet) | — | 76 B | 616 | ≈148 s |

These times are calculated, not measured; on real phones most transfers don't complete (see the status note at the top). The per-packet overhead (28 bytes, 224 bits, about 54 s) dominates short messages, so even a working vibration channel would only suit a word or two.

**Known timing conflict.** A full vibration packet takes longer on air (up to about 148 s) than the 20 s hardware ACK timeout, so in unicast mode the sender may retransmit before the first copy finishes. See [Known Issues](../project/KNOWN_ISSUES.md).

---

## 8. Channel metrics reported to the engine

| Method | Values |
|---|---|
| `capabilities` | name "Vibration (Hardware)", `maxThroughput 800`, `minLatency 300`, binary, hardware-implemented |
| `discover(timeoutMs)` | Waits `timeoutMs / 2`, then reports present if the last magnitude ≥ 0.8 × 12.0 |
| `test(n)` | Samples every 30 ms. Counts "received" when magnitude ≥ 0.7 × 12.0; throughput = 800 × ratio; latency = 80 × 8 = 640 ms; stability 0.65 |
| `getMetrics()` | Loss from sent/received counts (default 0.08); throughput 800·(1 − loss); latency (180 + 60) × 8 = 1 920 ms; reliability 1 − loss; stability 0.65 |

These values let the [Adaptive Engine](../algorithms/ADAPTIVE_ENGINE.md) rank vibration as the channel of last resort.

---

## 9. Limitations and tips

| Tip | Why |
|---|---|
| Press the phones **back to back**, firmly, on a soft surface (a hand or a cloth) | Maximises mechanical coupling and damps table resonance |
| Keep both phones still | Any movement shifts the baseline and can create false pulses |
| Send one short word | Each byte costs about 2 s; each packet about 54 s of overhead |
| Turn off keyboard haptics | Stray buzzes on the sender are harmless, but on the receiver they add noise |

Limitations: no forward error correction beyond the packet CRC; motor latency varies by model; iOS offers limited motor control (a haptic fallback is used); the web isn't supported.
