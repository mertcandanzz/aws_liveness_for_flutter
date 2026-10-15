# Contributing

## CI drafts and local checks

CI workflows are being prepared on the **local-only** `ci/workflows` branch. Do not push
that branch or add `.github/workflows` to `main` until the owner grants `workflow` scope.
No successful GitHub execution is claimed; iOS Xcode builds and XCTest are UNVERIFIED.
See [releasing.md](doc/releasing.md) for the separate first-publication and OIDC setup gates.

On that branch, validate workflow YAML with `actionlint` and run its small gate tests:

```sh
docker run --rm -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:latest
python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
```

The CI matrices cover Flutter 3.38.7 and stable (Dart and iOS SPM), host Kotlin 2.1.0 and
2.2.20, Node 22.13.0 and 24, and Swift 5.10 and 6.1 for the platform-free Linux checks.
The example and Cognito snippet have their own Flutter tests. Device/AWS integration
tests are separate and remain PENDING.

The Pigeon check temporarily overrides only the generator to 27.3.0, regenerates all
three outputs, formats the Dart output, then restores dependency resolution. This keeps
stable Dart from silently choosing a newer 27.x generator. For a deliberate generator
upgrade, update the script and regenerate the committed outputs together. The published
package dependency constraint is unchanged.

The Linux Swift job sets `AWS_LIVENESS_EXPECT_SDK=0` and the Docker harness forwards it to
XCTest. macOS jobs set `TEST_RUNNER_AWS_LIVENESS_EXPECT_SDK=1` for SPM and `0` for CocoaPods;
`xcodebuild` forwards the unprefixed variable to the test runner. Missing SDK assertions
must not be counted as passes.

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
- Node.js for the backend examples under `examples/`: `^22.13.0 || ^24.0.0 || >=26.0.0`, the range every locked tool supports (ESLint 10 needs 22.13+ on the 22 line; Vitest 5 skips the odd releases 23 and 25). Each project has `.nvmrc` and `engine-strict=true`.

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
