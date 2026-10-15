# Design: aws_liveness_for_flutter

Status: accepted for 0.1.0 · Last updated: 2026-10-15

This document fixes the public Dart API, the Dart↔native channel contract
(`pigeons/messages.dart`), the native hosting model, the error model, lifecycle rules,
open technical questions, the test plan and the quality checklist.

## 1. Goals and non-goals

Goals

- Run Amazon Rekognition Face Liveness fully natively in Flutter apps, on top of the
  official AWS Amplify Face Liveness SDKs: `com.amplifyframework.ui:liveness` (Android,
  Jetpack Compose) and `amplify-ui-swift-liveness` (iOS, SwiftUI, SPM product `FaceLiveness`).
- Bring your own credentials: the app passes short-lived AWS credentials from its own
  backend through a Dart callback. No Cognito, no Amplify configuration file.
- No code changes in the host app's `MainActivity` or `AppDelegate`.
- The same Dart API and behaviour on both platforms. Any gap between the SDKs that the
  plugin cannot close is documented (§12).

Non-goals

- WebView, browser, Custom Tab or `url_launcher` in any liveness path. Never.
- Client-side liveness decisions. The plugin never returns `isLive` or a confidence score.
  The app's backend calls `GetFaceLivenessSessionResults` and applies its threshold.
- Creating sessions or vending credentials (see `examples/`).
- App-specific policy such as engine selection, fallbacks or proof tokens.

## 2. Key decisions

| # | Decision | Why | Trade-off |
|---|---|---|---|
| D1 | One non-federated plugin package | Two platforms, both maintained here, no third-party implementations expected. Federation adds a platform-interface package and lockstep releases with no user benefit. | Adding web/desktop later needs a split. Acceptable for 0.x. |
| D2 | Pigeon for the channel | About 15 message types and a 26-value error enum shared by Dart, Kotlin and Swift. Pigeon generates typed code, async host calls and an async Flutter API for credential requests. A hand-written MethodChannel would duplicate string keys in three languages. | A dev dependency and committed generated files. CI checks that the generated files are up to date. |
| D3 | Dedicated native screens | Android: a plugin-owned full-screen Compose `ComponentActivity`. iOS: a `UIHostingController` presented full screen. No PlatformView and no `FlutterFragmentActivity` requirement. | The liveness UI cannot be embedded in a widget tree. The SDK UI expects to own the screen anyway. |
| D4 | Runtime outcomes are values | `start` returns a sealed `LivenessResult`. Runtime failures become `LivenessFailed(error)` and are never thrown. | Callers switch over the result; the compiler checks exhaustiveness. |
| D5 | Misuse throws `ArgumentError`/`StateError` synchronously | Invalid input and a concurrent `start` are programming errors. In Dart those are `Error`s, which should not be caught; failing at the call site surfaces bugs during development. | Callers should not wrap `start` in a catch-all. |
| D6 | Error text lives in Dart | Native code sends only a stable code plus raw native details. `message`, `recoverySuggestion`, `category` and `isRetryable` come from one Dart table. | Native messages stay available in `nativeDetails`. |
| D7 | Credentials are kept in memory only and never logged | They cross the channel only as the reply to a native request and are converted to SDK types at once. `LivenessCredentials.toString()` is redacted. | No caching: the provider runs on every native request. |
| D8 | Region format is validated, the region list is not enforced | Face Liveness regions change over time; a hard allowlist would block new regions until a release. `AwsLiveness.knownSupportedRegions` is informational. | An unsupported region fails at runtime (§4). |

## 3. Public Dart API

`package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart` exports only the types
below. Everything else in `lib/src/` is private to the package.

```dart
final result = await AwsLiveness.start(
  LivenessRequest(
    sessionId: sessionId, // created by your backend (CreateFaceLivenessSession)
    region: 'eu-west-1',
    credentialsProvider: () async {
      final c = await backend.fetchLivenessCredentials();
      return LivenessCredentials(
        accessKeyId: c.accessKeyId,
        secretAccessKey: c.secretAccessKey,
        sessionToken: c.sessionToken,
        expiration: c.expiration,
      );
    },
    challengeOptions: const LivenessChallengeOptions(
      faceMovementCamera: LivenessCamera.front,
    ),
    timeout: const Duration(minutes: 3),
  ),
);

switch (result) {
  case LivenessCompleted():
    // Ask YOUR backend for GetFaceLivenessSessionResults now.
  case LivenessCancelled(:final reason):
    // LivenessCancelReason.user or LivenessCancelReason.app
  case LivenessFailed(:final error):
    // error.code, error.category, error.isRetryable, error.recoverySuggestion
}
```

### 3.1 Entry point

```dart
abstract final class AwsLiveness {
  static Future<LivenessResult> start(LivenessRequest request);
  static Future<void> cancel();
  static bool get isActive;
  static Future<LivenessAvailability> checkAvailability();
  static Future<CameraPermissionStatus> getCameraPermissionStatus();
  static Future<CameraPermissionStatus> requestCameraPermission();
  static Future<bool> openAppSettings();
  static const List<String> knownSupportedRegions = <String>[/* §9.8 */];
}
```

- `start` validates its input synchronously, then shows the native UI. The returned future
  completes exactly once and never completes with an error. It throws synchronously:
  - `ArgumentError` if `sessionId` is blank, if `region` does not match
    `^[a-z]{2}(-[a-z]+)+-\d+$`, or if `timeout` or `credentialsTimeout` is not positive;
  - `StateError` if an earlier `start` from this isolate has not completed (`isActive`).
- `cancel` ends the active attempt; the pending `start` completes with
  `LivenessCancelled(reason: LivenessCancelReason.app)`. It is a no-op when idle and never
  throws.
- `isActive` is true from the `start` call until its future completes.
- `checkAvailability` reports whether liveness can run in this build and on this device:
  native SDK linked, a camera present, and on iOS `NSCameraUsageDescription` set. It never
  prompts.
- `getCameraPermissionStatus` and `requestCameraPermission` are optional helpers for apps
  that show their own rationale first. `start` performs the same check and request itself.
- `openAppSettings` opens this app's system settings page (for `permanentlyDenied`). It
  returns whether the page was opened.

### 3.2 Request

```dart
typedef LivenessCredentialsProvider = Future<LivenessCredentials> Function();

final class LivenessRequest {
  const LivenessRequest({
    required this.sessionId,
    required this.region,
    required this.credentialsProvider,
    this.challengeOptions = const LivenessChallengeOptions(),
    this.showStartView = true,
    this.theme = const LivenessTheme(),
    this.timeout, // null: no plugin-side timeout
    this.credentialsTimeout = const Duration(seconds: 15),
  });
}

final class LivenessCredentials {
  const LivenessCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
  });
  @override
  String toString() => 'LivenessCredentials(<redacted>)';
}

final class LivenessChallengeOptions {
  const LivenessChallengeOptions({this.faceMovementCamera = LivenessCamera.front});
}

enum LivenessCamera { front, back }
```

