## What and why

<!-- What does this pull request change, and why? Link the issue it fixes, for example "Fixes #12". -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Performance improvement
- [ ] Refactor (no behaviour change)
- [ ] Documentation only

## Compatibility

- [ ] No wire-format change. Phones on the previous build still talk to this one.
- [ ] Wire-format change. I bumped the version, the receiver rejects the old format, and the changelog says both phones need the new build. See [Changing a wire format](../docs/development/CONTRIBUTING.md#6-changing-a-wire-format).

## How I tested it

<!-- Which tests you added or ran. For camera, speaker, microphone or motor changes, list the phones (model and OS) and the result. -->

## Checklist

- [ ] `dart format lib test` applied
- [ ] `flutter analyze` prints "No issues found!"
- [ ] `flutter test` passes
- [ ] New code extends existing interfaces instead of overwriting them
- [ ] Documentation updated in this pull request (the code and the docs agree)
- [ ] Changelog entry added under **Unreleased**
