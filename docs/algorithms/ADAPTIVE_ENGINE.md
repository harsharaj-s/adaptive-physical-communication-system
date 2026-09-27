# Reliable Transport, State Machine and Adaptive Engine

The "adaptive" part of the system has three pieces:
- The **packet transport**, which makes a lossy channel reliable with a sliding window and ACK/NACK.
- The **transfer state machine**, which enforces a legal sequence of phases.
- The **decision engine**, which scores channels and switches between them with hysteresis.

These run the protocol path (Vibration, oversized Sound messages) and the Simulation Lab. The Light and Sound fountain paths don't need them, because they are rateless.

Back to the [documentation index](../README.md).

---

## Contents

1. [Where this applies](#1-where-this-applies)
2. [TransferManager: the end-to-end flow](#2-transfermanager-the-end-to-end-flow)
3. [Discovery](#3-discovery)
4. [Channel selection](#4-channel-selection)
5. [Reliable transport](#5-reliable-transport)
6. [The transfer loop](#6-the-transfer-loop)
7. [Transfer state machine](#7-transfer-state-machine)
8. [Scoring](#8-scoring)
9. [Degradation, hysteresis and switching](#9-degradation-hysteresis-and-switching)
10. [Worked examples](#10-worked-examples)
11. [Tuning the engine](#11-tuning-the-engine)
12. [Known quirks](#12-known-quirks)

---

## 1. Where this applies

| Situation | Path | Adaptive switching? |
|---|---|---|
| Light message (any size) | Fountain, direct | No: the user picked Light |
| Sound message ≤ 8 KiB | Fountain, direct | No |
| Sound message > 8 KiB | Protocol (`TransferManager`, legacy FSK) | Forced channel |
| Vibration message | Protocol | Forced channel |
| Legacy Messages screen, Hardware screen | Protocol | Optional |
| **Simulation Lab**, Performance comparison | Protocol over simulated channels | **Yes** |

In the everyday Send/Receive screens the user chooses the channel, so the engine's switching is demonstrated mainly in the Simulation Lab.

---

## 2. TransferManager: the end-to-end flow

`lib/core/manager/transfer_manager.dart`:

```
idle
 └─► discovering        _discoverPeer (unicast) — beacons until a discoveryResponse arrives
      └─► testingChannels   channelManager.testAll(testPacketCount = 20) → score each
           └─► negotiating      choose the channel:
                                  forced (user) → score 1.0
                                  broadcast     → optical, else acoustic, else first
                                  hardware + acoustic available → acoustic (0.9)
                                  otherwise     → decisionEngine.selectBestChannel
                └─► transferring    ReliableTransport + _transferLoop
                     ├─ every 20 iterations: _evaluateSwitch
                     │    degraded → testing alternatives → maybe switchingChannel → recovering
                     └─► completed / failed ─► idle
```

Transport configuration:

| Mode | `ackTimeoutMs` | `maxRetries` | `windowSize` | Packet size | Loop delay | Max iterations |
|---|---|---|---|---|---|---|
| Simulation | 500 | 5 | 8 | 256 B | 5 ms | 1 500 |
| Hardware | 20 000 | 8 | 4 | 1 400 / 512 / 48 B | 50 ms | 2 000 |

---

## 3. Discovery

**Sender** (unicast), repeated every 300 ms until timeout:
1. For each available channel, in the order **acoustic → optical → vibration** (vibration only on supported platforms):
   - make it active and transmit a `discovery` packet (payload `DC 01`);
   - read incoming packets. A `discoveryResponse` with the same session ID ends discovery and selects the channel it came on.

**Receiver:** on a `discovery` packet with the same session ID, it selects that channel and answers with `discoveryResponse`.

In `AppController`'s live receive loop, discovery replies go out only in **unicast** mode. An optical discovery is answered over **acoustic** when available, because the receiver's screen can't be seen by the sender's camera.

---

## 4. Channel selection

`AdaptiveDecisionEngine.selectBestChannel(testResults)`:
1. Score every test result (see [§8](#8-scoring)) and sort descending.
2. Pick the top one.
3. Explain the choice by comparing it with the runner-up: "Higher throughput and reliability", or "Lower packet loss", or "Lower latency", or the default "Highest composite channel score".

The result is a `ChannelDecision(selectedChannel, score, confidence, reason)`, which is logged and shown in the dev screens.

---

## 5. Reliable transport

`lib/core/transport/reliable_transport.dart`.

### 5.1 Fragmentation

```
chunks  = data split into packetSize pieces (at least one, possibly empty)
packet i (1-based) = PacketCodec.encode(header{type: data, seq: i, totalPackets: N, payloadLength}, chunk)
```

Every packet carries `totalPackets = N`, so the receiver knows when it's done even if packets arrive out of order.

### 5.2 Sender, unicast (sliding window)

```
window = [lastAcked + 1, lastAcked + windowSize] ∩ [1, N]
for seq in window: remember as pending (sentAt, retries = 0) and transmit
ACK(seq):  if seq > lastAcked: lastAcked = seq; drop pending ≤ seq
NACK(seq): retransmit seq (if retries < maxRetries)
retransmissionRequest(payload = list of u32 LE seqs): retransmit each
timeout:   any pending with now − sentAt > ackTimeoutMs → retransmit (retries++)
```

### 5.3 Sender, broadcast

Send each window's packets exactly **once** and never wait for ACKs. Done when `lastSent ≥ N`. Receivers stay silent, so they don't drown each other out (especially over sound).

### 5.4 Receiver

```
data(seq): if seen → duplicateCount++, re-ACK
           else store payload, ACK(seq), NACK every missing seq < max received
complete when all 1…N are present → reassemble in order
```

### 5.5 Channel switch messages

`createSwitchRequest(newChannel, lastConfirmed)` produces a `channelSwitchRequest` packet with an 8-byte payload `[u32 LE newChannelId, u32 LE lastConfirmed]` and `sequenceNumber = lastConfirmed`. `createSwitchAck` is the same structure, sent on the new channel. `resumeFromSequence(lastConfirmed)` sets `lastAcked` and drops pending packets up to it, so nothing already confirmed is resent.

---

## 6. The transfer loop

Each iteration of `_transferLoop`:

1. Stop if the user cancelled.
2. **Sender:** send the next window while not everything is acknowledged (broadcast: not everything sent).
3. Wait 50 ms (hardware) or 5 ms (simulation).
4. Receive, handle (data → ACK/NACK; ack; nack; retransmission request), and transmit any replies (skipped by a broadcast sender).
5. **Sender:** retransmit timed-out packets.
6. Receive and handle a second time (faster reaction within an iteration).
7. Exit conditions:
   - Receiver: transfer complete → reassemble.
   - Broadcast sender: all packets transmitted.
   - Unicast sender: `lastAcked ≥ N`.
   - Hardware: every pending packet exhausted its retries with nothing ever ACKed → "No acknowledgement from paired device"; or no progress within `peerInactivityTimeoutMs` → "Timed out waiting for paired device".
8. If adaptive switching is enabled and `i % 20 == 0`: `_evaluateSwitch()`.
9. Every 5 iterations: emit progress.

End state: `completed` on success, otherwise `failed` (forced).

---

## 7. Transfer state machine

`lib/core/manager/transfer_state_machine.dart`. There are ten states:

```
                 ┌─────────────────────────────── failed ◄── (any state except completed)
                 │                                  │
 idle ──► discovering ──► testingChannels ──► negotiating ──► transferring ──► completed
  ▲                                                          │     ▲              │
  │                                                          ▼     │              │
  │                                                      degraded ─┤              │
  │                                                          │     │              │
  │                                                          ▼     │              │
  │                                              switchingChannel ─┤              │
  │                                                          │     │              │
  │                                                          ▼     │              │
  │                                                      recovering┘              │
  └───────────────────────────────── completed / failed ◄─────────────────────────┘
```

Valid transitions (exactly as coded):

| From | To |
|---|---|
| idle | discovering, failed |
| discovering | testingChannels, failed |
| testingChannels | negotiating, failed |
| negotiating | transferring, failed |
| transferring | degraded, completed, failed |
| degraded | switchingChannel, recovering, transferring, failed |
| switchingChannel | recovering, transferring, failed |
| recovering | transferring, failed |
| completed | idle |
| failed | idle |

- `transition(to)` throws `StateError('Invalid state transition: …')` for anything else.
- `forceState(to)` bypasses validation. It's used to mark failure from any state.
- Every transition is appended to `history` with a timestamp, and the dev screens show it.

---

## 8. Scoring

### 8.1 Normalisation (`MetricNormalizer`)

```
T = clamp(throughput / 25 000, 0, 1)          throughput in bit/s
R = clamp(reliability, 0, 1)                  from a test: packetsReceived / packetsSent
L = clamp(1 − latency / 500, 0, 1)            latency in ms
C = clamp(confidence, 0, 1)
S = clamp(stability, 0, 1)
```

### 8.2 Weighted score (`ChannelScorer`)

```
score = 0.35·T + 0.25·R + 0.15·L + 0.15·C + 0.10·S          (defaultScoringWeights, sum = 1.0)
```

| Weight | Metric | Why this weight |
|---|---|---|
| 0.35 | Throughput | Transfer time is what users feel most |
| 0.25 | Reliability | Loss costs retransmissions and ACK timeouts |
| 0.15 | Latency | Affects ACK round trips and responsiveness |
| 0.15 | Confidence | Signal-quality evidence from the physical layer |
| 0.10 | Stability | Penalises channels whose quality fluctuates |

`setWeights` allows other profiles (e.g. a reliability-first weighting) to be plugged in.

### 8.3 Two ways to score

- `scoreTestResult(result)`: from a 20-packet channel test. Used for initial ranking and for **alternatives**.
- `scoreMetrics(metrics)`: from the channel's live `getMetrics()`. Used for the **current** channel during evaluation.

---

## 9. Degradation, hysteresis and switching

| Constant | Value | Source |
|---|---|---|
| `degradationThreshold` | **0.65** | `types.dart` |
| `switchHysteresisThreshold` | **0.15** | `types.dart` |
| Evaluation interval | every **20** loop iterations | `transfer_manager.dart` / orchestrator |
| Test size for alternatives | **20** packets | `testPacketCount` |

```
isDegraded(current)            = current < 0.65
shouldSwitch(current, alt)     = isDegraded(current)  AND  alt − current ≥ 0.15
```

**Why hysteresis.** Without a margin, two channels with similar scores would make the engine flip-flop on every evaluation, and each switch costs a handshake plus a resume. Requiring both "current is bad" *and* "the alternative is clearly better" prevents that.

**`_evaluateSwitch` procedure:**
1. Score the active channel from live metrics and store it.
2. If not degraded, return.
3. Log "quality degraded" and move transferring → degraded.
4. For each other available channel: run a 20-packet test, evaluate. On the first `shouldSwitch`, call `_performSwitch`.
5. If none qualifies: degraded → transferring (and log "Degraded but hysteresis not met").

**`_performSwitch(from, to)`:**
1. transferring/degraded → **switchingChannel**.
2. `lastConfirmed = transport.lastAckedSequence`.
3. Make `to` the active channel; `transport.setChannelId(to)`; `resumeFromSequence(lastConfirmed)`.
4. Transmit a `channelSwitchRequest(to, lastConfirmed)`. The peer answers with `channelSwitchAck` in the orchestrator.
5. Record a `SwitchEvent(from, to, lastConfirmed, timestamp, reason)`.
6. → **recovering** → **transferring**, resuming at `lastConfirmed + 1`.

---

## 10. Worked examples

### 10.1 Simulated channel defaults

(The confidence in a simulated test result is `confidence × (1 − loss/2)`.)

| Channel | Throughput | Loss | Latency | T | R | L | C | S | Score |
|---|---|---|---|---|---|---|---|---|---|
| Optical, healthy | 18 000 | 1% | 2 ms | 0.72 | 0.99 | 1.00 | 0.92 | 0.88 | **≈0.87** |
| Acoustic | 9 000 | 4% | 3 ms | 0.36 | 0.96 | 0.99 | 0.76 | 0.72 | **≈0.70** |
| Vibration | 800 | 6% | 120 ms | 0.03 | 0.94 | 0.76 | 0.70 | 0.68 | **≈0.53** |

Optical healthy, step by step:

```
0.35 × 0.72  = 0.252
0.25 × 0.99  = 0.2475
0.15 × 1.00  = 0.150
0.15 × 0.92  = 0.138
0.10 × 0.88  = 0.088
score        = 0.8755 ≈ 0.87
```

### 10.2 Scenario `optical-degrades`

After 15 packets, optical collapses to 2 kbps, 30% loss, 500 ms:

```
T = 2 000 / 25 000 = 0.08      R = 0.70      L = 1 − 500/500 = 0
C = 0.30                       S = 0.20
score = 0.35·0.08 + 0.25·0.70 + 0 + 0.15·0.30 + 0.10·0.20
      = 0.028 + 0.175 + 0 + 0.045 + 0.020 = 0.268
```

The scenario's acoustic alternative (9 kbps, 3% loss, 80 ms):

```
T = 0.36   R = 0.97   L = 1 − 80/500 = 0.84   C ≈ 0.79   S = 0.88
score = 0.126 + 0.2425 + 0.126 + 0.118 + 0.088 ≈ 0.70
```

Decision:

```
isDegraded(0.268)    → 0.268 < 0.65   ✓
0.70 − 0.268 = 0.43  → ≥ 0.15         ✓
⇒ switch optical → acoustic, resume from lastConfirmed + 1
```

The *decision* is correct. In the current simulator, though, the scenario still ends in failure. The first evaluation only happens at loop iteration 20, and each window on the degraded link takes seconds. By then the cumulative-ACK quirk ([§12](#12-known-quirks)) has already made the sender believe every packet was delivered. The switch happens with nothing left to resend, and the run times out after 1 500 iterations. Measured runs and details: [Simulation Lab](../development/SIMULATION_LAB.md).

### 10.3 A case where hysteresis holds

Current score 0.60 (degraded), best alternative 0.70. The gap of 0.10 is below 0.15, so the engine **does not switch** and logs "Degraded but hysteresis not met (0.10 < 0.15)". It stays on the current channel, avoiding a costly switch for a marginal gain.

### 10.4 A case where degradation isn't reached

Current 0.66, alternative 0.95. The current channel isn't degraded (0.66 ≥ 0.65), so the engine doesn't switch even though the alternative is much better. By design, the engine switches only to *escape* a bad channel, not to chase a better one mid-transfer.

---

## 11. Tuning the engine

| Goal | Change |
|---|---|
| Prefer reliable over fast | Raise the R weight (e.g. 0.40) and lower T (0.20) via `ChannelScorer.setWeights` |
| Switch sooner | Raise `degradationThreshold` (e.g. 0.75) |
| Avoid switching unless clearly better | Raise `switchHysteresisThreshold` (e.g. 0.25) |
| React faster | Evaluate every 10 iterations instead of 20 (costs more test traffic) |
| Channels faster than 25 kbps | Raise `maxThroughput` in `MetricNormalizer`, or T saturates at 1 |

Keep the weights summing to 1.0, so scores stay comparable with the 0.65 threshold.

---

## 12. Known quirks

These are documented behaviours of the current code (see also [Known Issues](../project/KNOWN_ISSUES.md) and [Simulation Lab](../development/SIMULATION_LAB.md)):

- **Cumulative ACK handling.** The receiver ACKs each packet individually, but the sender treats any ACK as cumulative (`lastAcked = seq`, and it drops all pending packets ≤ seq). An out-of-order ACK can therefore mark an unreceived earlier packet as delivered. A later NACK then finds nothing pending to resend, so under heavy loss the sender can report "all acknowledged" while the receiver still has gaps. This is why the `optical-degrades` and `burst-loss` simulations fail.
- **Hardware selection prefers acoustic.** In hardware mode with acoustic available and no forced channel, `TransferManager` picks acoustic (fixed score 0.9, "Acoustic is bidirectional") instead of the scored best.
- **The vibration airtime exceeds the ACK timeout.** A 76-byte vibration packet takes about 148 s on air, against a 20 s timeout.
- **Simulation:** undiscoverable channels are still tested; override profiles replace *all* fields; the "fixed" comparison strategies still run the adaptive orchestrator.