- The backend chooses the challenge (`FaceMovementAndLightChallenge` or
  `FaceMovementChallenge`) through `ChallengePreferences` in `CreateFaceLivenessSession`;
  the client SDKs always offer both. `FaceMovementAndLight` always uses the front camera.
  `faceMovementCamera` only applies to `FaceMovement`. Changing the camera requires a new
  session [A2].
- Photosensitivity: `FaceMovementAndLight` flashes a sequence of colours on screen. For
  audiences at risk of photosensitive epilepsy, recommend `FaceMovement`.
- `showStartView: false` maps to the SDKs' `disableStartView: true`.
- `credentialsProvider` runs every time a native SDK asks for credentials: at least once
  per attempt, and Android may ask again after a reconnect. It must return temporary
  credentials (session token and expiration) scoped to `rekognition:StartFaceLivenessSession`.
  The plugin checks that all fields are non-empty and that `expiration` is in the future.
- If the provider throws, exceeds `credentialsTimeout`, or returns invalid credentials,
  the attempt ends with `credentialsUnavailable`. The thrown object stays in Dart: it goes
  into `LivenessError.cause`, never across the channel and never into a log.
- Sessions are single use. Create a new session for every attempt, including retries.
- `timeout` is measured from the `start` call and includes the permission prompt and the
  start view.

### 3.3 Theme

```dart
enum LivenessThemeMode { system, light, dark }

final class LivenessTheme {
  const LivenessTheme({this.mode = LivenessThemeMode.system, this.light, this.dark});
  final LivenessThemeMode mode;
  final LivenessColors? light;
  final LivenessColors? dark;
}

final class LivenessColors {
  const LivenessColors({
    this.primary, this.onPrimary, this.background, this.onBackground, this.surface,
    this.error, this.onError, this.errorContainer, this.onErrorContainer,
  }); // all Color?; null keeps the SDK default for that token
}
```

Only the nine colour tokens that exist in both SDKs are exposed: Android
`LivenessColorScheme` (a Material 3 `ColorScheme`) [A2] and iOS
`FaceLivenessDetectorTheme.Colors` [S1]. Fonts (iOS only) and shapes or typography
(Android only) are not exposed. Android has an `onSurface` token that iOS lacks; the
plugin sets it from the `onBackground` override.

### 3.4 Result and errors

```dart
sealed class LivenessResult { String get sessionId; }
final class LivenessCompleted extends LivenessResult { /* sessionId */ }
final class LivenessCancelled extends LivenessResult { final LivenessCancelReason reason; }
final class LivenessFailed extends LivenessResult { final LivenessError error; }
enum LivenessCancelReason { user, app }

final class LivenessError implements Exception {
  final LivenessErrorCode code;
  LivenessErrorCategory get category => code.category;
  bool get isRetryable => code.isRetryable;
  final String message;            // English, developer-facing
  final String recoverySuggestion; // English, developer-facing
  final LivenessNativeDetails? nativeDetails;
  final Object? cause;             // Dart-side cause, e.g. the provider's exception
}

final class LivenessNativeDetails {
  final LivenessPlatform platform;
  final String? code;    // native exception class or error case name
  final String? message; // native message, never contains credentials
}

enum LivenessPlatform { android, ios }

enum LivenessErrorCategory {
  permission, credentials, configuration, service, interrupted, device, timeout, unknown,
}
```

`LivenessErrorCode` is an enhanced enum that carries `category` and `isRetryable`, so the
table lives in one place. Code names are a public, stable contract: they are not renamed
or removed without a deprecation cycle, and new codes are appended. `isRetryable` means
that a new attempt, with a new session, may succeed without any code or configuration
change. `message` and `recoverySuggestion` are not localized because they are meant for
developers and logs; apps map `code` to their own user-facing text.

### 3.5 Availability and permission

```dart
final class LivenessAvailability {
  final bool isAvailable;
  final LivenessUnavailableReason? reason;
}
enum LivenessUnavailableReason { sdkUnavailable, noCamera, missingCameraUsageDescription }
enum CameraPermissionStatus { granted, notDetermined, denied, permanentlyDenied, restricted }
```

- `denied` (Android only): the app may ask again.
- `permanentlyDenied`: on Android the user chose "don't ask again"; on iOS any denial.
  Only `openAppSettings()` helps.
- `restricted` (iOS only): blocked by parental controls or device management.
- Android can tell "never asked" apart from "permanently denied" only after a request,
  so `getCameraPermissionStatus` may report `notDetermined` for both. On a permanently
  denied permission, `requestCameraPermission` returns `permanentlyDenied` right away
  without showing a dialog. The plugin stores no permission state on disk.

## 4. Error model

### 4.1 Codes

These are wire-compatible with `ErrorCodeMessage` in `pigeons/messages.dart`: same names,
same order.

| Code | Category | Retryable | Raised by |
|---|---|---|---|
| `cameraPermissionDenied` | permission | yes | plugin pre-check, SDK |
| `cameraPermissionPermanentlyDenied` | permission | no | plugin pre-check, SDK |
| `credentialsUnavailable` | credentials | yes | plugin: provider threw, timed out, returned invalid credentials, or the engine detached |
| `accessDenied` | credentials | no | SDK: IAM denies `StartFaceLivenessSession`, or the access key is not recognized |
| `invalidSignature` | credentials | yes | SDK: expired credentials, clock skew |
| `sessionNotFound` | configuration | yes | SDK: unknown, expired or already used session, or session from another region |
| `invalidRegion` | configuration | no | SDK (iOS) |
| `validation` | configuration | no | service `ValidationException` |
| `unsupportedChallenge` | configuration | no | SDK (Android) |
| `sdkUnavailable` | configuration | no | plugin: iOS built with CocoaPods, or an unsupported platform |
| `missingCameraUsageDescription` | configuration | no | plugin: iOS `Info.plist` lacks `NSCameraUsageDescription` |
| `throttled` | service | yes | `ThrottlingException`, `ServiceQuotaExceededException` |
| `serviceUnavailable` | service | yes | `ServiceUnavailableException` |
| `internalServerError` | service | yes | `InternalServerException` |
| `sessionInterrupted` | interrupted | yes | SDK or plugin: app backgrounded, call, connection lost, iOS rotation during the check, UI dismissed by someone else |
| `faceTooClose` | interrupted | yes | SDK (iOS countdown) |
| `multipleFaces` | interrupted | yes | SDK (iOS countdown) |
| `noFaceDetected` | interrupted | yes | SDK (iOS countdown) |
| `cameraUnavailable` | device | yes | SDK: camera busy or failed |
| `videoEncodingFailed` | device | yes | SDK (Android): encoding or muxing |
| `presenterUnavailable` | device | yes | plugin: no foreground Activity or view controller to present from |
| `alreadyActive` | device | yes | plugin: another Flutter engine in this process owns the active session |
| `timedOut` | timeout | yes | plugin: `LivenessRequest.timeout` elapsed |
| `sessionTimedOut` | timeout | yes | SDK |
| `faceFitTimedOut` | timeout | yes | SDK: the face did not fit the oval in time |
| `unknown` | unknown | yes | anything not mapped above |

