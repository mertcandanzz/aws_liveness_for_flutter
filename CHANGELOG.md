## 0.0.1 - Unreleased

* Initial plugin scaffold for Android and iOS (Swift Package Manager layout,
  CocoaPods fallback).
* Dart API: `AwsLiveness.start`, `cancel`, `isActive`, `checkAvailability`,
  camera permission helpers, `openAppSettings` and `knownSupportedRegions`.
* Typed results (`LivenessCompleted`, `LivenessCancelled`, `LivenessFailed`) and
  stable `LivenessErrorCode`s with category and retryability.
* Pigeon channel contract with generated Dart, Kotlin and Swift bindings. Native
  hosts are not implemented yet.
