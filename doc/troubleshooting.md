# Troubleshooting

Start with `LivenessError.code`, `category` and `nativeDetails`. The sections below cover
the common causes.

## `sdkUnavailable`

- **iOS with CocoaPods.** The Amplify liveness SDK ships only through Swift Package
  Manager. Run `flutter config --enable-swift-package-manager` and rebuild. `nativeDetails.code`
  is `FaceLivenessNotLinked`.
- **iOS, face detector model missing.** The SDK loads its face detection model with
  `try! FaceDetectorShortRange.Model()`, which crashes the app if
  `face_detection_short_range.mlmodelc` is not in the bundle. The plugin cannot catch that
  crash. Instead it looks for the model before showing the screen and reports
  `sdkUnavailable` (`FaceDetectorModelNotFound`) when it is missing. A normal SwiftPM build
  bundles the model; if you see this code, check that the SDK's resource bundle is copied
  into the app (custom build scripts, app thinning settings or a stripped bundle are the
  usual causes).
- **Unsupported platform.** Only Android and iOS are supported; on other platforms every
  call reports `sdkUnavailable`.

## Camera

| Code | Fix |
|---|---|
| `missingCameraUsageDescription` | Add `NSCameraUsageDescription` to `ios/Runner/Info.plist` |
| `cameraPermissionDenied` | Explain why the camera is needed, then start a new attempt |
| `cameraPermissionPermanentlyDenied` | Send the user to `AwsLiveness.openAppSettings()` |
| `cameraUnavailable` | Another app uses the camera, the device has none, or it failed; close other camera apps and retry |

## Sessions

- **Single use, about three minutes.** A session id works for one attempt and expires
  roughly three minutes after `CreateFaceLivenessSession`. Reusing one, or starting late,
  gives `sessionNotFound` or `sessionTimedOut`. Create a new session for every attempt.
- **Region mismatch.** The `region` passed to `start` must be the region your backend
  created the session in. Otherwise you get `sessionNotFound`.
- **Read results promptly.** Call `GetFaceLivenessSessionResults` right after
  `LivenessCompleted`.

## Credentials

| Code | Usual cause |
|---|---|
| `credentialsUnavailable` | Your `credentialsProvider` threw (see `error.cause`), took longer than `credentialsTimeout` (15 s by default), or returned empty or expired credentials |
| `accessDenied` | The credentials do not allow `rekognition:StartFaceLivenessSession`, or the access key is not recognized |
| `invalidSignature` | Expired credentials or a **wrong device clock**. AWS rejects signatures more than about five minutes off. Ask the user to enable automatic time. Android reconnects once and asks your provider again |

Return temporary credentials (with a session token) for every call; the plugin does not
cache them.

## Regions

Face Liveness streaming is available in these regions (checked 2026-10-15, see
[Amazon Rekognition endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/rekognition.html)):

`us-east-1`, `us-west-2`, `ap-south-1`, `ap-northeast-1`, `eu-west-1`, `sa-east-1`,
`ap-southeast-5`, `ap-southeast-7`

`AwsLiveness.knownSupportedRegions` returns the same list. Rekognition exists in more
regions (for example `eu-central-1`) but without the streaming endpoint. iOS reports
`invalidRegion` for those; on Android the result is expected to be `unknown` (not observed
yet).

## `presenterUnavailable` and `alreadyActive`

- `presenterUnavailable`: there was no foreground screen to show the check from. Start the
  check while your app is visible, not from a background task.
- `alreadyActive`: another Flutter engine in the same app already runs a check. Only one
  check runs at a time per process.
- A `StateError` from `start` means your own code started a second check before the first
  one completed. Wait for the result or call `AwsLiveness.cancel()`.

## Android build errors

| Message | Fix |
|---|---|
| `Dependency ':...' requires core library desugaring to be enabled` | Add the desugaring lines from the README to your app module |
| `aws_liveness_for_flutter needs Kotlin 2.1.0 or newer` | Raise `org.jetbrains.kotlin.android` in `android/settings.gradle(.kts)` |
| `compileSdk` or AGP version errors from `checkDebugAarMetadata` | Use `compileSdk 36` and Android Gradle Plugin 8.6 or later |

## Testing with a local backend on Android

Forward the backend port to the phone, then use `http://localhost:8787` in the example app:

```sh
adb reverse tcp:8787 tcp:8787
```

The example accepts plain `http://` only for loopback addresses in debug builds; release
builds need HTTPS.

## Still stuck?

Open an issue with the platform, plugin and Flutter versions, `error.code`,
`error.nativeDetails` and the steps to reproduce. Never paste credentials, session tokens
or face images.
