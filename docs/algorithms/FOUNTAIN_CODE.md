# The Fountain Code (LT Code)

The fountain code is the heart of both the Light and the Sound channels. It lets a sender with **no return path** deliver a file to any number of receivers that each miss different, unpredictable frames. This document explains the idea, the exact encoding rules used in `lib/core/physical/fountain/lt_codec.dart`, the proofs behind them, the decoder, a complete worked example computed with the real code, and the measured performance.

Back to the [documentation index](../README.md).

---

## Contents

1. [The problem](#1-the-problem)
2. [The idea in one picture](#2-the-idea-in-one-picture)
3. [Encoding](#3-encoding)
4. [Why these three regimes: the mathematics](#4-why-these-three-regimes-the-mathematics)
5. [Pseudo-random generator](#5-pseudo-random-generator)
6. [Decoding: incremental Gauss–Jordan over GF(2)](#6-decoding-incremental-gaussjordan-over-gf2)
7. [Measured overhead](#7-measured-overhead)
8. [Worked example with real values](#8-worked-example-with-real-values)
9. [Complexity and memory](#9-complexity-and-memory)
10. [Comparison with alternatives](#10-comparison-with-alternatives)
11. [History: why the robust soliton was replaced](#11-history-why-the-robust-soliton-was-replaced)
12. [API summary](#12-api-summary)

---

## 1. The problem

A file is split into **K blocks**. The sender shows or plays one block per frame. The receiver catches each frame with some probability q (e.g. q = 0.7 for a hand-held camera), and it can't ask for the frames it missed.

**Naïve carousel.** Send blocks 1…K, then repeat. The receiver must wait for *every specific* block, which is a coupon-collector problem. For K = 33 and q = 0.7, the expected number of full passes is

```
E[passes] = Σ_{n≥0} [ 1 − (1 − (1−q)^n)^K ]  ≈ 3.9
```

That's about **110–130 frames** for 33 blocks, and it gets worse as K grows (it scales like K·ln K / q).

**Fountain.** Every frame carries a *different random combination* of blocks. Any K frames, give or take one or two, are enough. For the same case: (33 + ≈1.6) / 0.7 ≈ **49 frames**, more than twice as fast. Missing frames never matter; only the *count* of good ones does.

---

## 2. The idea in one picture

```
 blocks:     B0      B1      B2          (K = 3)

 symbols:    s0 = B0                     ┐
             s1 = B1                     ├ systematic: the file itself, sent first
             s2 = B2                     ┘
             s3 = B1                     ┐
             s4 = B1 ⊕ B2                │ repair symbols: XOR of a pseudo-random subset,
             s5 = B0 ⊕ B1                │ computed from (sessionId, index, K) on both sides
             s6 = B0 ⊕ B2                │
             …  forever                  ┘

 receiver catches {s1, s4, s5}:
             B1            = s1
             B2 = s4 ⊕ B1  = s4 ⊕ s1
             B0 = s5 ⊕ B1  = s5 ⊕ s1          → file recovered from 3 symbols
```

⊕ is bytewise XOR. Algebraically, every symbol is a linear equation over GF(2) (the field with elements 0 and 1, where addition is XOR). The receiver solves a K-unknown linear system; it completes when it has **K linearly independent equations** (rank = K).

---

## 3. Encoding

### 3.1 Splitting

```
K        = max(1, ceil(fileLen / blockLen))
block[i] = bytes [i·blockLen, (i+1)·blockLen) of the file, the last one zero-padded
```

`fileLen` is carried in every frame header, so padding is trimmed after decoding.

### 3.2 Symbol i

```
symbol(i) = block[i]                                   if i < K      (systematic)
symbol(i) = ⊕ { block[n] : n ∈ neighbours(i) }         if i ≥ K      (repair)
```

`neighbours(sessionId, i, K)` is a pure function, so sender and receiver compute it independently and **no neighbour list is transmitted**. The frame only needs `sessionId`, `symbolIndex`, K, `blockLen` and `fileLen`.

### 3.3 The three regimes

| K | Rule | Code |
|---|---|---|
| 1 | Always {0} | `if (k == 1) return [0]` |
| 2–8 (`_cycleMaxK = 8`) | Cycle through **all 2ᴷ − 1 non-empty subsets** in a session-keyed shuffled order | `_cycledSubset` |
| 9–256 (`denseMaxK = 256`) | Uniformly random non-empty subset: each block included with p = ½ | 32 random bits per 32 blocks; redraw if empty |
| > 256 | Exactly `d = sparseDegree(K) = min(⌊K/2⌋, ⌈2·ln K⌉ + 8)` distinct random blocks | draw until the set has d members, then sort |

`sparseDegree` values: K = 257 → 20, 300 → 20, 422 → 21, 600 → 21, 1 133 → 23, 5 000 → 26.

### 3.4 Small-K cycle in detail

```
cycleLen = 2^K − 1
order    = [1, 2, …, cycleLen]                       (each number is a subset bitmask)
shuffle order with Fisher–Yates, rng seeded by mix(sessionId ^ 0x5A17C0DE, K)
repair symbol r (= i − K) uses subset order[r mod cycleLen]
bit b of the mask set → block b is a neighbour
```

**Real example** (session `0x1234ABCD`, K = 3). Repair symbols 3…9 have neighbours:

```
3:[1]   4:[1,2]   5:[0,1]   6:[0,2]   7:[0]   8:[0,1,2]   9:[2]
```

That's all 7 non-empty subsets of {0, 1, 2}, each exactly once, and symbol 10 starts the same cycle again.

And for K = 5 (cycle length 31), the first ten repair symbols:

```
5:[4]  6:[1,3]  7:[0,1,2,3]  8:[1,4]  9:[1,2]  10:[0]  11:[1,2,3]  12:[1,2,3,4]  13:[2,4]  14:[2]
```

### 3.5 Dense and sparse examples (real output)

```
K = 20,  symbol 20:  [1, 3, 4, 5, 8, 9, 10, 11, 13, 14, 18]          (11 of 20 blocks, p ≈ ½)
K = 300, symbol 300: [2, 7, 9, 38, 58, 62, 69, 73, 88, 92, 100, 149,
                      163, 170, 182, 184, 212, 218, 229, 245]         (exactly 20 = sparseDegree(300))
```

---

## 4. Why these three regimes: the mathematics

### 4.1 Small K: a guaranteed-span argument

**Claim.** For any K, any 2ᴷ⁻¹ **distinct** non-zero vectors in GF(2)ᴷ span the whole space.

**Proof.** A proper subspace has dimension at most K − 1, so it contains at most 2ᴷ⁻¹ elements, of which 2ᴷ⁻¹ − 1 are non-zero. A set of 2ᴷ⁻¹ distinct non-zero vectors therefore can't fit inside any proper subspace, so it spans GF(2)ᴷ. ∎

**Consequence.** The cycle never repeats a subset within 2ᴷ − 1 consecutive repair symbols, and the permutation is reused every cycle, so any window of up to 2ᴷ − 1 consecutive repair symbols is distinct.
- **K = 2:** any 2 consecutive repair symbols complete the file.
- **K = 3:** any **4** consecutive repair symbols complete the file, whatever else was lost. (The test checks the stronger practical statement that 5 always do.)
- **K = 8:** 128 distinct symbols is the worst-case guarantee; in practice about K + 1 suffice, as for random rows.

The small-K regime matters because most text messages and small photos have K ≤ 8, and the old code's worst failures were exactly here.

### 4.2 Dense regime: full rank with probability ≥ 1 − 2⁻ᵐ

Suppose the receiver holds s systematic symbols and K − s + m repair symbols, a total of K + m. The systematic symbols directly give s blocks. Projected onto the remaining K − s unknown blocks, each repair row is a uniformly random vector in GF(2)^(K−s), because each block is included independently with probability ½.

The K − s + m random rows fail to span GF(2)^(K−s) only if some non-zero vector v is orthogonal to all of them. For a fixed v ≠ 0, a uniform random row r has v·r = 0 with probability exactly ½, so

```
P(rank deficient) ≤ Σ_{v ≠ 0} P(v ⟂ all rows) = (2^(K−s) − 1) · 2^−(K−s+m) < 2^−m
```

| Extra symbols m | Success probability ≥ |
|---|---|
| 0 | (≈ 29% exactly, for large K) |
| 1 | 50% |
| 2 | **75%** |
| 4 | 93.8% |
| 7 | **99.2%** |
| 10 | 99.9% |

The bound holds **whatever mix** of systematic and repair symbols the camera happened to catch. (Rows are redrawn if empty; that conditioning changes these numbers negligibly.)

The classic exact result for random binary matrices gives an expected overhead of about **1.61 extra symbols**, which matches the measured means in [§7](#7-measured-overhead).

### 4.3 Sparse regime: cheap encoding without holes

Dense rows cost about K/2 block XORs per symbol, which is too slow for large K. With a fixed row weight d, the risk is a block that **no** received symbol touches, which makes decoding impossible. The chance that a given block is missed by one symbol is 1 − d/K, so after about K symbols:

```
P(block uncovered) ≈ (1 − d/K)^K ≈ e^−d
d = 2·ln K + 8     ⇒   e^−d = K^−2 · e^−8
E[uncovered blocks] = K · K^−2 · e^−8 = e^−8 / K  ≈ 0.00034 / K
```

So uncovered blocks are vanishingly rare, and the rank behaviour stays close to that of a dense matrix while each symbol touches only 20–26 blocks.

---

## 5. Pseudo-random generator

All randomness is derived deterministically and identically on phone, web (JavaScript numbers) and tests:

```
imul(a, b)   exact 32-bit multiply (web-safe: splits into 16-bit halves)
fmix32(h)    MurmurHash3 finaliser:
               h ^= h >>> 16;  h = imul(h, 0x85EBCA6B)
               h ^= h >>> 13;  h = imul(h, 0xC2B2AE35)
               h ^= h >>> 16
mix(sid, i)  = fmix32(sid ^ fmix32(i + 0x632BE5AB))
_CounterRng(seed).next32():  counter++;  return fmix32(seed + counter · 0x9E3779B9)
```

| Use | Seed |
|---|---|
| Dense / sparse row of symbol i | `mix(sessionId, i)` |
| Small-K permutation | `mix(sessionId ^ 0x5A17C0DE, K)` |

**Why counter mode.** Each symbol's randomness depends only on (sessionId, i), with no state carried from symbol to symbol. A receiver that joins mid-stream, or misses symbols, computes exactly the same neighbour sets as the sender. fmix32 has full avalanche: flipping one input bit flips each output bit with probability about ½.

`0x9E3779B9` is ⌊2³² / φ⌋ (the golden ratio), the classic Weyl-sequence increment.

---

## 6. Decoding: incremental Gauss–Jordan over GF(2)

`LtDecoder` keeps the received equations in **reduced row-echelon form**, indexed by pivot column:

- `_pivotMask[c]`: bitset (`Uint32List`) of the equation whose pivot is block c.
- `_pivotValue[c]`: the corresponding payload.
- `_pivotSet`: bitset of the columns that have pivots.

**Invariant:** every stored row has exactly one pivot bit, and no stored row contains another row's pivot bit.

### `addSymbol(index, payload)` step by step

1. **Reject** a wrong payload length (`false`). Reject a seen index (**DUP**, `duplicateSymbols++`). If already complete: **RED**.
2. **Build the mask** from `neighborsFor(sessionId, index, K)`; copy the payload.
3. **Forward reduce.** For every set bit of `mask ∧ pivotSet`, XOR in that pivot row (mask and payload). Because pivot rows contain no other pivot bits, **one pass is enough**.
4. **Dependent?** If the mask is now empty, the symbol added nothing: **RED** (`redundantSymbols++`).
5. **New pivot** p = the lowest set bit.
6. **Back-eliminate.** For every existing row containing bit p, XOR the new row in, which keeps the form fully reduced. Update each row's solved flag.
7. **Store** the row at p, set the pivot bit, count **NEW** (`newSymbols++`), return `true`.

A row whose mask has a single bit is a **solved** block (`recoveredCount`). The transfer is **complete** when `rank == K`, at which point every row is a single bit, i.e. every block is solved. `takeBytes()` concatenates the blocks and trims to `fileLen`.

**Progress** is `rank / K`, the honest measure. (A peeling decoder can sit at "0 blocks solved" while holding almost all the information it needs.)

**Optimality.** Gaussian elimination completes exactly when the received equations span GF(2)ᴷ. No decoder can finish earlier with the same symbols, so this is the best possible decoder for the code.

---

## 7. Measured overhead

From `test/lt_small_k_test.dart`, across K = 1…600 with 40% of frames lost at random:

| Statistic | Result | Test assertion |
|---|---|---|
| Mean symbols beyond K | **0 – 2.2** | < 2.5 |
| 95th percentile | ≤ 6 | ≤ 7 |
| K = 3 from 5 consecutive repair symbols | **100%** | always |
| Decoder rank equals an independent GF(2) rank computation | yes | exact match |

With no loss at all, the systematic symbols alone complete the file after exactly **K** symbols (zero overhead). That's the benefit of being systematic.

Throughput benchmark (`test/fountain_benchmark_test.dart`): a 365 KB file (K = 1 133 at 330 B) with 20% erasures decodes at **> 40 KB/s** of CPU goodput on the build host, far above the ≈2 KB/s the camera delivers.

---

## 8. Worked example with real values

Data `"ABCDEFGHI"` (9 bytes), `blockLen = 3`, so K = 3:

| Block | Bytes | Hex |
|---|---|---|
| B0 | `ABC` | 41 42 43 |
| B1 | `DEF` | 44 45 46 |
| B2 | `GHI` | 47 48 49 |

Session `0x1234ABCD`, so the repair neighbours are those from §3.4: s3 = B1, s4 = B1⊕B2, s5 = B0⊕B1, …

**The camera catches s1, s3, s4, s5** (it missed s0 and s2):

| Step | Symbol | Neighbours | Payload | After forward reduce | Outcome | Rank |
|---|---|---|---|---|---|---|
| 1 | s1 | {1} | 44 45 46 | {1} | **NEW**, pivot 1: B1 solved | 1 |
| 2 | s3 | {1} | 44 45 46 | {} (XOR row 1) | **RED**: nothing new | 1 |
| 3 | s4 | {1,2} | 44⊕47, 45⊕48, 46⊕49 = **03 0D 0F** | {2}, payload 03 0D 0F ⊕ 44 45 46 = **47 48 49** | **NEW**, pivot 2: B2 = "GHI" | 2 |
| 4 | s5 | {0,1} | 41⊕44, 42⊕45, 43⊕46 = **05 07 05** | {0}, payload 05 07 05 ⊕ 44 45 46 = **41 42 43** | **NEW**, pivot 0: B0 = "ABC" | **3 = K → complete** |

`takeBytes()` returns `ABCDEFGHI`. The HUD would show NEW 3, DUP 0, RED 1.

(With a different session, e.g. 7, the code produces s3 = B2 and s4 = B0, and catching s1, s3, s4 completes after exactly 3 symbols. Verified by running the real encoder and decoder.)

---

## 9. Complexity and memory

Let w = ⌈K/32⌉ mask words and b = blockLen / 4 payload words.

| Operation | Cost |
|---|---|
| Encode a repair symbol, dense | ≈ K/2 block XORs = O(K·b) |
| Encode a repair symbol, sparse | d ≈ 2 ln K + 8 block XORs |
| Decode one symbol | ≤ rank forward XORs + ≤ rank back-eliminations, each O(w + b), so O(K·(w + b)) |
| Decode a whole file | O(K²·(w + b)) |
| Memory | ≈ K · (4w + blockLen) bytes |

**Example**, the 136 KB video (K = 422, blockLen = 330): w = 14, b = 83, so at most 422 × 97 ≈ 41 000 word operations per symbol. That's well under a millisecond on a phone, while symbols arrive every ~150 ms. Memory ≈ 422 × (56 + 330) ≈ **163 KB**. For K = 1 133 it's about 0.5 MB.

XOR of payloads uses 32-bit word operations when the buffers are aligned.

---

## 10. Comparison with alternatives

| Scheme | Overhead | Needs return path | Join mid-stream | Complexity | Notes |
|---|---|---|---|---|---|
| Carousel (repeat blocks) | Coupon collector: ≈ ln K / q passes | No | Yes | Trivial | The old APCS1 QR; very slow at the tail |
| Carousel + ACK/NACK | Low | **Yes** | No | Moderate | Impossible for screen → camera |
| Reed-Solomon erasure code | 0 (MDS) | No | Yes | O(n²) GF(256), n ≤ 255 symbols | A fixed rate, and limited to 255 symbols per block |
| **This LT code (exact decoder)** | ≈ 1.6 symbols mean | No | Yes | O(K²) bit operations | Simple, rateless, ideal for K ≲ 2 000 |
| Classic LT + peeling | 5–20% at moderate K; bad at small K | No | Yes | O(K log K) | Replaced (see §11) |
| Raptor / RaptorQ (RFC 6330) | < 0.02 symbols mean | No | Yes | Linear | Complex to implement; overkill for K ≤ ~1 000 |

For the K values in this app (1 to about 1 000), an exact GF(2) decoder is both simpler and more efficient in symbols than peeling, at negligible CPU cost.

---

## 11. History: why the robust soliton was replaced

APCF v2 used Luby's **robust-soliton** degree distribution with a peeling decoder: the textbook LT design, tuned for very large K. At small K it failed:

- At K = 3, about **47%** of repair symbols had degree 3, the same all-blocks equation over and over.
- Only **56%** of random K + 2 symbol sets (K = 1…10) were full rank.
- A 3-block transfer completed from five distinct repair symbols only **69%** of the time.
- Users saw the HUD stuck at "1 / 3 symbols" while NEW kept climbing: symbols were arriving but adding no rank.

APCF v3 introduced the cycled/dense/sparse rules and the exact decoder, and **bumped the frame version to 3** so a v2 receiver can't misinterpret v3 symbols (their neighbour sets differ).

---

## 12. API summary

```dart
// Encoder
final enc = LtEncoder(data: envelope, blockLen: 160, sessionId: sid);
enc.K;                      // number of blocks
enc.fileLen;                // original length
Uint8List s = enc.symbolAt(i);                     // any i ≥ 0, deterministic
LtEncoder.neighborsFor(sid, i, k);                 // List<int>, ascending
LtEncoder.sparseDegree(k);                         // row weight above 256
LtEncoder.denseMaxK;                               // 256

// Decoder
final dec = LtDecoder(K: k, blockLen: 160, fileLen: len, sessionId: sid);
bool added = dec.addSymbol(i, payload);            // true if rank increased
dec.rank; dec.isComplete; dec.progress;            // progress = rank / K
dec.newSymbols; dec.duplicateSymbols; dec.redundantSymbols; dec.recoveredCount;
Uint8List? bytes = dec.takeBytes();                // non-null once complete
dec.reset();
```

Full reference: [API Reference](../development/API_REFERENCE.md).