### 4.2 Mapping rules (both platforms, applied in this order)

1. The SDK reports a user cancel: `LivenessCancelled(user)`.
2. A plugin-initiated end (app cancel, timeout, backgrounding, presenter loss, engine
   detach) completes first; any later SDK callback is dropped by the exactly-once guard.
3. If the credentials-failure flag is set for this attempt, the result is
   `credentialsUnavailable`, whatever the SDK reports. iOS surfaces provider errors as
   `socketClosed` and Android as a generic failure, so only the plugin knows the real cause.
4. A typed SDK error maps through the tables below.
5. Anything else: `unknown`, with native details.

### 4.3 Android (`com.amplifyframework.ui:liveness` 1.12.0)

`FaceLivenessDetectionException` is not a `Throwable`. It is an
`open class(message, recoverySuggestion, throwable)`. The mapper checks the public
subclasses with `is` first, then handles the generic cases [S2].

| Native | Dart |
|---|---|
| `UserCancelledException` | `LivenessCancelled(user)` |
| `SessionNotFoundException` | `sessionNotFound` |
| `AccessDeniedException` | `accessDenied` |
| `CameraPermissionDeniedException` | `cameraPermissionDenied`, or `cameraPermissionPermanentlyDenied` after re-reading the permission state |
| `SessionInterruptedException` | `sessionInterrupted` |
| `SessionTimedOutException` | `sessionTimedOut` |
| `UnsupportedChallengeTypeException` | `unsupportedChallenge` |
| `VideoEncodingException`, `VideoMuxingException` | `videoEncodingFailed` |
| generic, message `Face did not match oval within time limit.` (internal `FaceInOvalMatchExceededTimeLimitException`) | `faceFitTimedOut` |
| generic, `throwable` is a `PredictionsException` whose `cause` is `ValidationException` | `validation` |
| … `InternalServerException` | `internalServerError` |
| … `ThrottlingException`, `ServiceQuotaExceededException` | `throttled` |
| … `ServiceUnavailableException` | `serviceUnavailable` |
| … `InvalidSignatureException` | `invalidSignature` |
| … `UnrecognizedClientException` | `accessDenied` |
| generic, message fallback when names are obfuscated: `Failed since the user made too many requests…` / `Service is currently unavailable.` / `Invalid signature` / `Unrecognized client` | `throttled` / `serviceUnavailable` / `invalidSignature` / `accessDenied` |
| generic `The camera failed to open within the allowed time limit.` / `A <front\|back> facing camera is required but no … facing camera detected.` | `cameraUnavailable` |
| generic `Failed to initialize video components required for Liveness check.` | `videoEncodingFailed` |
| generic `Failed to start the face liveness session.` | `credentialsUnavailable` if the flag is set (rule 3), otherwise `unknown` |
| anything else | `unknown` |

The camera and video-initialisation rows were added during implementation from the SDK
sources (`LivenessCoordinator`, `ChallengeView` at `release_liveness_v1.12.0`). In code,
rule 2 comes first: a plugin-initiated end has already been delivered by `SessionRegistry`,
and `ErrorMapper.map` also returns it when one is passed in.

`nativeDetails.code` holds the exception's simple class name, plus the cause's when there
is one (for example `PredictionsException/ThrottlingException`). `nativeDetails.message`
holds the SDK message. The plugin's `consumer-rules.pro` uses `-keepnames` for
`com.amplifyframework.predictions.aws.models.liveness.**` and for the liveness exception
classes, so the class-name path still works in R8 release builds. The message path is a
second line of defence.

### 4.4 iOS (`amplify-ui-swift-liveness` 1.5.1)

| `FaceLivenessDetectionError` | Dart |
|---|---|
| 0 `unknown` | `unknown` |
| 1 `sessionNotFound` | `sessionNotFound` |
| 2 `sessionTimedOut` | `sessionTimedOut` |
| 3 `faceInOvalMatchExceededTimeLimitError` | `faceFitTimedOut` |
| 4 `accessDenied` | `accessDenied` |
| 5 `cameraPermissionDenied` | after re-reading the permission state: `cameraPermissionPermanentlyDenied` if denied or restricted, otherwise `cameraPermissionDenied` |
| 6 `userCancelled` | `LivenessCancelled(user)` |
| 7 `socketClosed` | `credentialsUnavailable` if the flag is set, otherwise `sessionInterrupted` |
| 8 `countdownFaceTooClose` | `faceTooClose` |
| 9 `countdownMultipleFaces` | `multipleFaces` |
| 10 `countdownNoFace` | `noFaceDetected` |
| 11 `invalidRegion` | `invalidRegion` |
| 12 `validation` | `validation` |
| 13 `internalServer` | `internalServerError` |
| 14 `throttling` | `throttled` |
| 15 `serviceQuotaExceeded` | `throttled` |
| 16 `serviceUnavailable` | `serviceUnavailable` |
| 17 `invalidSignature` | `invalidSignature` |
| 18 `cameraNotAvailable` | `cameraUnavailable` |
| 19 `sessionInterrupted` | `sessionInterrupted` |
| any other | `unknown` |

`nativeDetails.code` holds the case name and `nativeDetails.message` the SDK message.

### 4.5 Misuse and channel failures

- `ArgumentError` and `StateError` (§3.1) are thrown synchronously, before any native call.
- A concurrent session from another engine is not the caller's bug, so it is reported as
  `LivenessFailed(alreadyActive)`.
- `MissingPluginException` (unsupported platform or unregistered plugin) becomes
  `LivenessFailed(sdkUnavailable)`. Any other `PlatformException` becomes
  `LivenessFailed(unknown)` with its code and message in `nativeDetails`.

## 5. Channel contract (Pigeon)

- Source: `pigeons/messages.dart`.
- Generated outputs:
  - `lib/src/messages.g.dart`;
  - `android/src/main/kotlin/io/github/mertcandanzz/aws_liveness_for_flutter/Messages.g.kt`;
  - `ios/aws_liveness_for_flutter/Sources/aws_liveness_for_flutter/Messages.g.swift`.
- The generated files are committed. CI regenerates them and fails on any diff.
- `LivenessHostApi` (Dart → native): `checkAvailability`, `start` (async),
  `cancel(attemptId, reason)`, `getCameraPermissionStatus`, `requestCameraPermission`
  (async), `openAppSettings` (async).
