# Simulation Lab

The Simulation Lab runs a complete adaptive transfer between two virtual phones, a sender **A** and a receiver **B**, entirely in software. Three simulated channels (optical, acoustic and vibration) connect them through a packet-level medium model that drops, corrupts and delays packets according to a per-channel profile. The same `ReliableTransport`, `TransferStateMachine` and `AdaptiveDecisionEngine` classes used by the protocol path of the app decide which channel to use and when to switch. The companion Performance Comparison screen reuses this machinery to compare an "adaptive" run with two "fixed-channel" runs. This document covers the medium model, every scenario, the transfer loop, the switching logic with a worked example, the screens, how to add a scenario, and the quirks that were confirmed in the code. Every constant here is copied from the code. Observed outcomes come from probe runs of the unmodified code on 2026-09-27. The medium's random generator is unseeded, so your runs will differ in detail.

Back to the [documentation index](../README.md).

---

## Contents

1. [What the lab is for](#1-what-the-lab-is-for)
2. [Opening it and every control](#2-opening-it-and-every-control)
3. [Architecture](#3-architecture)
4. [The medium model](#4-the-medium-model)
5. [Scenarios](#5-scenarios)
6. [The transfer loop and adaptive switching](#6-the-transfer-loop-and-adaptive-switching)
7. [Logs, metrics and panels](#7-logs-metrics-and-panels)
8. [Performance Comparison](#8-performance-comparison)
9. [Adding a scenario or a channel profile](#9-adding-a-scenario-or-a-channel-profile)
10. [Known quirks](#10-known-quirks)

---

## 1. What the lab is for

The real Light, Sound and Vibration channels need two phones, a camera, a speaker and a quiet room, and they use the rateless fountain modems described elsewhere. The Simulation Lab exercises a different layer: the adaptive protocol stack of discovery, channel testing, scoring, a sliding-window reliable transport, degradation detection and a channel-switch handshake. It exercises that stack without any hardware, so the decision logic can be demonstrated and debugged on a laptop.

Use it to:

- watch the adaptive engine pick a channel from 20-packet test results and see the score of every channel;
- watch a channel degrade mid-transfer and see the engine flag it (score below 0.65) and look for a better alternative (at least 0.15 higher);
- see the transport's ACK, NACK and retransmission traffic in a live log;
- compare an adaptive run with fixed-channel runs on the Performance Comparison screen.

The lab is not a physical-layer model. There is no signal-to-noise ratio, no modulation and no fountain coding. Each channel is reduced to a throughput, a loss probability, a corruption probability, a latency with jitter, and two quality numbers (confidence and stability). The simulation core in `lib/core/simulation/` is pure Dart and imports nothing from Flutter. For the scoring formula in isolation see [ADAPTIVE_ENGINE.md](../algorithms/ADAPTIVE_ENGINE.md). For every formula in one place see [CALCULATIONS.md](../algorithms/CALCULATIONS.md).

---

## 2. Opening it and every control

### 2.1 Opening the screens

Neither screen is on the home screen; `test/widget_test.dart` checks that the text "Simulation Lab" is not found there. To open them:

1. On the home screen, tap the **⋮** icon (tooltip "Developer tools"). This pushes `DevMenuScreen`, titled **Developer tools**.
2. Tap **Simulation Lab** ("Virtual endpoints with adaptive channel switching") to open `SimulationScreen`, or **Performance Comparison** ("Compare fixed vs adaptive strategies") to open `PerformanceScreen`.

Both screens read and drive the shared `AppController`. Its single `running` flag is shared by every long operation in the app, so the buttons below are disabled while any simulation, comparison or hardware operation is in progress.

### 2.2 Simulation Lab controls

| Control | Where | What it does |
|---|---|---|
| **Scenario** drop-down | "Scenario" card at the top | Lists the `name` of every entry in `scenarios` (section 5), in list order. The initial selection is `optical-degrades` ("Optical Starts Good, Becomes Poor"), from `AppController._scenarioId`. Changing it calls `setScenario(id)`. Disabled while running |
| **Run Simulation** | Scenario card | Calls `AppController.runSimulation()`. It clears the live log and both panels, builds the scenario's pair, subscribes to both endpoints' loggers, sets `onUpdate` so the panels refresh on every snapshot, and runs `SimulationOrchestrator.runTransfer(generateTestData(dataSize))`. While running, the label reads "Running…" with a spinner |
| **Clear Logs** | Scenario card | Calls `clearLogs()`, which empties the live log list and the app's own `StructuredLogger`. Disabled while running |
| **Run All Scenarios** | App bar; labelled "Run All" on narrow layouts | Calls `runAllScenarios()`. It runs every scenario in order with its own `dataSize`, counts `result.success`, and sets the status message to `N/9 scenarios passed`. See [quirk 12](#10-known-quirks) for what the screen does not show |
| **Sender (A)** panel | Body | An `EndpointPanel` showing endpoint A's latest `DashboardSnapshot` (section 7.2) |
| **Receiver (B)** panel | Body | The same for endpoint B |
| **LIVE LOGS** panel | Body | A `LogPanel` listing every log entry from both endpoints as it happens (section 7.1) |
| **SUCCESS** / **FAILED** chip | Below the panels | Appears after a single run, from `lastSimResult.success` |

On wide layouts the two endpoint panels and the log panel sit side by side in a row. On narrow layouts they are stacked in a column with flex ratios 2 : 2 : 3. Before the first run the endpoint panels show "Waiting for transfer" and the log panel shows "Logs will appear here during transfer".

### 2.3 Performance Comparison controls

| Control | What it does |
|---|---|
| **Run Comparison** (in the "Baseline Comparison" card) | Calls `runPerformanceComparison()`, which clears the previous results and awaits `PerformanceComparator().runComparison()`. The label reads "Running…" with a spinner while it works |
| Result cards | One card per strategy (section 8). Wide layouts use a grid, with 3 columns on desktop and 2 otherwise. Narrow layouts use a list. Before the first run the area shows "Run comparison to see results" |

### 2.4 Simulation mode outside the lab

`AppController` starts in `OperationMode.simulation`. In that mode, sending a chat message from **Legacy Messages** (also in Developer tools) calls `runSimulation(data: envelope)` with the currently selected scenario instead of the scenario's generated test data. The message is marked delivered when `dataMatch` is true and failed otherwise.

---

## 3. Architecture

### 3.1 Classes

| Class or function | File | Role |
|---|---|---|
| `ChannelSimulationProfile` | `lib/core/simulation/simulated_medium.dart` | Seven numbers that describe a simulated channel (section 4.1) |
| `DegradationSchedule` | same | `afterPacket` plus a replacement `profile` |
| `SimulatedChannelConfig` | same | A base `profile` plus optional `degradation` and `recovery` schedules |
| `SimulatedMedium` | same | Applies the active profile to every packet sent; queues packets for the peer; runs discovery and channel tests |
| `VirtualLink` | same | Cross-connects two media so that each one's output is the other's input |
| `profileToMetrics`, `profileToTestResult` | same | Convert a profile into the `ChannelMetrics` and `ChannelTestResult` that the engine scores |
| `SimulatedCommChannel`, `createOpticalChannel`, `createAcousticChannel`, `createVibrationChannel` | `lib/core/channels/comm_channel.dart` | The `CommChannel` implementation backed by a `SimulatedMedium` |
| `ChannelManager` | `lib/core/manager/channel_manager.dart` | Holds the registered channels and the active channel; `discoverAll`, `testAll`, `testChannel`, `transmit`, `receiveActive` |
| `VirtualEndpoint` | `lib/core/simulation/simulation_orchestrator.dart` | One virtual phone: id, role, logger, channel manager, state machine, decision engine, transport, scores, switch events |
| `SimulationPair`, `createSimulationPair` | same | Build both endpoints, six media, six channels and three links |
| `SimulationOrchestrator` | same | `runTransfer(data)` drives one full transfer and returns a `SimulationResult` |
| `generateTestData(size)` | same | Test payload whose byte `i` is `i % 256` |
| `ScenarioDefinition`, `scenarios`, `getScenario` | `lib/core/simulation/scenarios.dart` | The nine named scenarios |
| `ReliableTransport`, `TransportConfig` | `lib/core/transport/reliable_transport.dart` | Packetisation, sliding window, ACK/NACK handling, timeouts, switch packets |
| `AdaptiveDecisionEngine`, `ChannelScorer`, `MetricNormalizer` | `lib/core/engine/adaptive_decision_engine.dart` | Scoring, selection, degradation test, switch test |
| `TransferStateMachine` | `lib/core/manager/transfer_state_machine.dart` | Validated state transitions |
| `StructuredLogger` | `lib/core/logging/structured_logger.dart` | Categorised log with listeners |
| `PerformanceComparator`, `StrategyResult`, `TransferStrategy`, `strategyLabel` | `lib/core/performance/performance_comparator.dart` | The comparison runs (section 8) |
| `AppController` | `lib/application/app_controller.dart` | `runSimulation`, `runAllScenarios`, `runPerformanceComparison`, `setScenario`, `clearLogs` |

`TransferManager` is not used by the lab. `createChannelManagerForMode(OperationMode.simulation)` in `transfer_manager.dart` can register the simulated channels of a pair's endpoint A for use with `TransferManager`, but the app only calls that function in hardware mode. Class signatures are listed in [API_REFERENCE.md](API_REFERENCE.md), and the screens and widgets are described in [UI_GUIDE.md](UI_GUIDE.md).

### 3.2 How the pieces are wired

`createSimulationPair(...)` builds the whole two-phone world:

1. For each of the six (channel, endpoint) combinations it builds a `SimulatedChannelConfig` whose profile is `defaultXProfile.copyWith(...)` with every field of the optional override profile. Degradation and recovery schedules are attached to **endpoint A's** configs only.
2. It creates two `StructuredLogger`s and two `ChannelManager`s.
3. It creates six media named `A-optical`, `B-optical`, `A-acoustic`, `B-acoustic`, `A-vibration` and `B-vibration`.
4. It registers three `SimulatedCommChannel`s with each manager, in the order optical, acoustic, vibration. That order is also the order used for discovery, testing and trying switch alternatives.
5. It links the pairs with `VirtualLink(A-optical, B-optical)`, `VirtualLink(A-acoustic, B-acoustic)` and `VirtualLink(A-vibration, B-vibration)`.
6. It returns endpoint `A` with role `sender` and endpoint `B` with role `receiver`.

```
                      SimulationOrchestrator.runTransfer(data)
                                        |
             +--------------------------+---------------------------+
             v                                                      v
  VirtualEndpoint A (sender)                             VirtualEndpoint B (receiver)
    TransferStateMachine                                   TransferStateMachine
    AdaptiveDecisionEngine  (scores, decides)              AdaptiveDecisionEngine (unused)
    ReliableTransport       (sends data)                   ReliableTransport      (ACKs, NACKs)
    StructuredLogger                                       StructuredLogger
    ChannelManager A                                       ChannelManager B
     |- SimulatedCommChannel OPTICAL                        |- SimulatedCommChannel OPTICAL
     |    SimulatedMedium A-optical  <==VirtualLink==>      |    SimulatedMedium B-optical
     |- SimulatedCommChannel ACOUSTIC                       |- SimulatedCommChannel ACOUSTIC
     |    SimulatedMedium A-acoustic <==VirtualLink==>      |    SimulatedMedium B-acoustic
     |- SimulatedCommChannel VIBRATION                      |- SimulatedCommChannel VIBRATION
          SimulatedMedium A-vibration <==VirtualLink==>          SimulatedMedium B-vibration
     (degradation / recovery schedules live here)           (profiles never change)
```

A packet sent by A on optical is shaped by **A-optical's** profile. An ACK or NACK sent back by B on optical is shaped by **B-optical's** profile. The two directions of one channel can therefore behave differently.

### 3.3 How a simulated transfer runs

`SimulationOrchestrator(pair).runTransfer(data)` goes through these phases. Section 6 describes the loop and the switching in detail.

| Phase | What happens | Sender state | Receiver state |
|---|---|---|---|
| Setup | `initializeAll()` and `startAll()` on both managers; a new session ID and transfer ID are created and copied to B; both state machines are reset | `idle` | `idle` |
| Discovery | `discoverAll(300)` on A's manager, then on B's. If either list is empty the run ends at once with `success: false` | `discovering` | `discovering` |
| Testing | `testAll(20)` on **A's** manager tests every registered channel; each result is scored with `scoreTestResult` and written to both endpoints' `channelScores` | `testingChannels` | `testingChannels` |
| Selection | `selectBestChannel(testResults)` picks the highest score; both managers set it active | `negotiating` | `negotiating` |
| Transfer | A `ReliableTransport` is created on each side; A splits the data into packets; the loop runs for up to 1500 iterations | `transferring`, and `degraded` → `switchingChannel` → `recovering` → `transferring` around a switch | `transferring` |
| Verification | The receiver's reassembled data is compared with the original | `completed`, or forced to `failed` | `completed`, or forced to `failed` |

The orchestrator calls `onUpdate(senderSnapshot, receiverSnapshot)` at each phase change, every 5 loop iterations and once at the end. Only the sender's state machine ever enters `degraded`, `switchingChannel` or `recovering`.

---

## 4. The medium model

### 4.1 Profile fields

A `ChannelSimulationProfile` has seven fields. The constructor defaults matter because any profile written in a scenario starts from them, not from the channel's own default (see [quirk 2](#10-known-quirks)).

| Field | Constructor default | Meaning |
|---|---|---|
| `baseThroughput` | 18000 | Bits per second, used for the per-packet air time |
| `packetLossRate` | 0.01 | Probability that a sent packet is dropped |
| `baseLatencyMs` | 80 | Fixed latency in ms, before jitter |
| `confidence` | 0.92 | Quality number from 0 to 1, fed to the scorer |
| `stability` | 0.88 | Quality number from 0 to 1, fed to the scorer |
| `corruptionRate` | 0.005 | Probability that one byte of a delivered packet is flipped |
| `discoverable` | `true` | Whether the discovery probe can succeed |

### 4.2 Default channel profiles

These constants are used when a scenario does not override a channel.

| Channel | Constant | Throughput | Loss | Latency | Confidence | Stability | Corruption | Discoverable |
|---|---|---|---|---|---|---|---|---|
| Optical | `defaultOpticalProfile` | 18 000 bps | 0.01 | 2 ms | 0.92 | 0.88 | 0.005 | yes |
| Acoustic | `defaultAcousticProfile` | 9 000 bps | 0.04 | 3 ms | 0.78 | 0.72 | 0.01 | yes |
| Vibration | `defaultVibrationProfile` | 800 bps | 0.06 | 120 ms | 0.72 | 0.68 | 0.015 | yes |

`defaultOpticalProfile` only sets `baseLatencyMs: 2`; its other fields are the constructor defaults. The simulated channels advertise `ChannelCapabilities` named `Optical (Simulated)`, `Acoustic (Simulated)` and `Vibration (Simulated)`, with `maxThroughput` equal to the configured `baseThroughput`, `minLatency` equal to the configured `baseLatencyMs`, `supportsBinary: true` and `hardwareImplemented: false`.

### 4.3 What happens to a sent packet

`SimulatedCommChannel.transmit(packet)` throws a `StateError` if the channel has not been started, and otherwise awaits `SimulatedMedium.send(raw)`. `send` applies the medium's **active profile** in this order:

1. **Count and schedule.** `_packetsProcessed` is incremented, then `_checkDegradation()` and `_checkRecovery()` run (section 4.6).
2. **Loss.** If `random.nextDouble() < packetLossRate`, the method returns at once. The packet is gone and **costs no time**.
3. **Corruption.** If `random.nextDouble() < corruptionRate` and the packet is longer than the 24-byte header, one byte is XORed with `0xFF`. The index is `headerSize + random.nextInt(max(1, length − headerSize − crcSize))` with `headerSize = 24` and `crcSize = 4`. For a data packet this lands in the payload. For a 28-byte ACK or NACK it lands on the first CRC byte. Either way the receiver's CRC-32 check fails, `packetCodec.decode` returns `null`, and the packet is silently discarded, so corruption behaves like extra loss.
4. **Delay.** The sender's `send` call waits for the whole flight time:

   ```
   latency         = baseLatencyMs + (random.nextDouble() × 2 − 1) × 15      (uniform jitter of ±15 ms)
   throughputDelay = (raw.length × 8) / baseThroughput × 1000                (ms)
   delayMs         = max(1, round(latency + throughputDelay))
   ```

5. **Deliver.** The possibly corrupted copy is handed to the peer's `receiveFromPeer`, which queues it with `deliverAt = now`. The peer's next `pollReceived()` returns everything queued, in arrival order, and `SimulatedCommChannel.receive()` decodes it.

Because the orchestrator awaits every `send`, only one packet is ever in flight, packets are never reordered, and a window of 8 packets blocks the sender for the sum of the delays of the packets that were not lost. The medium has no separate noise model: corruption stands in for noise, and the ±15 ms jitter is the only timing randomness. Each medium uses its own unseeded `Random()`.

A full data packet is 256 payload bytes plus 28 bytes of overhead (24-byte header and 4-byte CRC-32), which is 284 bytes. ACK and NACK packets have no payload and are 28 bytes. The table shows the mean delay per delivered packet. Every value varies by ±15 ms, and the result is never below 1 ms.

| Profile | Data packet (284 B) | ACK / NACK (28 B) |
|---|---|---|
| Default optical (18 000 bps, 2 ms) | 126.2 + 2 ≈ 128 ms | 12.4 + 2 ≈ 14 ms |
| Default acoustic (9 000 bps, 3 ms) | 252.4 + 3 ≈ 255 ms | 24.9 + 3 ≈ 28 ms |
| Default vibration (800 bps, 120 ms) | 2 840 + 120 ≈ 2 960 ms | 280 + 120 = 400 ms |
| Degraded optical in `optical-degrades` (2 000 bps, 500 ms) | 1 136 + 500 ≈ 1 636 ms | 112 + 500 ≈ 612 ms |

### 4.4 Discovery and channel tests

Discovery and channel tests do not send packets through the link. They sample the sender's active profile directly.

| Method | Behaviour |
|---|---|
| `runDiscoveryTest(timeoutMs)` | Returns `false` at once if `discoverable` is false. Otherwise it waits `min(timeoutMs, round(50 + random × 100))` ms and returns `random > packetLossRate × 2`. With a loss rate of 0.01, discovery succeeds 98% of the time |
| `runChannelTest(n)` | For each of `n` virtual packets it counts one as received if `random >= packetLossRate`, then waits `round(baseLatencyMs / n)` ms. It returns `(sent: n, received: k)` |

`SimulatedCommChannel.test(n)` turns the counts into a `ChannelTestResult` with `profileToTestResult`:

```
measuredLoss = (sent − received) / sent        (packetLossRate if sent == 0)
throughput   = baseThroughput × (1 − measuredLoss)
latency      = baseLatencyMs
confidence   = confidence × (1 − measuredLoss × 0.5)
stability    = stability
```

With 20 test packets the measured loss moves in steps of 5%.

### 4.5 Metrics seen by the engine and the panels

`SimulatedCommChannel.getMetrics()` returns the **configured** values of the active profile through `profileToMetrics`. Nothing is measured from the traffic.

```
throughput  = baseThroughput
packetLoss  = packetLossRate
latency     = baseLatencyMs
reliability = max(0, 1 − packetLossRate − corruptionRate)
errorRate   = corruptionRate
confidence  = confidence
stability   = stability
```

These values drive the mid-transfer re-evaluation (section 6.3), the Throughput, Packet Loss and Latency rows of the endpoint panels, and the Throughput and Packet Loss fields of the Performance Comparison.

### 4.6 Degradation and recovery schedules

A `DegradationSchedule` has an `afterPacket` count and a replacement `profile`. On every `send`:

- `_checkDegradation()`: if `_packetsProcessed >= degradation.afterPacket`, the active profile becomes `activeProfile.merge(degradation.profile)`. `merge` copies **every** field from the schedule's profile.
- `_checkRecovery()`: if `_packetsProcessed >= recovery.afterPacket`, the active profile becomes `recovery.profile`.

The following consequences come straight from the code:

- The counter is incremented before the check, so `afterPacket: 15` means "from the 15th send onward".
- Every call to `send` counts: first transmissions, window re-sends, timeout and NACK retransmissions, switch requests, and packets that are then lost. Discovery probes and channel tests do not count.
- Both checks run on every send, so once both thresholds have been passed, recovery wins because it runs second.
- Schedules exist only on endpoint A's media. They only fire if A actually sends on that channel, which normally means that the channel is active.
- A channel test run after the degradation samples the degraded profile, because tests read the active profile.

---

## 5. Scenarios

`lib/core/simulation/scenarios.dart` defines nine `ScenarioDefinition`s. Each has an `id`, a `name`, a `description`, a `dataSize` in bytes and a `createPair` function that calls `createSimulationPair(...)`. The payload is `generateTestData(dataSize)`, and the packet count is `ceil(dataSize / 256)`.

### 5.1 Definitions as written

| `id` | `name` | `dataSize` | Packets | Overrides and schedules as written in the code |
|---|---|---|---|---|
| `optical-always-good` | Optical Always Good | 4096 | 16 | Optical A and B: loss 0.005, 20 000 bps. Acoustic A and B: loss 0.05 |
| `acoustic-always-good` | Acoustic Always Good | 4096 | 16 | Optical A and B: `discoverable: false`. Acoustic A and B: loss 0.02, 10 000 bps |
| `optical-degrades` | Optical Starts Good, Becomes Poor | 8192 | 32 | Acoustic A: loss 0.03, 9 000 bps, confidence 0.8. Acoustic B: loss 0.03, 9 000 bps. Optical degradation after 15 sends: 2 000 bps, loss 0.30, 500 ms, confidence 0.3, stability 0.2 |
| `random-loss` | Random Packet Loss | 4096 | 16 | Optical A: loss 0.08, corruption 0.02. Optical B: loss 0.08. Acoustic A and B: loss 0.06 |
| `burst-loss` | Burst Packet Loss | 6144 | 24 | Optical degradation after 8 sends: loss 0.45, 4 000 bps, 300 ms |
| `both-degrade` | Both Channels Degrade | 2048 | 8 | Optical degradation after 10 sends: loss 0.25, 3 000 bps. Acoustic degradation after 10 sends: loss 0.20, 4 000 bps |
| `acoustic-recovers` | Acoustic Starts Poor, Recovers | 4096 | 16 | Optical A and B: `discoverable: false`. Acoustic A: loss 0.15, 3 000 bps, confidence 0.4. Acoustic B: loss 0.15, 3 000 bps. Acoustic recovery after 30 sends: loss 0.02, 10 000 bps, confidence 0.85 |
| `repeated-degradation` | Repeated Degradation and Recovery | 10240 | 40 | Acoustic A and B: loss 0.05, 8 000 bps. Optical degradation after 12 sends: loss 0.35, 2 500 bps, confidence 0.25. Optical recovery after 35 sends: loss 0.01, 18 000 bps, confidence 0.9 |
| `vibration-coupled` | Vibration Coupled | 2048 | 8 | Optical and acoustic A and B: `discoverable: false`. Vibration A: loss 0.03, 900 bps, confidence 0.82. Vibration B: loss 0.03, 900 bps |

### 5.2 Effective profiles

Because an override starts from the constructor defaults ([quirk 2](#10-known-quirks)), fields that a scenario never mentions still change. The table lists the profiles that `createSimulationPair` actually builds, as throughput / loss / latency / confidence / stability / corruption. "Default" means the channel's own default from section 4.2.

| `id` | Optical | Acoustic | Vibration | Schedules (endpoint A only) |
|---|---|---|---|---|
| `optical-always-good` | 20 000 / 0.005 / 80 / 0.92 / 0.88 / 0.005 | 18 000 / 0.05 / 80 / 0.92 / 0.88 / 0.005 | default | none |
| `acoustic-always-good` | 18 000 / 0.01 / 80 / 0.92 / 0.88 / 0.005, not discoverable | 10 000 / 0.02 / 80 / 0.92 / 0.88 / 0.005 | default | none |
| `optical-degrades` | default (18 000 / 0.01 / 2 / 0.92 / 0.88 / 0.005) | A: 9 000 / 0.03 / 80 / 0.8 / 0.88 / 0.005; B: 9 000 / 0.03 / 80 / 0.92 / 0.88 / 0.005 | default | Optical from send 15: 2 000 / 0.30 / 500 / 0.3 / 0.2 / 0.005 |
| `random-loss` | A: 18 000 / 0.08 / 80 / 0.92 / 0.88 / 0.02; B: 18 000 / 0.08 / 80 / 0.92 / 0.88 / 0.005 | 18 000 / 0.06 / 80 / 0.92 / 0.88 / 0.005 | default | none |
| `burst-loss` | default | default | default | Optical from send 8: 4 000 / 0.45 / 300 / 0.92 / 0.88 / 0.005 |
| `both-degrade` | default | default | default | Optical from send 10: 3 000 / 0.25 / 80 / 0.92 / 0.88 / 0.005; acoustic from send 10: 4 000 / 0.20 / 80 / 0.92 / 0.88 / 0.005 |
| `acoustic-recovers` | 18 000 / 0.01 / 80 / 0.92 / 0.88 / 0.005, not discoverable | A: 3 000 / 0.15 / 80 / 0.4 / 0.88 / 0.005; B: 3 000 / 0.15 / 80 / 0.92 / 0.88 / 0.005 | default | Acoustic from send 30: 10 000 / 0.02 / 80 / 0.85 / 0.88 / 0.005 |
| `repeated-degradation` | default | 8 000 / 0.05 / 80 / 0.92 / 0.88 / 0.005 | default | Optical from send 12: 2 500 / 0.35 / 80 / 0.25 / 0.88 / 0.005; optical from send 35: 18 000 / 0.01 / 80 / 0.9 / 0.88 / 0.005 |
| `vibration-coupled` | 18 000 / 0.01 / 80 / 0.92 / 0.88 / 0.005, not discoverable | 18 000 / 0.01 / 80 / 0.92 / 0.88 / 0.005, not discoverable | A: 900 / 0.03 / 80 / 0.82 / 0.88 / 0.005; B: 900 / 0.03 / 80 / 0.92 / 0.88 / 0.005 | none |

### 5.3 What happens

"Intended" paraphrases the scenario's name and description. "Observed" comes from two runs of each scenario on 2026-09-27, and four runs of `optical-degrades` and `burst-loss`. The scores quoted are the initial 20-packet test scores.

| `id` | Intended | Observed | Why |
|---|---|---|---|
| `optical-always-good` | Optical chosen, stays good | Success every time on optical (0.882), no switch, about 13.7 s | As intended. Acoustic scored 0.740 to 0.854, because its override gives it 18 000 bps |
| `acoustic-always-good` | Optical unavailable, acoustic chosen | Success every time, but on **optical** (0.854 against acoustic 0.742), about 14 s | Undiscoverable channels are still tested and ranked ([quirk 1](#10-known-quirks)), and the override gives optical 18 000 bps |
| `optical-degrades` | Optical first, degrades, switch to acoustic | **Failed in all 4 runs**, 135 to 146 s. One switch OPTICAL to ACOUSTIC per run, always with "Last confirmed packet = 32" | The switch only happens after the transfer has already stalled because of cumulative ACK handling ([quirk 4](#10-known-quirks)). Section 6.4 walks through it |
| `random-loss` | Optical carries on through 8% loss | Success every time. Acoustic was chosen once (0.854 against 0.825) and optical once. 14.7 to 16.6 s | Both overrides give 18 000 bps with 6–8% loss, so the random 20-packet test decides |
| `burst-loss` | Optical degrades after send 8 and the engine reacts | **Failed in all 4 runs**, 62 to 70 s. One switch OPTICAL to ACOUSTIC per run at "Last confirmed packet = 24" | Same mechanism as `optical-degrades`. In one run the sender had all 24 packets acknowledged while the receiver was still missing packet 18. Degraded optical scores 0.478 and acoustic about 0.70 |
| `both-degrade` | Both degrade, no clearly better alternative | Success every time on optical, no switch, 5.8 to 6.8 s | Only 8 packets, so the transfer ends before the first re-evaluation. If re-evaluated, degraded optical would score 0.580 against about 0.69–0.71 for untouched acoustic, a gap below 0.15 |
| `acoustic-recovers` | Acoustic chosen while poor, then recovers | Success every time on **optical** (0.854 against acoustic 0.50 to 0.52), about 14 s | Quirk 1. Acoustic is never used, so its send counter never reaches 30 and the recovery never fires |
| `repeated-degradation` | Optical degrades at send 12, recovers at send 35 | Success every time on optical, no switch, 37.6 to 40.4 s | No re-evaluation is reached while optical is degraded, and the recovery arrives before the 40 packets finish |
| `vibration-coupled` | Only vibration usable, vibration chosen | Success every time on **optical** (0.854; acoustic 0.825 to 0.854; vibration 0.600), about 6 s | Quirk 1. Only vibration is discoverable, and it passes discovery with probability 0.94 on each endpoint, so about 12% of runs (1 − 0.94²) end with "Discovery failed" |

A full **Run All** therefore takes around five minutes and, on the evidence above, usually reports 7 of 9 passed, because `optical-degrades` and `burst-loss` fail. The automated tests in `test/simulation_integration_test.dart` cover only `optical-always-good` and `random-loss` with 1024 bytes and `acoustic-always-good` with its own 4096 bytes. They assert only that the data matches. See [TESTING.md](TESTING.md).

---

## 6. The transfer loop and adaptive switching

### 6.1 Constants

| Setting | Value | Source |
|---|---|---|
| Discovery timeout | 300 ms | `runTransfer` |
| Test packets, initial and per alternative | 20 | `runTransfer`, `_evaluateAndSwitch` |
| Packet payload size | 256 bytes | `TransmissionConfig.packetSize` |
| ACK timeout | 500 ms | `TransportConfig.ackTimeoutMs` |
| Max retries per packet | 5 | `TransportConfig.maxRetries` |
| Window | 8 packets | `TransportConfig.windowSize` |
| Loop delay | 5 ms per iteration | `runTransfer` |
| Max loop iterations | 1500 | `runTransfer` |
| Re-evaluation | when `i − lastMonitor >= 20`, so first at iteration 20, then 40, 60 and so on | `runTransfer` |
| Degradation threshold | score below 0.65 | `degradationThreshold` |
| Switch hysteresis | alternative − current ≥ 0.15 | `switchHysteresisThreshold` |
| Snapshot emission | every 5 iterations | `runTransfer` |

### 6.2 One loop iteration

After selection, the sender calls `createDataPackets(data)`, which numbers the packets 1 to N and encodes each one once. The receiver calls `setExpectedTotalPackets(N)`. Each iteration then does the following:

1. If `sender.lastAckedSequence < N`, call `sendNextWindow`, which transmits packets `lastAcked + 1` to `lastAcked + 8`. Packets that are already pending are sent again on every iteration without counting as retries.
2. Wait 5 ms.
3. Poll both active channels with `receiveActive()`. The receiver stores each new data packet and replies with an ACK for it, plus a NACK for every gap below the highest sequence it holds. The sender handles ACK, NACK and retransmission-request packets and transmits any retransmissions.
4. Run `_handleSwitchNegotiation`, which polls both channels again and acts only on `channelSwitchRequest` and `channelSwitchAck` packets. Any other packet read here is dropped ([quirk 5](#10-known-quirks)).
5. Call `checkTimeouts()`, which retransmits every pending packet older than 500 ms that has fewer than 5 retries.
6. Poll and handle both sides once more.
7. If the receiver holds all N packets, reassemble the data and leave the loop.
8. If `i − lastMonitor >= 20`, set `lastMonitor = i` and run `_evaluateAndSwitch`.
9. If `i % 5 == 0`, emit a snapshot.

When the loop ends, `dataMatch` is true if the reassembled data is at least `data.length` long and its first `data.length` bytes equal the original. On a match both state machines go to `completed`. Otherwise both are forced to `failed`. Reaching 1500 iterations without completing is a failure.

### 6.3 Re-evaluation and the switch handshake

`_evaluateAndSwitch` runs on the sender only:

1. It scores the active channel's `getMetrics()` with `scoreMetrics`. These are the configured profile values from section 4.5, not measurements. The score is stored in `channelScores`.
2. If the score is 0.65 or more, it returns.
3. Otherwise it logs `<CHANNEL> quality degraded (score=x.xx)` and moves the sender from `transferring` to `degraded`.
4. For each other registered channel, in the order optical, acoustic, vibration, it logs `Testing <CHANNEL> channel`, runs a fresh 20-packet test and calls `evaluateSwitch(current, currentMetrics, altResult)`. That scores the alternative with `scoreTestResult` and switches if `current < 0.65` and `alternative − current >= 0.15`. The **first** alternative that qualifies wins, not necessarily the best one.
5. If no alternative qualifies, the sender goes back from `degraded` to `transferring`.

The two inputs to the formula differ:

| Used for | Function | Throughput | Reliability | Latency | Confidence |
|---|---|---|---|---|---|
| Initial selection and alternatives | `scoreTestResult` | `baseThroughput × (1 − measuredLoss)` | `received / sent` | `baseLatencyMs` | `confidence × (1 − measuredLoss / 2)` |
| Re-evaluating the active channel | `scoreMetrics` | `baseThroughput` | `1 − packetLossRate − corruptionRate` | `baseLatencyMs` | `confidence` |

In both cases `score = 0.35·T + 0.25·R + 0.15·L + 0.15·C + 0.10·S`, with `T = clamp(throughput / 25000, 0, 1)`, `L = clamp(1 − latency / 500, 0, 1)` and R, C and S clamped to 0–1.

`_performSwitch(from, to)` then does the following:

1. The sender goes to `switchingChannel`, and `lastConfirmed` is set to `sender.lastAckedSequence`.
2. It logs `Switching FROM → TO` (DECISION) and `Last confirmed packet = N` (SWITCH).
3. On both endpoints it calls `setActiveChannel(to)`, `transport.setChannelId(to)` and `transport.resumeFromSequence(lastConfirmed)`, which sets `lastAckedSequence` and drops pending packets up to `lastConfirmed`.
4. The sender transmits a `channelSwitchRequest` on the new channel. Its payload is two little-endian u32 values, the new channel ID and `lastConfirmed`, and its header sequence number is `lastConfirmed`.
5. After a 30 ms wait it runs `_handleSwitchNegotiation`. The receiver sees the request, sets the channel again, replies with a `channelSwitchAck`, and logs `Switch acknowledged, resuming from packet N+1`.
6. It records a `SwitchEvent(from, to, lastConfirmedPacket, timestamp, reason)`, logs `Resuming packet N+1` (TRANSFER), and moves the sender through `recovering` back to `transferring`.

### 6.4 Worked example: `optical-degrades`

**Initial test and selection.** A tests all three channels with 20 packets each. With every test packet arriving, the scores are:

| Term | Optical (default) | Acoustic A (9 000 / 0.03 / 80 / 0.8 / 0.88) | Vibration (default) |
|---|---|---|---|
| T | 18 000 / 25 000 = 0.720, × 0.35 = 0.2520 | 9 000 / 25 000 = 0.360, × 0.35 = 0.1260 | 800 / 25 000 = 0.032, × 0.35 = 0.0112 |
| R | 20 / 20 = 1.000, × 0.25 = 0.2500 | 1.000, × 0.25 = 0.2500 | 1.000, × 0.25 = 0.2500 |
| L | 1 − 2 / 500 = 0.996, × 0.15 = 0.1494 | 1 − 80 / 500 = 0.840, × 0.15 = 0.1260 | 1 − 120 / 500 = 0.760, × 0.15 = 0.1140 |
| C | 0.92, × 0.15 = 0.1380 | 0.80, × 0.15 = 0.1200 | 0.72, × 0.15 = 0.1080 |
| S | 0.88, × 0.10 = 0.0880 | 0.88, × 0.10 = 0.0880 | 0.68, × 0.10 = 0.0680 |
| **Score** | **0.8774** | **0.7100** | **0.5512** |

If one optical test packet is lost (19 of 20), the optical score becomes 0.849. Either way optical wins, and the log shows `[DECISION] Selected OPTICAL` with score 0.8774 and reason `Higher throughput and reliability`, because optical's measured throughput is higher than the runner-up's.

**Degradation.** The 32 packets go out in windows of 8. A-optical's send counter counts the first sends, the re-sends of the window and the retransmissions, so the 15th send happens by the second loop iteration at the latest. From then on, A-optical uses 2 000 bps, loss 0.30, 500 ms, confidence 0.3 and stability 0.2. Each delivered data packet now costs about 1.64 s. A full window of 8 costs about 9 s, because the roughly 30% of packets that are lost cost nothing.

**What the engine would decide.** Re-evaluating the degraded optical channel from its profile gives:

| Term | Value | Weighted |
|---|---|---|
| T = 2 000 / 25 000 | 0.080 | 0.0280 |
| R = 1 − 0.30 − 0.005 | 0.695 | 0.1738 |
| L = 1 − 500 / 500 | 0.000 | 0.0000 |
| C | 0.300 | 0.0450 |
| S | 0.200 | 0.0200 |
| **Current score** | | **0.2668**, below 0.65, so degraded |

The first alternative tried is acoustic. A fresh 20-packet test on acoustic A scores 0.710 with all 20 received, 0.688 with 19 and 0.666 with 18. The gap is at least 0.666 − 0.267 = 0.40, well over 0.15, so `evaluateSwitch` returns `shouldSwitch: true` with the reason `Switching OPTICAL → ACOUSTIC: 0.71 vs 0.27`. Vibration is never tested, because acoustic qualifies first.

**What actually happens.** The first re-evaluation is at loop iteration 20, and on the degraded link every iteration that sends a window takes several seconds. The loop therefore never reaches iteration 20 while data is still flowing. In one traced run:

| Time since start | Event |
|---|---|
| 1.06 s | `[DECISION] Selected OPTICAL` (score 0.8774) |
| 111.4 s | `[TRANSFER] Packet 32 acknowledged`. The sender's cumulative ACK is now 32/32, but the receiver is still missing packets 10 and 14 |
| 111.5 s | With nothing left to send, iterations take milliseconds, iteration 20 arrives, and the log shows `[WARNING] OPTICAL quality degraded (score=0.27)` and `[ADAPT] Testing ACOUSTIC channel` |
| 111.9 s | `[DECISION] Switching OPTICAL → ACOUSTIC`, `[SWITCH] Last confirmed packet = 32`, and on the receiver `Switch acknowledged, resuming from packet 33` |
| 135.2 s | The loop reaches 1500 iterations with packets 10 and 14 still missing, and the log shows `[ERROR] Transfer failed` |

The switch itself works as designed, but by then there is nothing left to send on acoustic, because the sender has already discarded packets 10 and 14 from its pending list ([quirk 4](#10-known-quirks)). All four probe runs of this scenario ended this way. The re-evaluated scores of the other scenarios' degraded profiles are:

| Degraded profile | Re-evaluated score | Degraded? | Typical alternative | Switch if evaluated? |
|---|---|---|---|---|
| `burst-loss` optical (4 000 / 0.45 / 300 / 0.92 / 0.88) | 0.478 | yes | default acoustic, about 0.69–0.71 | yes (gap about 0.22) |
| `both-degrade` optical (3 000 / 0.25 / 80 / 0.92 / 0.88) | 0.580 | yes | default acoustic, about 0.69–0.71 | no (gap below 0.15) |
| `repeated-degradation` optical (2 500 / 0.35 / 80 / 0.25 / 0.88) | 0.448 | yes | acoustic 8 000 / 0.05 / 80, about 0.71 | yes (gap about 0.26) |
| Default optical, healthy (R = 0.985) | 0.874 | no | none | no |

---

## 7. Logs, metrics and panels

### 7.1 Log entries

Each endpoint has its own `StructuredLogger`. Entries carry a category, a message, a timestamp and optional data, and each logger keeps at most 1000 entries. During a single run `AppController` subscribes to both loggers with `onLog`, so the LIVE LOGS panel shows sender and receiver entries interleaved in the order they happen. The panel draws each entry as `[CATEGORY] message` in a monospace font, with a count chip in its header.

| Category | Colour | Messages produced in a simulated run |
|---|---|---|
| `DISCOVERY` | blue | `Device discovered on <CHANNEL> channel` |
| `TEST` | blue | `<CHANNEL> throughput = x.x kbps`, `<CHANNEL> packet loss = y.y%` (initial tests and alternative tests) |
| `DECISION` | green | `Selected <CHANNEL>` (with `score` and `reason` in its data), `Switching FROM → TO` |
| `TRANSFER` | light blue | `Packet n received`, `Missing packet n detected, requesting retransmission` (receiver); `Packet n acknowledged`, `Retransmitting packet n (retry k)`, `Resuming packet n`, `Transfer complete` (sender) |
| `WARNING` | amber | `<CHANNEL> quality degraded (score=x.xx)` |
| `ADAPT` | cyan | `Testing <CHANNEL> channel` |
| `SWITCH` | purple | `Last confirmed packet = n` (sender), `Switch acknowledged, resuming from packet n` (receiver) |
| `ERROR` | red | `Max retries exceeded for packet n`, `Timeout: max retries for packet n`, `Transfer failed` |

`Packet n acknowledged` is logged only when an ACK advances the sender's `lastAckedSequence`. A discovery failure is not written to either logger. It appears only as the single string `Discovery failed` in `SimulationResult.logs`.

### 7.2 Endpoint panels

`EndpointPanel` renders a `DashboardSnapshot` built by `VirtualEndpoint.getSnapshot()`.

| Row | Source |
|---|---|
| Title and state chip | `transferStateLabel(state)`. The chip is green for COMPLETED, red for FAILED, amber for DEGRADED, SWITCHING_CHANNEL and RECOVERING, and blue otherwise |
| Channel | The endpoint's active channel, or N/A |
| Score, Confidence | `currentDecision.score` and `.confidence` from the initial selection. They are not updated after a switch |
| Throughput, Packet Loss, Latency | The active channel's `getMetrics()`, shown in kbps, % and ms. These are the configured profile values (section 4.5). Packet loss is drawn in red above 10% |
| Progress bar, Progress, Packets, Retries | `transport.getProgress(allPackets.length, dataToSend.length)`. Packets shows acknowledged / total, and Retries shows the transport's `retryCount` (NACK, retransmission-request and timeout resends; window re-sends are not counted). See [quirk 10](#10-known-quirks) for why the bar stays at 0% |
| CHANNELS | One bar per entry in `channelScores`. On the sender these start as the initial test scores and are overwritten by re-evaluation and alternative-test scores. On the receiver they stay at the initial test scores |
| SWITCH EVENTS | `FROM → TO @ pkt N` for each `SwitchEvent`. Only the sender records switch events |

In the probe runs a successful 16-packet transfer typically ended with the sender showing "Packets 8 / 16" and "Retries 16". The receiver completed even though many ACKs never reached the sender's transport ([quirk 5](#10-known-quirks)).

### 7.3 `SimulationResult`

| Field | Meaning |
|---|---|
| `success`, `dataMatch` | Both equal the verification result |
| `originalSize`, `receivedSize` | Bytes sent and bytes reassembled (0 if nothing was reassembled) |
| `switchEvents` | Number of switches the sender performed |
| `senderSnapshot`, `receiverSnapshot` | Final `DashboardSnapshot`s |
| `durationMs` | Wall-clock time of the whole run, including discovery and tests |
| `logs` | Sender entries followed by receiver entries, formatted `[CATEGORY] message` |

---

## 8. Performance Comparison

### 8.1 Strategies

`PerformanceComparator.runComparison({int dataSize = 4096})` runs three strategies one after another and returns one `StrategyResult` each. The app calls it with the default of 4096 bytes (16 packets).

| Strategy | Label | How it is built | Channel actually used in the probe runs |
|---|---|---|---|
| `TransferStrategy.adaptive` | Adaptive | `getScenario('optical-degrades')!.createPair()`, run with 4096 bytes instead of the scenario's 8192 | Optical throughout, no switch |
| `TransferStrategy.fixedOptical` | Fixed Optical | `createSimulationPair(opticalProfileA: ChannelSimulationProfile(packetLossRate: 0.08))`, so optical A is 18 000 / 0.08 / 80 / 0.92 / 0.88 / 0.005 and everything else is default | Optical |
| `TransferStrategy.fixedAcoustic` | Fixed Acoustic | `createSimulationPair` with optical A and B set to `ChannelSimulationProfile(discoverable: false)` | **Optical**, because the undiscoverable optical channel (18 000 bps, 80 ms, score about 0.85) outscores default acoustic (about 0.71) |
| `TransferStrategy.staticSwitch` | Static Switch | Present in the enum and in `strategyLabel`, but never run | none |

All three call the full `SimulationOrchestrator.runTransfer`, including discovery, score-based selection and periodic re-evaluation ([quirk 3](#10-known-quirks)).

### 8.2 Metrics

| Field | Computed as | Shown on the card as |
|---|---|---|
| `success` | `result.success` | Green tick or red error icon next to the label |
| `durationMs` | `result.durationMs` | `Duration` in ms |
| `throughput` | `senderSnapshot.metrics.throughput`, the configured `baseThroughput` of the sender's active channel at the end | `Throughput`, value ÷ 1000 with one decimal, labelled kbps |
| `goodput` | `dataSize / (durationMs / 1000)` in bytes per second if successful, otherwise 0 | `Goodput`, value ÷ 1024 with one decimal, labelled KB/s |
| `packetLoss` | `senderSnapshot.metrics.packetLoss`, the configured loss rate of the active channel | `Packet Loss`, value × 100 % |
| `retransmissions` | `senderSnapshot.progress.retryCount` | `Retransmissions` |
| `switchCount` | `result.switchEvents` for Adaptive; hard-coded `0` for both fixed strategies | `Channel Switches` |

### 8.3 Observed results

Two comparison runs on 2026-09-27 produced:

| Strategy | Success | Duration | Throughput field | Packet Loss field | Retransmissions | Switches | Goodput |
|---|---|---|---|---|---|---|---|
| Adaptive | 2 of 2 | 53.9 s, 48.5 s | 2 000 bps (degraded optical profile) | 0.30 | 17, 19 | 0, 0 | 76.0, 84.5 B/s |
| Fixed Optical | 2 of 2 | 11.9 s, 11.9 s | 18 000 bps | 0.08 | 15, 16 | 0 | 344.1, 345.2 B/s |
| Fixed Acoustic | 2 of 2 | 13.7 s, 13.6 s | 18 000 bps | 0.01 | 16, 16 | 0 | 298.9, 302.0 B/s |

One comparison takes about 75 to 80 seconds. Read the results with care. "Adaptive" is the slowest because it is the only strategy whose channel degrades, and with 16 packets it never reaches a re-evaluation. "Fixed Acoustic" actually ran on optical, which is why its throughput field shows 18 000 bps and its loss field 0.01. The comparison therefore does not currently show an adaptive advantage. See [KNOWN_ISSUES.md](../project/KNOWN_ISSUES.md).

---

## 9. Adding a scenario or a channel profile

### 9.1 Adding a scenario

1. Open `lib/core/simulation/scenarios.dart` and add a `ScenarioDefinition` to the `scenarios` list. Give it a unique kebab-case `id`, a human-readable `name`, a one-sentence `description`, a `dataSize` in bytes, and a `createPair` closure that calls `createSimulationPair(...)`.
2. Write out every field you care about in each override profile. An override replaces all seven fields with its own values, so anything you leave out becomes a constructor default (18 000 bps, 0.01, 80 ms, 0.92, 0.88, 0.005, discoverable). The same applies to the profile inside a `DegradationSchedule`.
3. Remember what `afterPacket` counts. It counts endpoint A's `send()` calls on that channel, including re-sends, retransmissions and lost packets. A schedule on a channel that never becomes active never fires, and schedules cannot be attached to endpoint B.
4. Do not rely on `discoverable: false` to keep a channel out of selection ([quirk 1](#10-known-quirks)). To make a channel lose, give it a genuinely bad profile, such as low throughput, high loss and high latency.
5. Size the data against the re-evaluation interval. A switch can only happen at loop iterations 20, 40 and so on, and the degradation must have happened by then.
6. Nothing else needs registering. The Simulation Lab drop-down reads `AppController.availableScenarios`, which returns `scenarios`, and Run All iterates the same list and uses `scenarios.length` as its denominator.
7. If the scenario should stay green, add a test to `test/simulation_integration_test.dart`. Assert `dataMatch` and give it a generous timeout, because the medium really waits for every packet's latency and air time.

This example makes optical nearly unusable, so that acoustic wins on merit, and gives acoustic its real default characteristics with 10% loss. The two constants go at the top of `scenarios.dart`, and the `ScenarioDefinition` goes inside the `scenarios` list:

```dart
const noisyAcousticProfile = ChannelSimulationProfile(
  baseThroughput: 9000,
  packetLossRate: 0.10,
  baseLatencyMs: 3,
  confidence: 0.78,
  stability: 0.72,
  corruptionRate: 0.01,
);

const unusableOpticalProfile = ChannelSimulationProfile(
  baseThroughput: 1000,
  packetLossRate: 0.40,
  baseLatencyMs: 400,
  confidence: 0.3,
  stability: 0.3,
);

ScenarioDefinition(
  id: 'acoustic-noisy',
  name: 'Acoustic Only, Noisy',
  description: 'Optical is nearly unusable; acoustic carries the transfer through 10% loss.',
  dataSize: 2048,
  createPair: () => createSimulationPair(
    opticalProfileA: unusableOpticalProfile,
    opticalProfileB: unusableOpticalProfile,
    acousticProfileA: noisyAcousticProfile,
    acousticProfileB: noisyAcousticProfile,
  ),
),
```

With these profiles, a typical optical test (12 of 20 received) scores about 0.25, acoustic with 18 of 20 received scores about 0.67, and default vibration about 0.55, so acoustic is selected. Re-evaluated from its profile, acoustic scores 0.687, which is above the 0.65 threshold, so no switch is attempted. The matching test:

```dart
test('acoustic noisy scenario completes', () async {
  final scenario = getScenario('acoustic-noisy')!;
  final orchestrator = SimulationOrchestrator(scenario.createPair());
  final result = await orchestrator.runTransfer(generateTestData(scenario.dataSize));
  expect(result.dataMatch, isTrue);
}, timeout: const Timeout(Duration(minutes: 2)));
```

Because loss is random and unseeded, run a new scenario test several times before relying on it. A 10% loss rate will sometimes leave the permanent gap described in [quirk 4](#10-known-quirks), and the test will then fail.

### 9.2 Adding or changing a channel profile

- **A reusable profile** is simply a top-level `const ChannelSimulationProfile(...)` with all fields written out, like `noisyAcousticProfile` above. Put it at the top of `scenarios.dart`, or next to the defaults in `simulated_medium.dart`, which `scenarios.dart` already imports. Pass it as the `opticalProfileA`, `acousticProfileB` or other override arguments.
- **Changing a default** (`defaultOpticalProfile`, `defaultAcousticProfile` or `defaultVibrationProfile` in `simulated_medium.dart`) affects every scenario that does not override that channel, and the Performance Comparison strategies. Scenarios that do override the channel are unaffected, because their override replaces every field.
- **A fourth channel type** is not supported by the current API. `createSimulationPair` has fixed parameters for three channels, and `CommChannelId` has only `optical`, `acoustic` and `vibration`. Adding one would need a new `CommChannelId` value, a new factory in `comm_channel.dart`, new parameters and registrations in `createSimulationPair`, and a new case in `ChannelManager.startAll`.

---

## 10. Known quirks

Each item below was confirmed in the code, and most were also seen in the probe runs. Items 1 to 4 have been reported before; the rest were found while writing this document. Wider limitations are collected in [KNOWN_ISSUES.md](../project/KNOWN_ISSUES.md).

1. **Undiscoverable channels are still tested and can be chosen.** `runTransfer` only checks that the discovery lists are not empty. `testAll(20)` then tests every registered channel, `runChannelTest` ignores `discoverable`, and the switch loop iterates `availableChannelIds`, which is every registered channel. In the probe runs `acoustic-always-good`, `acoustic-recovers`, `vibration-coupled` and "Fixed Acoustic" all transferred over optical.
2. **Override profiles replace all fields of a channel profile.** `createSimulationPair` calls `defaultXProfile.copyWith(baseThroughput: override?.baseThroughput, ...)`. A `const ChannelSimulationProfile(packetLossRate: 0.05)` carries a non-null value for every field (the constructor defaults), so every default is overwritten, including optical's 2 ms latency and all of acoustic's and vibration's characteristics. Degradation schedules behave the same way, because `merge(other)` takes every field from `other`, and recovery assigns its profile directly.
3. **The "fixed" comparison strategies still run the adaptive orchestrator.** `_runFixedOptical` and `_runFixedAcoustic` call `SimulationOrchestrator.runTransfer`, with its discovery, 20-packet tests, score-based selection and re-evaluation every 20 iterations. Nothing forces a channel, and their `switchCount` is hard-coded to 0.
4. **`ReliableTransport` treats per-packet ACKs as cumulative.** The receiver ACKs each packet individually and NACKs gaps. The sender's `_handleAck` sets `lastAckedSequence` to the ACKed sequence and removes **all** pending packets up to it. If packet k is lost and k+1 is ACKed, packet k leaves the pending list. The NACK for k then finds nothing to retransmit, and `sendNextWindow` starts after k. Once `lastAckedSequence` reaches N the loop sends nothing more, the receiver never completes, and the run fails after 1500 iterations. This is why `optical-degrades` and `burst-loss` failed in every probe run.
5. **The switch-negotiation step throws away ACKs.** `_handleSwitchNegotiation` polls both active channels with `receiveActive()`, which drains the channel's buffer, and ignores everything that is not a switch request or switch ACK. It runs right after the receiver has sent its ACKs and NACKs for the window, so many of those are discarded. Progress then relies on timeout retransmissions and on duplicate ACKs from repeated window sends. This is why retransmission counts roughly equal the packet count, and why successful runs often end with the sender showing only part of the data acknowledged.
6. **Re-evaluation starts at loop iteration 20.** `lastMonitor` starts at 0, so the first check is at `i == 20`. On a slow link one iteration takes seconds, so most transfers end, or stall, before any re-evaluation. The only switches seen in the probe runs happened after the loop had stalled because of quirk 4.
7. **Schedules exist only on endpoint A and count every A-side send.** B's media never change. The counter includes window re-sends, retransmissions and packets that are then lost, but not tests. A schedule on a channel that is never active never fires.
8. **Lost packets cost no time.** `SimulatedMedium.send` returns before the delay when a packet is lost, so a lossy channel finishes a window faster than a clean one with the same throughput.
9. **Displayed and compared metrics are configured, not measured.** `getMetrics()` returns the active profile. The panels' Throughput, Packet Loss and Latency rows, the mid-transfer re-evaluation, and the comparison's Throughput and Packet Loss fields all report the profile, not what happened on the link.
10. **The panels' progress bar does not move.** The sender's `getProgress` counts its own reassembly buffer, which stays empty, so it reads 0%. The receiver passes `allPackets.length`, which is 0 on the receiver, as the total, so it reads 0% with a total of 0 packets. Its acknowledged count only changes when a switch calls `resumeFromSequence` on it. In practice only the sender's Packets and Retries rows move during a transfer.
11. **The Score and Confidence rows are not updated after a switch.** They come from `currentDecision`, which is set only at the initial selection.
12. **Run All is silent on the Simulation Lab screen.** `runAllScenarios` sets neither `onUpdate` nor log listeners and does not touch `lastSimResult`, so the panels, the live log and the result chip do not change. Its `N/9 scenarios passed` summary goes to `AppController.statusMessage`, which this screen does not display.
13. **Randomness is unseeded.** Every `SimulatedMedium` creates its own `Random()`, so selection when scores are close, loss patterns, failures and durations all vary between runs. `vibration-coupled` fails discovery about 12% of the time.
14. **Data packets keep their original channel ID after a switch.** `createDataPackets` encodes every packet once, with the channel chosen at the start, and `sendNextWindow` sends those stored bytes. The receiver checks only the transfer ID, so this has no effect on delivery.
15. **The Adaptive strategy uses 4096 bytes, not the scenario's 8192, and `TransferStrategy.staticSwitch` is never run.**

See also [ADAPTIVE_ENGINE.md](../algorithms/ADAPTIVE_ENGINE.md) for the decision engine in isolation, [CALCULATIONS.md](../algorithms/CALCULATIONS.md) for the formulas, [TESTING.md](TESTING.md) for the test suite, [API_REFERENCE.md](API_REFERENCE.md) for class signatures, and [UI_GUIDE.md](UI_GUIDE.md) for the screens and widgets.
