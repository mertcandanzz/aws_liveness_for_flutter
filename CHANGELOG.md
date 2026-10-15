## 0.0.1 - Unreleased

* Initial plugin scaffold for Android and iOS (Swift Package Manager layout,
  CocoaPods fallback).
* Dart API: `AwsLiveness.start`, `cancel`, `isActive`, `checkAvailability`,
  camera permission helpers, `openAppSettings` and `knownSupportedRegions`.
* Typed results (`LivenessCompleted`, `LivenessCancelled`, `LivenessFailed`) and
  stable `LivenessErrorCode`s with category and retryability.
* Pigeon channel contract with generated Dart, Kotlin and Swift bindings.
* Android host on the Amplify Face Liveness SDK.
* iOS host on the Amplify UI Swift Face Liveness SDK (Swift Package Manager only;
  CocoaPods builds report `sdkUnavailable`). Not yet built or run on macOS.
* Example app and an Express backend example (sessions, scoped credentials,
  server-side result decision).
