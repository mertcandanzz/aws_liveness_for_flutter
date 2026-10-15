## What and why

<!-- What does this change, and which issue does it address? -->

## How it was tested

<!-- Commands you ran and their results. Name devices and OS versions for native changes.
     Do not claim a device or Xcode test you did not run. -->

- [ ] `dart format --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos`
- [ ] `flutter test`
- [ ] Android: `testDebugUnitTest` / example build (if Android code changed)
- [ ] iOS: Xcode build and XCTest, or `tool/ios_linux_check.sh` (if Swift code changed)
- [ ] Backend example: `npm run lint && npm run typecheck && npm test` (if it changed)
- [ ] Device checks from `doc/manual-test-checklist.md` (list them)

## Checklist

- [ ] Pigeon bindings regenerated and formatted if `pigeons/messages.dart` changed
- [ ] No credentials, tokens or images logged or committed
- [ ] Public Dart API documented
- [ ] `CHANGELOG.md` updated under `Unreleased` for user-visible changes
- [ ] Docs updated (README, `doc/`) if behaviour changed
