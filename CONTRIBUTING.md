# Contributing to APCS

Thanks for your interest in the Adaptive Physical Communication System. Bug reports, device test results, documentation fixes and code are all welcome. This page covers how to get involved. The full developer guide (code style, performance rules, wire-format changes and common recipes) is [Contributing in the documentation](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/docs/development/CONTRIBUTING.md).

By taking part, you agree to follow the [Code of Conduct](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/CODE_OF_CONDUCT.md).

## Ways to contribute

| You want to… | Do this |
|---|---|
| Report a bug | Open an issue with the **Bug report** template. Include both phones' models and OS versions, the channel and profile, and what the HUD showed. |
| Share a device test result | Open an issue with the **Device test report** template. Results from real phones are the most valuable feedback this project gets. |
| Suggest a feature | Open an issue with the **Feature request** template and describe the problem before the solution. |
| Report a security problem | **Don't open an issue.** Follow the [security policy](SECURITY.md). |
| Ask a question | Check the [FAQ](docs/getting-started/FAQ.md) and [Troubleshooting](docs/operations/TROUBLESHOOTING.md) first, then open an issue. |
| Fix documentation | Edit the Markdown file and open a pull request. If a document disagrees with the code, the code is right. |
| Change code | Read the rest of this page, then the [developer guide](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/docs/development/CONTRIBUTING.md). |

## Set up

You need Flutter 3.41 or later (Dart 3.11 or later). Full instructions for Windows, macOS and Linux are in [Installation](docs/getting-started/INSTALLATION.md).

```bash
git clone https://github.com/harsharaj-s/adaptive-physical-communication-system.git
cd adaptive-physical-communication-system
flutter pub get
flutter test
```

## Make a change

1. Create a branch from `main`, for example `feature/rugged-light-profile` or `fix/sound-sync-drift`.
2. Make your change, following the project principles below.
3. Run the checks. All three must pass:

   ```bash
   dart format lib test
   flutter analyze   # must print "No issues found!"
   flutter test      # must stay green
   ```

4. Update the documentation in the same pull request, and add a line under **Unreleased** in the [changelog](docs/project/CHANGELOG.md).
5. Open a pull request against `main` and fill in the template.

## Project principles

These rules keep the app fast and keep two phones compatible. The [developer guide](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/docs/development/CONTRIBUTING.md#1-principles) explains each one.

- **Extend, don't overwrite.** Add new modems, codecs and widgets beside the old ones behind the shared interfaces.
- **Reuse over duplication.** Extract shared code instead of copying it.
- **Physical channels only.** No network code in the data path.
- **Simulate first.** Prove every physical-layer change in a headless simulator test before trying it on phones.
- **Keep the UI smooth.** Don't block the UI thread; drop work when busy instead of queueing it.
- **Version wire formats.** Any change to a frame, envelope or packet needs a version bump and a changelog note. See [Changing a wire format](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/docs/development/CONTRIBUTING.md#6-changing-a-wire-format).

## Pull request review

- Keep each pull request to one topic, and keep refactors separate from behaviour changes.
- Say how you tested the change: which tests, and which phones for anything that touches the camera, speaker, microphone or motor.
- A maintainer reviews every pull request. Expect questions about compatibility and performance; they're the two things that are easiest to break.

## License

By contributing, you agree that your contributions are licensed under the project's [MIT License](https://github.com/harsharaj-s/adaptive-physical-communication-system/blob/main/LICENSE).