- `LivenessFlutterApi` (native → Dart): `fetchCredentials(attemptId)` (async), returning
  `CredentialsResultMessage`. Dart never throws across the channel; failure is a value.
- `attemptId` is a Dart-generated, increasing integer per `start`:
  - native echoes it in `fetchCredentials`;
  - `cancel` targets one attempt, so a stale timer cannot cancel a newer one;
  - Dart answers credential requests for any other attempt with `staleAttempt`.
- Exactly once:
  - native completes `start` once, behind an atomic guard;
  - Dart completes the public future once, behind a `Completer` guard;
  - late native replies are ignored (§6.3).
- Credentials appear on the channel only as the reply to `fetchCredentials`. Native code
  converts them to SDK types immediately and keeps no reference after handing them over.
  Pigeon's generated Kotlin data classes and Swift structs print their fields in
  `toString`/`description`, so those objects must never be logged. Review checks every
  `Log`, `print`, `NSLog` and `os_log` call in the plugin sources.

## 6. Lifecycle rules

1. **One active session per process.** Within an isolate, a second `start` throws
   `StateError`. Across engines, a process-wide native registry with a single slot answers
   `alreadyActive`. The slot is released when the result is delivered, so a new `start`
   may begin while the old UI is still animating out. On iOS the result is delivered from
   the dismissal completion handler, so the next presentation starts cleanly.
2. **Exactly-once delivery.** Three guards: the native registry flag, the Dart completer
   and `attemptId`.
3. **Timeout.**
   - A Dart timer starts at the `start` call. When it fires, Dart calls
     `cancel(attemptId, timeout)`; native closes the UI and replies `failed(timedOut)`.
   - If native has not replied within 5 seconds, Dart completes with `timedOut` itself
     and ignores the late reply.
   - Separately, native fails a credential request with `credentialsUnavailable` after
     `credentialsTimeoutMillis` + 5 seconds without a Dart reply (for example, if the
     engine is gone).
4. **App cancel.** Same path, with reason `app`, giving `LivenessCancelled(app)`.
   - Android calls the SDK's captured `onCancel` lambda so the SDK closes the session
     properly. If the cancel slot has not been composed yet (permission prompt, early
     start), the plugin finishes the Activity directly.
   - iOS dismisses the hosting controller. If cancel arrives before presentation (for
     example during the permission prompt), the plugin completes at once and skips
     presentation.
5. **Backgrounding.** Once the native UI is visible, sending the app to the background
   ends the attempt with `sessionInterrupted` (retryable; a new session is required).
   - Android: `LivenessActivity.onStop()` when neither `isChangingConfigurations` nor
     `isFinishing` is true.
   - iOS: `UIScene.didEnterBackgroundNotification` for the presenting scene.
   - The SDKs restore screen brightness when their view goes away; the manual checklist
     verifies this.
6. **Camera permission.** The plugin checks the permission before showing the SDK UI on
   both platforms. The Android SDK does not request it and fails at once without it [S2];
   on iOS the plugin requests it first for parity. If permission is not granted, the
   plugin requests it; on denial the result is `cameraPermissionDenied` or
   `cameraPermissionPermanentlyDenied`. On iOS a missing `NSCameraUsageDescription` gives
   `missingCameraUsageDescription` before `requestAccess` is called, because that call
   would crash the app.
7. **Orientation.**
   - Android: the SDK locks portrait itself, and the Activity declares `configChanges` so
     rotation never recreates it.
   - iOS: the SDK shows `RotateDeviceView` in landscape. During a check this ends with
     `sessionInterrupted`; cancelling on that screen gives `LivenessCancelled(user)`.
   - Tablets behave the same.
8. **Android process death.** If `LivenessActivity` starts for an attempt the registry does
   not know (process death, or an attempt that already ended), it finishes immediately
   without a result: the Dart side is gone. If it is recreated (`savedInstanceState != null`)
   while the registry still holds the attempt, the Dart side is still waiting, so the attempt
   ends with `sessionInterrupted` instead of hanging; the SDK session state is lost anyway.
   `onDestroy` delivers `sessionInterrupted` for any attempt that is still open, so every
   way out of the Activity produces exactly one result.
9. **Engine detach.** The owning engine's attempt is cancelled, its UI closed and its
   result dropped. Pending credential requests fail.
10. **No foreground UI.** If Android has no attached Activity, or iOS finds no view
    controller in a foreground-active scene, the result is `presenterUnavailable`.
11. **Camera interruptions.** If another app takes the camera, or a call arrives, the
    result is `cameraUnavailable` or `sessionInterrupted`. Both are retryable.

## 7. Android host

Package `io.github.mertcandanzz.aws_liveness_for_flutter`, under `android/src/main/kotlin/…`:

- `AwsLivenessForFlutterPlugin.kt`: `FlutterPlugin` and `ActivityAware`. Sets up the host
  API and the Flutter API, tracks the current Activity, owns an engine token.
- `LivenessHostApiImpl.kt`: every entry point is wrapped in `try`/`catch` and turned into
  a typed failure. Catches `ActivityNotFoundException` and `IllegalStateException`.
- `SessionRegistry.kt`: process-wide single slot, an `AtomicBoolean` completion guard,
  delivery on the main thread.
- `LivenessActivity.kt`:
  - a `ComponentActivity` with `enableEdgeToEdge()`; requests the camera permission with
    the Activity Result API before composing;
  - composes `MaterialTheme(colorScheme) { FaceLivenessDetector(..., cancelButton = { onCancel -> /* capture */ LivenessCancelButton(onCancel) }) }`;
  - a `BackHandler` calls the captured `onCancel`;
  - the SDK composes the `cancelButton` slot only while the challenge runs. During the start
    view and the connecting phase the plugin draws the same cancel button itself, which ends
    the attempt with `LivenessCancelled(user)`;
  - the Intent carries only a process-unique attempt token; the request stays in memory;
  - implements the `onStop` and `onDestroy` rules from §6.
- `CameraPermissionActivity.kt`: translucent, with no UI. Used only by
  `requestCameraPermission()`, so the host never has to forward permission results.
- `CameraPermission.kt`: status logic (§3.5), with no persistence.
- `PluginCredentialsProvider.kt`:
  - implements `AWSCredentialsProvider<AWSCredentials>`;
  - calls `fetchCredentials` on the main thread and applies the guard timeout;
  - sets the credentials-failure flag;
  - builds the credentials with `AWSCredentials.createAWSCredentials(...)` and fails if
    the result is not `AWSTemporaryCredentials`.
- `ErrorMapper.kt`: a pure function, tested on the JVM.
- `ThemeMapper.kt`: `LivenessColorScheme` defaults for the resolved light/dark mode, with
  the overrides applied.
