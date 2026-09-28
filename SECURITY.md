# Security policy

This policy explains which versions receive security fixes and how to report a vulnerability privately. For what the app does and doesn't protect against (the threat model), see [Security](docs/operations/SECURITY.md) in the documentation.

## Supported versions

APCS is developed on a single branch. Security fixes go into `main` and the next release; older builds aren't patched.

| Version | Supported |
|---|---|
| `main` (latest) | Yes |
| Any earlier build | No |

Two phones must run builds from the same protocol milestone to talk to each other (see the [changelog](docs/project/CHANGELOG.md#compatibility-rule)), so updating both phones is the fix for any protocol-level issue.

## Known, by-design limitations

These are documented behaviour, not vulnerabilities, so please don't report them:

- Transfers are **not encrypted or authenticated**. Anyone who can see the screen, hear the speaker or touch the phone can receive or forge a message. CRC checks detect noise, not attackers.
- A recorded Sound transfer or a filmed Light transfer can be **replayed**.
- Light and Sound can be **jammed** locally with a bright light, noise or another QR stream.

The reasons and the options for adding encryption are in [Security §4 and §7](docs/operations/SECURITY.md#4-why-checksums-are-not-security).

## What to report

Please report anything that could harm a user or their device, for example:

- A crafted QR frame, sound burst or vibration pattern that crashes the receiver, hangs it, or makes it use unbounded memory.
- A received message that can write outside the app's own storage or the **Adaptive Comm** Gallery album.
- Any network traffic in a release build (the data path is meant to be physical only).
- A permission being used for something other than what [Permissions and Privacy](docs/operations/PERMISSIONS_AND_PRIVACY.md) describes.

## How to report a vulnerability

**Don't open a public issue for a security problem.** Instead:

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability** to open a private advisory. Only you and the maintainer can see it.
3. Include:
   - the app version (**About** dialog) and the phone model and OS version of both sender and receiver;
   - the channel (Light, Sound or Vibration) and profile;
   - steps to reproduce, and a sample file or recording if you have one;
   - the impact you expect (crash, data exposure, and so on).

If the **Report a vulnerability** button isn't available, contact the maintainer, [@harsharaj-s](https://github.com/harsharaj-s), privately through the contact details on their GitHub profile and ask for a private channel. Describe the impact, but don't send a working exploit until you have one.

## What happens next

This is a small, volunteer-maintained project, so these are goals rather than guarantees:

- You'll get an acknowledgement within **7 days**.
- The maintainer will confirm whether the issue is reproducible and agree a disclosure date with you, normally within **90 days** of the report.
- Once a fix is released, the advisory is published with credit to you, unless you ask to stay anonymous.
