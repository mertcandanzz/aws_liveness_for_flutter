# Contributing

Thanks for helping. Bug reports, fixes and documentation improvements are welcome.

## Before you start

- For anything larger than a small fix, open an issue first so we can agree on the approach.
- Read [doc/design.md](doc/design.md): it records the API, the channel contract and the
  lifecycle rules the code must keep.
- Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Setup

- Flutter 3.38 or later (Dart 3.10).
- Android: JDK 17 and the Android SDK.
- iOS: a Mac with Xcode for builds. Without a Mac, see the Linux check below.
- Node.js 20.11 or later for the backend examples under `examples/`.

```sh
flutter pub get
cd example && flutter pub get
```

## Checks

Run what your change touches:

```sh
# Dart
dart format .
flutter analyze --fatal-infos
flutter test --coverage
dart doc --dry-run

# Android unit tests and lint (from example/android)
./gradlew :aws_liveness_for_flutter:testDebugUnitTest :aws_liveness_for_flutter:lintDebug

# Example app
cd example && flutter test && flutter build apk --debug

# Swift without a Mac (Docker): parses every iOS source, compiles and tests the
# platform-free core on Linux. It does not replace an Xcode build.
tool/ios_linux_check.sh
SWIFT_IMAGE=swift:6.1-jammy tool/ios_linux_check.sh

# Backend examples (each of backend-express, backend-lambda and cognito)
cd examples/<name> && npm ci && npm run lint && npm run typecheck && npm test
# Cognito Flutter snippet
cd examples/cognito/flutter_client && flutter pub get && flutter analyze && flutter test
```

## The channel contract

`pigeons/messages.dart` defines everything that crosses between Dart and native code. After
changing it, regenerate and format the bindings, and commit all of them:

```sh
dart run pigeon --input pigeons/messages.dart
dart format lib/src/messages.g.dart
```

Never edit `messages.g.dart`, `Messages.g.kt` or `Messages.g.swift` by hand.
`ErrorCodeMessage` must keep the same names and order as `LivenessErrorCode`; a test checks
this. New error codes are appended, never inserted or renamed.

## Code rules

- Runtime failures are `LivenessResult` values; only programming errors throw.
- Every attempt produces exactly one result. Add a test for any new way an attempt can end.
- Never log credentials, Pigeon credential messages, tokens or images.
- No `!!` in Kotlin; no force unwraps, `try!` or `fatalError` in Swift plugin code.
- Public Dart API needs doc comments (`public_member_api_docs` is on).
- Tests first for bug fixes: a failing test that shows the bug, then the fix.

## Commits and pull requests

- Small commits with [Conventional Commits](https://www.conventionalcommits.org) messages in
  English (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- Fill in the pull request template, including what you tested and on which devices.
- Add a line under `Unreleased` in `CHANGELOG.md` for user-visible changes.

By contributing you agree that your work is licensed under the Apache License 2.0.