- `res/values/strings.xml` and `res/values-tr/strings.xml`: the plugin's own strings,
  prefixed with `aws_liveness_` (cancel label and its content description).
- Manifest:
  - `android.permission.CAMERA`;
  - `<uses-feature android:name="android.hardware.camera" android:required="false"/>` and
    the same for `android.hardware.camera.front`. Without these, the CAMERA permission
    implies a required camera and Google Play filters the host app;
  - `android.hardware.camera.any` with `required="false"` and
    `tools:replace="android:required"`: `liveness` 1.12.0 declares it without `required`
    (meaning true), and the merger keeps true over false. The example app's
    `verify<Variant>CameraFeatures` task fails the build if the merged manifest requires any
    `android.hardware.camera*` feature (`aapt2 dump badging` on the release APK shows all
    three as `uses-feature-not-required`);
  - both activities `exported="false"` and `excludeFromRecents="true"`;
  - `configChanges="orientation|screenSize|screenLayout|smallestScreenSize|keyboard|keyboardHidden|navigation|uiMode|density|fontScale|locale|layoutDirection"`;
  - a no-action-bar theme.
- Gradle:
  - Compose as described in §9.1, with `buildFeatures.compose`;
  - dependencies: `com.amplifyframework.ui:liveness:1.12.0` (a normal version, not a
    strict pin), `androidx.activity:activity-compose`, `material3` through the BOM;
  - `consumer-rules.pro` with the `-keepnames` rules from §4.3.
- Rules: no `!!` in plugin code, no blocking on the main thread, no StrictMode violations.

## 8. iOS host

Under `ios/aws_liveness_for_flutter/Sources/aws_liveness_for_flutter/`. The SDK symbols the
plugin uses, with their sources, are listed in `doc/ios-sdk-surface.md`.

Status (2026-10-15): implemented, **not compiled against UIKit, Flutter or FaceLiveness
yet**. No macOS host was available. `tool/ios_linux_check.sh` parses every file with
`swiftc -parse` and compiles and unit-tests the platform-free part in the Swift Linux image
(Swift 5.10 and 6.1). The iOS build and XCTest run in the `ios-spm` and `ios-cocoapods` CI
jobs.

Layering: the platform-free core is testable with fakes and the adapters are thin.

- Core (Foundation only; also compiled on Linux):
  - `LivenessHost.swift`: the host for one engine. It runs the availability and slot
    checks, the camera pre-check, presentation and cancel. UIKit, AVFoundation and
    FaceLiveness reach it through `CameraAccess`, `LivenessPresenting` and
    `SettingsOpening`.
  - `SessionCoordinator.swift`: a `@MainActor` process-wide single slot (`ActiveAttempt`)
    with an exactly-once `finish(_:with:)`.
    - When the UI is shown, the result is delivered from the dismissal completion, so the
      next presentation starts cleanly. `dismissalGrace` (3 s) bounds that wait.
    - `end(_:with:)` records the plugin-initiated end (rule 2).
    - `detach(engine:)` drops an attempt without a result.
    - End handlers fail pending credential requests at once.
  - `CredentialsBroker.swift`:
    - bridges `fetchCredentials(attemptId)` to `async` with a checked continuation;
    - fails after `credentialsTimeoutMillis` + 5 s and as soon as the attempt ends;
    - sets the credentials-failure flag;
    - converts the reply into `PluginTemporaryCredentials`, whose description, debug
      description and mirror are all redacted.
  - `ErrorMapper.swift`: a pure function on the SDK error code (§4.2 rule order, §4.4
    table).
  - `CameraPermission.swift` (status table §3.5, pre-check §6.6), `Presenter.swift` (the
    topmost-controller walk), `ThemeMapper.swift` (`ArgbColor`), `LivenessSDK.swift`,
    `Outcomes.swift` and `MainThread.swift`.
- Adapters:
  - `AwsLivenessForFlutterPlugin.swift`:
    - one instance per engine;
    - sets up the host API and the Flutter API;
    - `registrar.publish(plugin)`, so the engine calls `detachFromEngine(for:)`, which
      tears down the channel and drops the engine's attempt;
    - no `addApplicationDelegate`: the plugin needs no app delegate callbacks.
  - `LivenessHostApiImpl.swift`: Pigeon handlers run on the platform (main) thread and
    enter the main actor with `MainActor.assumeIsolated`. Every reply is a value.
  - `SystemServices.swift`: AVFoundation camera access, the Settings app, and
    `LivenessHost.system(...)`.
  - `Presenter.swift` (UIKit part):
    - `registrar.viewController` [F4] when its window is in a foreground scene, then its
      topmost presented controller, skipping one that is being dismissed;
    - otherwise the key window of a foreground `UIWindowScene` from
      `UIApplication.shared.connectedScenes`;
    - never `UIApplication.keyWindow` or the app delegate's `window`;
    - "foreground" includes `foregroundInactive`: the scene is briefly inactive right
      after the camera prompt closes.
  - `LivenessViewController.swift` (inside `#if canImport(FaceLiveness)`):
    - `SystemLivenessPresenter` looks the presenter up before it creates
      `FaceLivenessDetectorView(sessionID:credentialsProvider:region:disableStartView:challengeOptions:isPresented:onCompletion:)`,
      because the view's initialiser already starts the session;
    - `isPresented` is `.constant(true)`. The plugin closes the UI itself, and real state
      would re-run the initialiser, which starts a new session;
    - the detector view is created once and stored in `LivenessContainer`, with
      `.faceLivenessDetectorTheme(_:)`;
    - `onCompletion` may arrive on a background queue and is moved to the main thread;
    - `LivenessViewController` is a `UIHostingController` with `.fullScreen` and
      `overrideUserInterfaceStyle` for forced theme modes. While visible, it reports
      `sessionInterrupted` on `UIScene.didEnterBackgroundNotification` (its own scene),
      `UIApplication.didEnterBackgroundNotification`, or a `viewDidDisappear` the plugin
      did not cause;
    - a close requested during the presentation animation waits for `viewDidAppear`.
      Dismissal goes through the presenting controller, so it also removes anything the
      SDK presented on top (its camera alert);
    - if UIKit refuses the presentation (`presentingViewController` stays nil), the
      result is `presenterUnavailable` instead of a hang;
    - `PluginCredentialsProvider` conforms to `AWSCredentialsProvider` and holds no
      credentials;
    - `SdkError(FaceLivenessDetectionError)`: the SDK's `code` is internal, so the plugin
      compares against the 20 public static cases (equality is by code).
- Camera pre-check (§6.6) on iOS:
  - `NSCameraUsageDescription` missing or blank: `missingCameraUsageDescription`, and
    `requestAccess` is never called;
  - `notDetermined`: the plugin prompts first;
  - a denial (now or earlier) or `restricted`: `cameraPermissionPermanentlyDenied`,
    because iOS cannot prompt again;
  - no video device (the simulator): `cameraUnavailable` (`NoVideoDevice`) before any UI;
  - `requestCameraPermission()` without a usage description returns the current status
    without prompting.
