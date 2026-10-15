# aws_liveness_for_flutter

Native [Amazon Rekognition Face Liveness](https://docs.aws.amazon.com/rekognition/latest/dg/face-liveness.html)
for Flutter on iOS and Android, built on the official AWS Amplify Face Liveness SDKs.
No WebView, no Cognito required.

> **Unofficial.** Not affiliated with, endorsed or sponsored by Amazon Web Services.
> See [NOTICE](NOTICE).

## Status

Early development; not published yet. The Dart API (`AwsLiveness.start`) and the
channel contract are in place, the native Android and iOS hosts are in progress, so
`start` currently reports `sdkUnavailable`. See [doc/design.md](doc/design.md).

## What your app will need

These requirements come from the underlying AWS SDKs and cannot be hidden by the plugin:

- **A backend.** Your server calls Rekognition `CreateFaceLivenessSession`, hands the
  `sessionId` to the app, and reads the verdict with `GetFaceLivenessSessionResults`.
  The confidence score is only trusted server-side; the app never decides pass/fail.
- **AWS credentials for the streaming call.** Short-lived credentials scoped to
  `rekognition:StartFaceLivenessSession`, supplied by your app. Never ship long-lived keys.
- **A supported region.** Face Liveness is not available in every AWS region
  (for example `eu-west-1` has it, `eu-central-1` does not).
- **Android:** `minSdk 24`.
- **iOS:** iOS 15.0 or later, Swift Package Manager enabled, and an
  `NSCameraUsageDescription` entry in your app's `Info.plist`.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
