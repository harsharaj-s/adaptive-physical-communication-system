# Reed-Solomon Error Correction

The Sound channel protects every frame with a Reed-Solomon (RS) code over GF(256). RS is what turns "a few percent of bytes wrong" (normal for audio in a room) into "frame recovered exactly". This document explains the finite-field arithmetic, encoding, the decoder (syndromes → Berlekamp–Massey → Chien → Forney), errors-and-erasures decoding and the GMD retry strategy, with worked examples from the real implementation in `lib/core/physical/acoustic/reed_solomon.dart`.

Back to the [documentation index](../README.md).

---

## Contents

1. [What RS gives you](#1-what-rs-gives-you)
2. [The field GF(256)](#2-the-field-gf256)
3. [Encoding](#3-encoding)
4. [Decoding overview](#4-decoding-overview)
5. [Syndromes](#5-syndromes)
6. [Berlekamp–Massey: the error locator](#6-berlekampmassey-the-error-locator)
7. [Chien search: where the errors are](#7-chien-search-where-the-errors-are)
8. [Forney: what the errors are](#8-forney-what-the-errors-are)
9. [Errors and erasures](#9-errors-and-erasures)
10. [GMD: using the demodulator's confidence](#10-gmd-using-the-demodulators-confidence)
11. [Worked examples](#11-worked-examples)
12. [Parameters used by the Sound profiles](#12-parameters-used-by-the-sound-profiles)
13. [Safety: miscorrection and the CRC](#13-safety-miscorrection-and-the-crc)
14. [API](#14-api)

---

## 1. What RS gives you

An RS code with **P parity bytes** appended to k data bytes (codeword length n = k + P ≤ 255) can:

| Damage | Repairable when |
|---|---|
| e unknown byte errors | 2e ≤ P, i.e. e ≤ P/2 |
| f erasures (positions known to be bad) | f ≤ P |
| both | **2e + f ≤ P** |

RS is **maximum distance separable** (MDS): its minimum distance is P + 1, the best any code with P redundant symbols can achieve. It works on whole bytes, so a burst that damages 8 consecutive bits costs one byte, not eight.

---

## 2. The field GF(256)

Bytes are treated as elements of the finite field GF(2⁸), i.e. polynomials of degree < 8 over GF(2), reduced modulo the **primitive polynomial**

```
p(x) = x⁸ + x⁴ + x³ + x² + 1        (0x11D)
```

with the primitive element **α = 2** (the polynomial x).

| Operation | Implementation |
|---|---|
| Addition / subtraction | XOR (they're the same in characteristic 2) |
| Exp table | `exp[i] = αⁱ` for i = 0…254, built by repeated ×2 with reduction by 0x11D; duplicated to index 511 so `exp[log a + log b]` needs no modulo |
| Log table | `log[αⁱ] = i` |
| Multiply | `a·b = exp[log a + log b]` (0 if either is 0) |
| Divide | `a/b = exp[(log a + 255 − log b) mod 255]` |
| Power | `aⁿ = exp[(log a · n) mod 255]` |
| Inverse | `a⁻¹ = exp[255 − log a]` |

**Example:** α⁸ = x⁸, which reduces mod 0x11D to x⁴ + x³ + x² + 1 = **0x1D**. That's why the table generator XORs with 0x11D whenever a doubling overflows bit 8. With the tables, every multiply is two lookups and one addition.

---

## 3. Encoding

**Generator polynomial** with P consecutive roots α⁰ … α^(P−1):

```
g(x) = ∏_{i=0}^{P−1} (x − αⁱ)         (degree P, built once per parity size)
```

**Systematic encoding.** Treat the data as the high-order coefficients of m(x)·x^P and take the remainder by g(x):

```
c(x) = m(x)·x^P  +  ( m(x)·x^P mod g(x) )
```

The code does this by synthetic division in place (`encode`), then copies the data back in front. The codeword is **data first, then P parity bytes**, so a clean codeword needs no decoding at all: the first k bytes are the data.

Every valid codeword is a multiple of g(x), so c(αⁱ) = 0 for i = 0…P−1.

**Limits:** `maxDataLength() = 255 − P`. The codes used here are **shortened** (n = 63…99 < 255): the unused high-order data positions are implicitly zero.

---

## 4. Decoding overview

```
received r = c + e   (e = error pattern)
   │
   ├─ 1. syndromes S_i = r(αⁱ), i = 0…P−1      all zero → return data unchanged
   ├─ 2. Berlekamp–Massey → error locator Λ(z)   (with erasures: seeded by Γ(z))
   ├─ 3. Chien search → positions (root count must equal deg Λ)
   ├─ 4. Forney → magnitudes, XOR them out
   └─ 5. recompute syndromes → must all be zero, else reject
```

Position indexing: byte p of an n-byte codeword is the coefficient of x^(n−1−p), so its **locator** is X = α^(n−1−p).

---

## 5. Syndromes

```
S_i = r(αⁱ) = c(αⁱ) + e(αⁱ) = e(αⁱ) = Σ_k Y_k · X_kⁱ
```

where the sum runs over the error positions with locators X_k and magnitudes Y_k. The syndromes depend **only on the errors**, not on the data. P syndromes give P equations. With e unknown positions and e unknown magnitudes (2e unknowns), up to P/2 errors can be solved.

Implementation: `_syndromes` evaluates the codeword polynomial at α⁰…α^(P−1) by Horner's rule.

---

## 6. Berlekamp–Massey: the error locator

The **error locator polynomial** is

```
Λ(z) = ∏_k (1 − X_k z)          roots at z = X_k⁻¹
```

The syndromes satisfy a linear recurrence whose connection polynomial is Λ. Berlekamp–Massey finds the **shortest** such recurrence in O(P²):

```
Λ ← 1,  B ← 1
for i = 0 … P−1:
    B ← B·z                               (shift the fallback)
    Δ ← S_i + Σ_{j≥1} Λ_j · S_{i−j}       (discrepancy)
    if Δ ≠ 0:
        if deg B > deg Λ:  swap roles (Λ, B) ← (Δ·B, Λ/Δ)
        Λ ← Λ + Δ·B
```

After P steps, `deg Λ` is the number of errors e. The decoder **rejects** if e = 0 (the syndromes were non-zero, so something is inconsistent) or if 2e > P (too many errors).

---

## 7. Chien search: where the errors are

Evaluate Λ at every candidate position and keep the roots. The implementation reverses Λ's coefficients to get the reciprocal ∏(z − X_k), whose roots are the X_k themselves. Then it tests z = αⁱ for i = 0…n−1; a root at αⁱ means position `n − 1 − i`.

**Consistency check.** The number of roots found must equal deg Λ. If Λ has roots outside the shortened codeword, or repeated roots, the pattern is uncorrectable and the frame is rejected. This is a strong guard against miscorrection.

---

## 8. Forney: what the errors are

With the positions known, the magnitudes follow in closed form. Define the **error evaluator**

```
Ω(z) = S(z) · Λ(z)  mod z^P,        S(z) = Σ S_i zⁱ
```

Then for each error with locator X_i:

```
Y_i = Ω(X_i⁻¹) / ∏_{j≠i} (1 − X_j · X_i⁻¹)
```

The denominator is the formal derivative Λ'(X_i⁻¹) divided by X_i: for Λ(z) = ∏(1 − X_j z), every term but one vanishes at z = X_i⁻¹. Forney's numerator carries a matching factor of X_i, so the two cancel. (This is the form used in `_correct`, chosen because it's far harder to get wrong than index arithmetic on Λ'.)

Each byte is corrected with `codeword[p] ^= Y_i`. Finally the syndromes are recomputed and **must all be zero**, otherwise the result is rejected.

---

## 9. Errors and erasures

If the receiver already knows that some positions are suspect (**erasures**), their locators are known, so only their magnitudes are unknown. That's **one** unknown per erasure against **two** per unknown error.

**Implementation (`_errataPositions`).**
1. Build the erasure locator Γ(z) = ∏_{j ∈ erasures} (1 − X_j z).
2. Run Berlekamp–Massey **starting from Γ**, with the register length already at f and iterations from r = f to P − 1. The iteration only has to discover the unknown errors.
3. The final polynomial has degree e + f. Reject if 2e + f > P.
4. Chien search over all positions; the number of roots must equal the degree.
5. Forney with all errata positions (erasures and errors) together.

```
Capacity: 2e + f ≤ P
P = 24:  e = 12, f = 0  │  e = 10, f = 4  │  e = 6, f = 12  │  e = 0, f = 24
```

The test suite checks the exact boundary 2e + f = P and that **18 erasures** are repaired by a code whose errors-only limit is 10.

---

## 10. GMD: using the demodulator's confidence

The MT-FSK demodulator gives every byte a **reliability**: the smaller of its two nibble margins, where margin = 1 − second-best tone power / best tone power. Wrong bytes tend to have low reliability. Generalised minimum-distance (GMD) decoding exploits that (`AcousticFrameCodec.decode`):

```
1. plain RS decode (errors only)                       → success? parse + CRC-16
2. sort positions by reliability, ascending
3. for erased = 4, 8, 12, … while erased ≤ P − 4:      (gmdStep = 4, gmdReserve = 4)
       RS decode with the `erased` least reliable positions as erasures → parse + CRC-16
4. give up → frame rejected (the fountain code simply waits for another)
```

**Why keep 4 parity bytes in reserve.** If all P parity bytes were spent on erasures, the decoder would "correct" *any* input into some codeword, with no ability to notice failure. Keeping 4 unspent guarantees every accepted result still satisfies 4 independent checks, and the CRC-16 adds 16 bits more.

**Why it helps.** With e real errors among the f erased positions, the erased errors cost 1 each instead of 2. If the demodulator's doubts line up with its mistakes, a frame with up to about 20 wrong bytes (P = 24) can be repaired instead of 12. In the room simulator, GMD took the hardest acoustic scenario from decoding **nothing** to passing.

---

## 11. Worked examples

### 11.1 Small code: RS(9, 5) with P = 4, data "HELLO"

Produced with `ReedSolomon(4)`:

```
data      : 48 45 4C 4C 4F                ("HELLO")
codeword  : 48 45 4C 4C 4F  8E 94 59 01   (5 data + 4 parity)
```

Corrupt two bytes (position 1: `45 → BA`, position 3: `4C → 5C`):

```
received  : 48 BA 4C 5C 4F  8E 94 59 01
decode    : syndromes ≠ 0 → BM finds deg Λ = 2 → Chien finds positions {1, 3}
            → Forney finds magnitudes FF and 10 → XOR → syndromes = 0
result    : 48 45 4C 4C 4F  = "HELLO"   ✓   (2 errors = P/2, the maximum)
```

### 11.2 A real acoustic frame (Standard, P = 24)

The 99-byte codeword for the text "sos" (hex in [Data Formats §4](../architecture/DATA_FORMATS.md#4-acoustic-fountain-frame)), tested with the production `AcousticFrameCodec`:

| Damage injected | Reliability supplied? | Result |
|---|---|---|
| 12 bytes XORed with `5A` at positions 3, 10, 17, … | no | **Recovered** (e = 12 = P/2) |
| 13 bytes XORed with `33` at positions 2, 9, 16, … | no | Rejected (13 > 12) |
| The same 13 bytes, marked as least reliable | yes | **Recovered** by GMD at the first retry: 4 of the bad bytes are erased and 9 remain as unknown errors, 2·9 + 4 = 22 ≤ 24 |

---

## 12. Parameters used by the Sound profiles

| Profile | n | k = 11 + L | P | Code rate k/n | Errors only | Erasures only | GMD erasure steps |
|---|---|---|---|---|---|---|---|
| Rugged | 63 | 43 | 20 | 0.68 | 10 | 20 | 4, 8, 12, 16 |
| Safe | 83 | 59 | 24 | 0.71 | 12 | 24 | 4, 8, 12, 16, 20 |
| Standard | 99 | 75 | 24 | 0.76 | 12 | 24 | 4, 8, 12, 16, 20 |
| Fast | 99 | 75 | 24 | 0.76 | 12 | 24 | 4, 8, 12, 16, 20 |

In terms of correctable byte error rate per frame (errors only): Rugged 10/63 = 15.9%, Safe 12/83 = 14.5%, Standard and Fast 12/99 = 12.1%.

**No interleaver.** Interleaving spreads burst errors across codewords. Here each frame is a single codeword and RS already corrects any burst of up to P/2 consecutive bytes, so it adds nothing. (A 12-byte burst is tested.)

---

## 13. Safety: miscorrection and the CRC

A bounded-distance decoder facing more than P/2 errors usually *detects* failure: the locator degree is inconsistent, the root count mismatches, or the syndromes are non-zero after correction. Occasionally it lands on a *different* valid codeword. Three layers guard against accepting such output:

1. **Structural checks** in the decoder: root count = degree, and zero syndromes after correction.
2. **GMD reserve:** at least 4 parity bytes are never spent on erasures.
3. **CRC-16/CCITT-FALSE** over header + payload, plus the header's `blockLen` must match the profile.

The test suite measures the miscorrection rate of the RS layer alone at **< 5%** on heavily corrupted input. After the CRC-16, the chance of accepting a wrong frame is about that × 2⁻¹⁶, below 10⁻⁶.

---

## 14. API

```dart
final rs = ReedSolomon(24);                 // parity bytes; 0 < P < 255
rs.correctableBytes;                        // P ~/ 2 = 12
rs.maxDataLength();                         // 255 − P = 231

Uint8List cw = rs.encode(data);             // data ++ parity
Uint8List? d = rs.decode(cw);               // errors only; null if uncorrectable
Uint8List? d2 = rs.decode(cw,
    dataLength: data.length,
    erasures: [3, 17, 40]);                 // errors + erasures
```

Tests: `test/reed_solomon_test.dart`: t errors for P = 4…32, bursts, parity-region errors, the miscorrection rate, the exact 2e + f = P boundary, and 18 erasures repaired by a code limited to 10 unknown errors.