- Without `FaceLiveness` (CocoaPods builds):
  - `checkAvailability` returns `sdkUnavailable` and `start` returns
    `LivenessFailed(sdkUnavailable)` with `nativeDetails.code` `FaceLivenessNotLinked`;
  - the permission helpers still work.
- `Package.swift`: `.package(url: "https://github.com/aws-amplify/amplify-ui-swift-liveness", from: "1.5.1")`
  and the target dependency `.product(name: "FaceLiveness", package: "amplify-ui-swift-liveness")`.
  It pulls in `amplify-swift` from 2.60.2.
- Podspec: unchanged, because `FaceLiveness` is not on CocoaPods. A CocoaPods app needs
  `platform :ios, '15.0'` in its Podfile.
- `PrivacyInfo.xcprivacy`: unchanged and accurate for the plugin's own code. The plugin
  collects nothing, tracks nothing and uses no required-reason API. Video goes to AWS
  through the SDK, which the app declares.
- Known SDK hazard: `FaceLivenessDetectorView.init` calls `try! FaceDetectorShortRange.Model()`.
  That loads `face_detection_short_range.mlmodelc` from the SDK's `Bundle.module` and
  crashes if the model is missing; the plugin cannot catch it. Mitigation:
  - before creating the view, the plugin searches the app bundle (four levels deep,
    skipping `flutter_assets`) for the model;
  - if the model is absent, `checkAvailability` reports `sdkUnavailable` and `start`
    fails with `sdkUnavailable` (`FaceDetectorModelNotFound`) instead of crashing;
  - the search runs once, on first use, never at launch;
  - pending: confirm on the CI simulator build that a normal SwiftPM build passes this
    check.

## 9. Resolved and open questions

### 9.1 Compose compiler: decided, verified locally; CI matrix pending

- Since Kotlin 2.0 the Compose compiler ships with Kotlin, as the Gradle plugin
  `org.jetbrains.kotlin.plugin.compose`, versioned with Kotlin [K1].
- In a Flutter app, the host's `settings.gradle(.kts)` loads the Kotlin Gradle plugin;
  plugin subprojects resolve their buildscript classpath on a child class loader.
- Decision: the plugin's `android/build.gradle` puts
  `org.jetbrains.kotlin:compose-compiler-gradle-plugin` on its own buildscript classpath
  and applies `org.jetbrains.kotlin.plugin.compose`. The host needs no change. An existing
  Flutter liveness plugin does the same at a pinned Kotlin version [P2].
- The Kotlin Gradle plugin is expected to resolve the compiler-plugin artifact for the
  Kotlin version actually compiling; the CI matrix confirms this.
- A fail-fast check throws a `GradleException` with an actionable message when the host's
  Kotlin Gradle plugin is older than 2.1.0.
- Rejected:
  - (a) requiring every host to add the plugin in `settings.gradle(.kts)`. Kept as a
    documented fallback if the matrix finds an incompatible Kotlin version;
  - a prebuilt AAR without the compiler. It would complicate publishing; revisit only if
    the decision above fails.
- Minimum host Kotlin: 2.1.0. The Amplify artifacts depend on `kotlin-stdlib` 2.2.0 [M1],
  and the Kotlin compiler reads metadata at most one version ahead. Tested baseline:
  2.2.20 (the Flutter 3.38 template).
- Implementation finding: both buildscript artifacts must use the host's version. With
  `kotlin-gradle-plugin` pinned at 2.2.20, its BOM upgraded the Compose plugin to 2.2.20
  under a host on 2.1.0, and compilation failed with "Multiple values are not allowed for
  plugin option androidx.compose.compiler.plugins.kotlin:sourceInformation". The plugin
  therefore reads the host's Kotlin Gradle plugin version (`project.properties` in the jar
  that provides `KotlinAndroidPluginWrapper` on the parent class loader) and requests that
  version for both artifacts. It falls back to 2.2.20 when the host loads no Kotlin plugin.
- Local evidence (2026-10-15, Windows, Flutter 3.38.7, AGP 8.11.1, Gradle 8.14; the example's
  `org.jetbrains.kotlin.android` version switched temporarily and reverted):

  | Host Kotlin | Result |
  |---|---|
  | 2.0.21 | fails fast: "aws_liveness_for_flutter needs Kotlin 2.1.0 or newer, but the app uses Kotlin 2.0.21. …" |
  | 2.1.0 | `flutter build apk --debug` passes |
  | 2.2.20 (template) | debug APK and R8 release APK (`flutter build apk --release`) pass |
  | 2.3.0 | debug APK passes. The Flutter 3.38 app template itself fails on 2.3 (`kotlinOptions.jvmTarget` is an error); the test moved the example app to `compilerOptions` temporarily. That is a host-template issue, not a plugin one |

- Still required: the CI Android job repeats this matrix.

### 9.2 AAR minimums: measured

Measured on 2026-10-15 with `:app:checkDebugAarMetadata` and the `aar-metadata.properties`
of all 247 artifacts on the example's `releaseRuntimeClasspath`:

- `minCompileSdk`: 36 at most (`com.squareup.okhttp3:okhttp-android` 5.4.0, pulled in by
  Amplify). Flutter 3.38's default `flutter.compileSdkVersion` is 36, so template apps
  already comply.
- `minAndroidGradlePluginVersion`: 8.6.0 at most (`androidx.core` 1.16.0, Compose UI 1.10.5,
  `androidx.transition` 1.6.0).
- `coreLibraryDesugaringEnabled=true`, `desugar_jdk_libs` ≥ 1.2.0: `com.amplifyframework`
  `core`, `common-core`, `aws-core` and `aws-predictions` 2.41.0. Without it the app fails
  `checkDebugAarMetadata`. **Host requirement** (app module only, no `MainActivity` change),
  configured in the example app:

  ```kotlin
  android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
  dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
  ```

- `minSdk`: 24, the same as `liveness` 1.12.0.

### 9.3 Running without `Amplify.configure()` on Android: source-checked, device check pending

- Source evidence: with a non-null `credentialsProvider`, `AWSPredictionsPlugin
  .startFaceLivenessSession` converts it with `convertToSdkCredentialsProvider` and never
  creates the Cognito provider. The remaining `Amplify.*` uses in the liveness path are
  `Amplify.Logging` loggers, which work without configuration.
- The credentials provider is resolved on `Dispatchers.Main` and again on the clock-skew
  reconnect (`LivenessWebSocket.start`), which matches §6.3.
- Pending: a real session on a device (needs P5 `backend-express`).

### 9.4 R8 release build and error mapping: build verified, device check pending

