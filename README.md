# aws_liveness_for_flutter

Native [Amazon Rekognition Face Liveness](https://docs.aws.amazon.com/rekognition/latest/dg/face-liveness.html)
for Flutter on iOS and Android, built on the official AWS Amplify Face Liveness SDKs.
No WebView, no Cognito required.

> **Unofficial.** Not affiliated with, endorsed or sponsored by Amazon Web Services.
> See [NOTICE](NOTICE).

## Status

Early development; not published yet. The Dart API and the Android host are
implemented; the iOS host is in progress, so on iOS `start` currently reports
`sdkUnavailable`. Real-device checks are pending. See [doc/design.md](doc/design.md).

## What your app will need

These requirements come from the underlying AWS SDKs and cannot be hidden by the plugin:

- **A backend.** Your server calls Rekognition `CreateFaceLivenessSession`, hands the
  `sessionId` to the app, and reads the verdict with `GetFaceLivenessSessionResults`.
  The confidence score is only trusted server-side; the app never decides pass/fail.
- **AWS credentials for the streaming call.** Short-lived credentials scoped to
  `rekognition:StartFaceLivenessSession`, supplied by your app. Never ship long-lived keys.
- **A supported region.** Face Liveness is not available in every AWS region
  (for example `eu-west-1` has it, `eu-central-1` does not).
- **Android:** `minSdk 24`, `compileSdk 36`, Android Gradle Plugin 8.6 or later and
  Kotlin 2.1 or later. The Amplify SDK needs core library desugaring in your app module
  (`android/app/build.gradle.kts`); `MainActivity` stays unchanged:

  ```kotlin
  android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
  dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
  ```

- **iOS:** iOS 15.0 or later, Swift Package Manager enabled, and an
  `NSCameraUsageDescription` entry in your app's `Info.plist`.

## Example

- [`examples/backend-express`](examples/backend-express) is a small TypeScript backend
  that creates sessions, vends liveness-only credentials (STS `AssumeRole`, 15 minutes)
  and decides the result with a server-side threshold. Its README has the IAM policies.
- [`example/`](example) is a Flutter app that talks to that backend. Enter the backend
  URL and token in the app, or pass them at build time:

  ```sh
  adb reverse tcp:8787 tcp:8787
  flutter run --dart-define=LIVENESS_BACKEND_URL=http://localhost:8787 \
              --dart-define=LIVENESS_BACKEND_TOKEN=<token>
  ```

Each check is billed by Rekognition (about 0.015 USD) and every attempt needs a new
session.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
