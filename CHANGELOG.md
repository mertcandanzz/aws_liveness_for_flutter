# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Unreleased

First release. Not yet published to pub.dev.

### Added

- `AwsLiveness.start` runs an Amazon Rekognition Face Liveness check with the official AWS
  Amplify SDKs and returns `LivenessCompleted`, `LivenessCancelled` or `LivenessFailed`.
- `AwsLiveness.cancel`, `isActive`, `checkAvailability`, `getCameraPermissionStatus`,
  `requestCameraPermission`, `openAppSettings` and `knownSupportedRegions`.
- `LivenessRequest` with a `credentialsProvider` callback for temporary AWS credentials,
  challenge camera, start view, theme, attempt timeout and credentials timeout.
- 26 stable `LivenessErrorCode`s with category, retryability, recovery suggestion and
  native details.
- `LivenessTheme` with light/dark/system mode and nine colour tokens shared by both SDKs.
- Android host: a plugin-owned Compose Activity on `com.amplifyframework.ui:liveness`
  1.12.0; plugin strings in English and Turkish.
- iOS host on `amplify-ui-swift-liveness` 1.5.1 through Swift Package Manager; CocoaPods
  builds compile without the SDK and report `sdkUnavailable`.
- Example app and an Express backend example (sessions, scoped credentials, server-side
  result decision).
- Documentation: architecture, security, compatibility, platform parity, theming,
  localization, troubleshooting, manual test checklist and releasing.

### Known limitations

- The iOS host has not been built in Xcode or run on a device yet.
- No liveness check has been run on a real device or against AWS yet; see
  `doc/manual-test-checklist.md`.

[Unreleased]: https://github.com/mertcandanzz/aws_liveness_for_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mertcandanzz/aws_liveness_for_flutter/releases/tag/v0.1.0