- `flutter build apk --release` (R8 on) passes with the plugin's `consumer-rules.pro`; no
  extra `-dontwarn` rules were needed.
- `mapping.txt` keeps the names that `ErrorMapper` reads: `FaceLivenessDetectionException`
  and all its nested classes (including the internal
  `FaceInOvalMatchExceededTimeLimitException`), `PredictionsException`, and
  `com.amplifyframework.predictions.aws.models.liveness.*` (for example
  `ThrottlingException`, `ValidationException`, `InvalidSignatureException`).
- Pending: error mapping observed on a device in a release build.

### 9.5 FlutterFramework SPM dependency: decided for 0.1.0, not declared

- The generated `FlutterFramework` placeholder package reached Flutter master in January
  2026 (flutter/flutter#181578, after #178931), which is after 3.38 [F2]. On 3.38,
  `path: "../FlutterFramework"` would point at a package that is never generated.
- Flutter 3.44 enables SPM by default [F1] and prints a warning, not an error, for plugins
  that lack the dependency [F3].
- The minimum Flutter version stays 3.38, which has the registrar APIs needed for UIScene
  [F4].
- Evidence required: CI `ios-spm` on 3.38.x and on current stable, plus `ios-cocoapods`.
- Revisit when the minimum Flutter version reaches the first stable release that
  generates the placeholder.

### 9.6 UIScene presenter: decided (§8)

### 9.7 Theming, localization and cancel parity: decided

- Theme: the nine shared colour tokens plus the mode (§3.3).
- SDK strings:
  - Android: the app's `res/values-<lang>/strings.xml` entries with the SDK's keys
    override the library resources [A2];
  - iOS: the SDK looks up each key in the app's main bundle first, then falls back to its
    own bundle [S1].
- Plugin strings: the Android cancel label and its content description ship in en and tr
  and can be overridden with the same keys. On iOS the plugin has no visible strings,
  because the SDK draws its own close button.
- Correction (P4): amplify-ui-swift-liveness 1.5.1 does have a cancel slot
  (`.cancelButton { configuration in ... }` and `.hidesCancelButton(_:)`). The plugin keeps
  the SDK's default close button on iOS, so the decision below is unchanged; the slot is
  an option if parity of the cancel control is needed later.
- Key lists go into `doc/localization.md`.
- Cancel:
  - both platforms show a cancel control. Android uses the plugin's button in the SDK's
    `cancelButton` slot plus the system back button; iOS uses the SDK's close button;
  - both support `cancel()`;
  - the control's look is not configurable from Dart, because iOS has no slot for it.

### 9.8 Supported regions: decided, informational

- Rekognition streaming endpoints exist in us-east-1, us-west-2, ap-south-1,
  ap-northeast-1, eu-west-1, sa-east-1, ap-southeast-5 and ap-southeast-7. The Face
  Liveness quota table on the same page lists the same eight [R1].
- eu-central-1 has Rekognition but no streaming endpoint.
- `knownSupportedRegions` mirrors this list as of 2026-10-15.

### 9.9 Package name and CI token scope

- The name `aws_liveness_for_flutter` is free on pub.dev.
- The GitHub token lacks the `workflow` scope. The repository owner must run
  `gh auth refresh -s workflow` before CI files can be pushed.

## 10. Prior art

- `face_liveness_detector` (MIT, 0.2.11, unverified uploader) [P1]. It requires
  `amplifyconfiguration.json`, Amplify Auth, a `MainActivity` that extends
  `FlutterFragmentActivity`, and Podfile changes. This plugin avoids all of these.
- The Android build of a related plugin [P2] applies the Compose compiler Gradle plugin
  from its own buildscript. It also pulls in `aws-auth-cognito`, `aws-api`,
  `aws-android-sdk-core` and `appcompat`. Adopted: the Compose approach. Avoided: the
  extra dependencies.
- `crokta_liveness` aggregates `face_liveness_detector` and `amplify_flutter`. It is not a
  suitable base.
- AWS has no official Flutter support (aws-amplify/amplify-flutter#6556).

## 11. Test plan

1. **Dart unit tests** (`test/`; at least 95% line coverage of `lib/src`, excluding
   `messages.g.dart`):
   - `ArgumentError` cases;
   - `StateError` on a concurrent `start`, and `isActive` transitions;
   - exactly-once: duplicate and late native replies are ignored;
   - timeout with `fake_async`: the `timeout` cancel reason, and the 5-second grace
     fallback;
   - app cancel;
   - credentials: success, provider throws, provider times out, invalid, expired, stale
     attempt;
   - `LivenessCredentials.toString()` is redacted;
   - error table: `ErrorCodeMessage` and `LivenessErrorCode` have the same names in the
     same order, and every code has a non-empty message and recovery suggestion;
   - a snapshot of each code's category and `isRetryable`;
   - theme serialization to ARGB;
   - mapping of availability and permission statuses;
   - `MissingPluginException` maps to `sdkUnavailable`, other `PlatformException`s to
     `unknown`.
2. **Kotlin JVM tests** (`android/src/test/kotlin`):
   - every branch of `ErrorMapper`, including the message fallback and the credentials
     precedence rule;
   - `SessionRegistry` exactly-once under concurrent completion, `alreadyActive`, engine
     detach;
   - the `CameraPermission` status table;
   - `ThemeMapper`;
   - credentials conversion and timeout.
3. **Swift XCTest** (`example/ios/RunnerTests`, 46 tests; also run on Linux by
   `tool/ios_linux_check.sh`):
   - `ErrorMapper` for codes 0–19, unknown codes, and the user-cancel, credentials and
     plugin-end precedence rules;
   - `SessionCoordinator`: exactly-once delivery, delivery after dismissal and the grace
     fallback, `alreadyActive`, engine detach, lookup scoping;
   - `CredentialsBroker`: success, failure values, invalid or expired credentials, channel
     error, timeout at `credentialsTimeoutMillis` + 5 s, attempt end, redaction;
   - `CameraPermission`: the status table, and that a missing usage description never
     prompts;
   - `LivenessHost` with fakes: availability reasons, `sdkUnavailable` (CocoaPods),
     permission paths, cancel during the prompt, timeout, presenter loss, credentials
     precedence, interruption, dispose;
   - `Presenter` on a fake view-controller tree, ARGB conversion, the model lookup;
   - the CI jobs set `TEST_RUNNER_AWS_LIVENESS_EXPECT_SDK` (`1` for SPM, `0` for
     CocoaPods) and a test checks that the build matches.
4. **Integration tests** (`example/integration_test`, real device; sessions come from
   `examples/backend-express`):
   - `checkAvailability`;
   - revoked camera permission gives `cameraPermissionDenied` or
     `cameraPermissionPermanentlyDenied`;
   - an invalid session gives `sessionNotFound`;
   - invalid or expired credentials give `accessDenied` or `invalidSignature`;
   - a throwing provider gives `credentialsUnavailable`;
   - `cancel()` gives `LivenessCancelled(app)`;
   - an elapsed timeout gives `timedOut`.
5. **Manual checklist** (`doc/manual-test-checklist.md`; Android device; iOS device runs
   are pending because no iOS device is available):
   - a successful check with a real face;
   - rotation before and during the check;
   - backgrounding during the check;
   - camera taken by another app;
   - airplane mode during the check;
   - dark and light theme, large font, TalkBack, tr and en;
   - FaceMovement with the front and the back camera;
   - an R8 release build.
6. **CI jobs:**
   - `dart`;
   - `android`: debug APK, R8 release APK, Gradle unit tests, the Kotlin matrix;
   - `ios-spm`: Flutter 3.38.x and stable;
   - `ios-cocoapods`;
   - `backends`;
   - a check that the Pigeon output is up to date.

## 12. Known platform differences

These go into `doc/platform-parity.md`.

- **Cancel control:** on Android it is the plugin's own button and can be localized; on
  iOS it is the SDK's close button.
- **iOS-only codes:** `faceTooClose`, `multipleFaces` and `noFaceDetected`. Android shows
  these situations as on-screen hints instead.
- **Android-only codes:** `unsupportedChallenge` and `videoEncodingFailed`.
- **Region errors:** iOS reports `invalidRegion`. Android's behaviour for an unsupported
  region is checked on a device; until then it is expected to map to `unknown`.
- **Orientation:** Android locks portrait; iOS shows a rotate prompt.
- **Permission statuses:** `denied` exists only on Android, `restricted` only on iOS.
- **Permission errors:** iOS cannot prompt twice, so a denial in `start` is always
  `cameraPermissionPermanentlyDenied`; Android reports `cameraPermissionDenied` until the
  user picks "don't ask again".
- **Credential requests:** Android may call the provider again after a reconnect; iOS
  calls it once per attempt.

## 13. Implementation plan by owner

- **dev: P2, Dart**
  - Files:
    - `lib/aws_liveness_for_flutter.dart`: exports only;
    - `lib/src/aws_liveness.dart`: the facade;
    - `lib/src/liveness_controller.dart`: internal; attempt ids, completer, timers, the
      `LivenessFlutterApi` implementation; host API and clock can be injected;
    - `lib/src/models/{request,theme,result,error,availability}.dart`;
    - `lib/src/wire_converters.dart`;
    - `lib/src/messages.g.dart`: generated with `dart run pigeon --input pigeons/messages.dart`.
  - `analysis_options.yaml`: enable `public_member_api_docs`.
  - Tests per §11.1.
  - Rewrite `test/plugin_layout_test.dart` to parse `pubspec.yaml` and check the
    per-platform registration (review follow-up).
- **android-native: P3** — everything in §7, plus §9.2–9.4 and the example app's
  Android configuration.
- **ios-native: P4** — everything in §8, plus `Package.swift`, XCTest and §9.5.

## 14. Quality standards checklist

| # | Standard | Where / owner | Status |
|---|---|---|---|
| 1 | 100% public Dart API docs, `dart doc` with zero warnings, full pana documentation score | P2 dev, P6 | planned |
| 2 | iOS/Android parity and `doc/platform-parity.md` | P2–P4, P6; §12 | planned |
| 3 | Real-device integration tests and manual checklist | P3/P8 Android; iOS device runs pending | planned |
| 4 | Unit tests: Dart ≥95%, Kotlin JVM, Swift XCTest | P2–P4 | planned |
| 5 | GitHub Actions `ci.yml` and `publish.yml` | P7 | blocked until the token has the `workflow` scope |
| 6 | Dependabot | P7 | planned |
| 7 | Compatibility matrix | P6; §9.1–9.5 | planned |
| 8 | SemVer, CHANGELOG, `doc/releasing.md` | P6/P10 | planned |
| 9 | Exception hierarchy and typed errors | §3.4, §4 | specified |
| 10 | Localization (SDK overrides, plugin strings in en and tr) | §9.7; P3, P6 | specified |
| 11 | `LivenessTheme` | §3.3 | specified |
| 12 | Accessibility and photosensitivity note | P3, P8; §3.2 | planned |
| 13 | Lifecycle | §6 | specified |
| 14 | Camera interruptions | §6.11 | specified |
| 15 | Permissions and `openAppSettings` | §3.5, §6.6 | specified |
| 16 | Orientation | §6.7 | specified |
| 17 | Background and foreground | §6.5 | specified |
| 18 | Timeout, cancel, retry | §6.3–6.4; example app | specified |
| 19 | Native crash protection | §7–8 | specified |
| 20 | Example app | P2/P3 | planned |
| 21 | Lambda backend example | P5 | planned |
| 22 | Cognito example | P5 | planned |
| 23 | Express backend example | P5 | planned |
| 24 | Mermaid diagrams | P6 | planned |
| 25 | `SECURITY.md` and `doc/security.md` | P6 | planned |

## References

Accessed 2026-10-15.

- [A1] Amplify UI, Android Face Liveness: https://ui.docs.amplify.aws/android/connected-components/liveness
- [A2] Amplify UI, Android Face Liveness customization: https://ui.docs.amplify.aws/android/connected-components/liveness/customization
- [A3] Amplify UI, Swift Face Liveness: https://ui.docs.amplify.aws/swift/connected-components/liveness
- [S1] amplify-ui-swift-liveness 1.5.1, `Sources/FaceLiveness/Theming/*` and `Utilities/String+Localizable.swift`: https://github.com/aws-amplify/amplify-ui-swift-liveness/tree/1.5.1
- [S2] amplify-ui-android, tag `release_liveness_v1.12.0`: https://github.com/aws-amplify/amplify-ui-android
- [M1] Maven Central, `liveness-1.12.0.module`: https://repo1.maven.org/maven2/com/amplifyframework/ui/liveness/1.12.0/
- [K1] Kotlin, Compose compiler migration guide: https://kotlinlang.org/docs/compose-compiler-migration-guide.html
- [F1] Flutter, Swift Package Manager for plugin authors: https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors
- [F2] flutter/flutter#178931 (and #181578, #181739): https://github.com/flutter/flutter/pull/178931
- [F3] Third-party plugin PR quoting the Flutter 3.44 warning (secondary source): https://github.com/berkaycatak/adaptive_platform_ui/pull/152
- [F4] Flutter, UIScene migration for plugin authors: https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
- [R1] AWS, Amazon Rekognition endpoints and quotas: https://docs.aws.amazon.com/general/latest/gr/rekognition.html
- [P1] pub.dev, `face_liveness_detector`: https://pub.dev/packages/face_liveness_detector
- [P2] `android/build.gradle` of a related plugin: https://github.com/raichandramohan27ca/amplify-flutter-face-liveness
