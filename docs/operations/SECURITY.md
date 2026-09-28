# Security

What the system protects against, what it does not, and how to add real protection. The short version: every check in the app detects **accidental** damage (noise, blur, echo). None of them resist a **deliberate** attacker. Treat every transfer as public.

Back to the [documentation index](../README.md).

---

## Contents

1. [Security properties at a glance](#1-security-properties-at-a-glance)
2. [Threat model](#2-threat-model)
3. [Threats and mitigations](#3-threats-and-mitigations)
4. [Why checksums are not security](#4-why-checksums-are-not-security)
5. [Input handling on the receiver](#5-input-handling-on-the-receiver)
6. [Advantages of physical channels](#6-advantages-of-physical-channels)
7. [Adding encryption](#7-adding-encryption)
8. [Guidance for users](#8-guidance-for-users)
9. [Reporting a problem](#9-reporting-a-problem)

---

## 1. Security properties at a glance

| Property | Provided? | How / why not |
|---|---|---|
| **Integrity against noise** | Yes | CRC-32 per Light frame, CRC-16 + Reed-Solomon per Sound frame, CRC-32 per packet, QR's own Reed-Solomon |
| **Integrity against an attacker** | No | CRCs are public, unkeyed functions; anyone can compute a valid one |
| **Confidentiality** | No | Payloads are sent in the clear |
| **Authenticity** (who sent it) | No | No keys, signatures or identities |
| **Replay protection** | No | A recorded Sound or filmed Light transfer can be played again |
| **Availability** | Partial | Jamming is easy (noise, a bright light, another QR stream), but it's local and obvious |
| **No remote attack surface** | Yes | No network permission in release builds, no server, no open ports |

---

## 2. Threat model

| Actor | Capability | Realistic? |
|---|---|---|
| **Bystander** | Sees the screen or hears the tones | Very: that's how the channels work |
| **Eavesdropper with equipment** | Films the screen with a zoom lens; records audio from across the room | Yes |
| **Active attacker** | Shows their own QR stream or plays their own tones near the receiver | Yes, with the app or a modified build |
| **Remote attacker** | Over the Internet | No: there is no network path |
| **Malicious file** | Crafted image or video bytes delivered through a valid transfer | Possible; handled by platform decoders ([§5](#5-input-handling-on-the-receiver)) |

---

## 3. Threats and mitigations

| Threat | Channel | Current state | Mitigation |
|---|---|---|---|
| Eavesdropping | Light, Sound | Anyone in range can decode | Shield the screen; lower the volume; move closer; [encrypt](#7-adding-encryption) |
| Unnoticed transfer | Sound (Silent) | Silent tones are inaudible to most adults, so people nearby may not notice a transfer, but any phone running the app within about half a metre can still decode it | Treat Silent as quiet, not private; it offers no confidentiality |
| Eavesdropping | Vibration | Requires touching the phones | Inherently private, but very slow |
| Spoofed message | Light, Sound | A fake stream with valid CRCs is accepted | Authenticated encryption with a shared passphrase |
| Session hijack / pollution | Light | Frames with the victim's session ID but wrong data would corrupt the decode (caught later only if the envelope magic breaks) | Keyed MAC per frame, or authenticated encryption of the envelope |
| Replay | Light, Sound | A recording decodes again | Timestamps or nonces inside an authenticated envelope |
| Jamming | Sound | Loud noise in the 1.2–7.2 kHz band stops decoding; ordinary noise barely reaches 18–20 kHz, but a deliberate high-frequency tone would jam Silent | Rugged profile, or Silent in a noisy room; move away; switch to Light |
| Jamming | Light | Another screen in view, glare | Per-session decoders (up to 3) keep going; aim carefully |
| Denial of service by memory | Light | Frames can announce large K or file lengths | The receiver keeps at most 3 sessions; K and block sizes come from a CRC-checked header. A hostile frame could still claim a large file, so a hard cap on `fileLen` would be a sensible addition |
| Malicious media | All | Received bytes go to Flutter's image decoder and the platform video player | Platform decoders are sandboxed and regularly patched; keep the OS updated |

---

## 4. Why checksums are not security

A CRC is a fixed, public polynomial function. Given any payload, anyone can compute the CRC that makes it "valid". CRCs catch random bit flips with overwhelming probability:

| Check | Undetected random error probability |
|---|---|
| CRC-16 (Sound frame, after RS repair) | about 1 in 65 536 |
| CRC-32 (Light frame, packet) | about 1 in 4.3 billion |

So they're excellent against noise and useless against intent. Security needs a **secret key**, via a MAC or authenticated encryption.

Likewise, the **session ID** (`CRC32(content) XOR blockLen·0x9E3779B1`) is an identifier, not a secret. It reveals nothing useful, but anyone who sees one frame knows it.

---

## 5. Input handling on the receiver

The receiver treats every frame as untrusted input:

- **Magic, version and CRC first.** Light frames must start with `APCF`, version 3, and pass CRC-32 before any field is used. Sound frames must pass Reed-Solomon and CRC-16.
- **Header sanity.** Block length, K and the symbol index must agree with an existing decoder, or a new decoder is created (the oldest is evicted beyond 3).
- **Envelope parsing** (`ChatPayloadCodec.decodeIncoming`) checks every length field against the remaining bytes before slicing, so a truncated or lying envelope returns `null` instead of reading out of bounds.
- **Type checks.** An image must start with a JPEG/PNG/GIF/WebP signature; a video must be at least 512 bytes.
- **Links are never opened automatically.** A received URL is only opened when the user taps it, in the external browser.
- **Files are not executed.** Received media is only displayed, played, or saved to the Gallery.

---

## 6. Advantages of physical channels

- **No remote attack surface.** There is nothing to scan, nothing listening on a port, and no server to breach.
- **Visible range.** An attacker must be physically present: in view of the screen, in earshot, or touching the phone.
- **Works in air-gapped settings.** It can move data out of or into a network-isolated machine without enabling any radio. That's useful, but it is also something administrators of air-gapped systems should know about.

---

## 7. Adding encryption

A design that fits the current architecture without changing any modem:

```
key       = Argon2id(passphrase, salt = random 16 B, memory ≥ 64 MiB)
nonce     = random 12 B (AES-GCM) or 24 B (XChaCha20-Poly1305)
sealed    = AEAD_Encrypt(key, nonce, plaintext = APCM envelope, aad = "APCE1")
envelope' = "APCE" | version 1 | salt | nonce | sealed (ciphertext + 16-byte tag)
```

- The fountain and frame layers carry `envelope'` exactly like any other bytes.
- The receiver sees the `APCE` magic, asks for the passphrase, derives the key and decrypts. A wrong passphrase or any tampering fails the tag check.
- This provides confidentiality, integrity and authenticity for everyone who knows the passphrase. For replay protection, add a timestamp inside the plaintext.
- Suitable Dart packages: `cryptography` (AES-GCM, ChaCha20-Poly1305, Argon2id).
- Overhead: 4 + 1 + 16 + 12 + 16 = **49 bytes**, which is under one extra Light symbol.

This is on the [Roadmap](../project/ROADMAP.md).

---

## 8. Guidance for users

- Don't send passwords, ID documents or anything private by Light or Sound in a public place.
- For private content, encrypt the file first (for example a password-protected archive). Vibration is harder to overhear because it needs contact, but it isn't encrypted either.
- If an unexpected message arrives, remember that anyone nearby can send one.
- Received files are saved to your Gallery automatically; delete anything you didn't want.

---

## 9. Reporting a problem

For ordinary bugs, open an issue on the project's GitHub repository with the steps to reproduce.

For anything that could hurt users (for example a crash triggered by a crafted frame), **don't open a public issue**. Report it privately through the repository's **Security** tab, as described in the [security policy](../../SECURITY.md). That policy also lists what is in scope, the by-design limitations above that don't need reporting, and the response times to expect.
