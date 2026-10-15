# Platform parity

The Dart API is the same on both platforms. The native SDKs differ in places the plugin
cannot hide; this page lists them per behaviour. Unless stated otherwise, the behaviour is
implemented but **not yet observed on a device** (see the
[manual test checklist](manual-test-checklist.md)).

## Camera permission

| | Android | iOS |
|---|---|---|
| Who asks | The plugin, before showing the SDK screen (the SDK does not ask) | The plugin, before showing the SDK screen |
| Missing usage text | Not applicable | `missingCameraUsageDescription`, without calling `requestAccess` (which would crash) |
| First denial in `start` | `cameraPermissionDenied` (can ask again) | `cameraPermissionPermanentlyDenied` (iOS cannot ask twice) |
| "Don't ask again" | `cameraPermissionPermanentlyDenied` | — |
| Statuses | `granted`, `notDetermined`, `denied`, `permanentlyDenied` | `granted`, `notDetermined`, `permanentlyDenied`, `restricted` |
| Before the first request | May report `notDetermined` even for a permanent denial | Exact |
| No camera | `checkAvailability` reports `noCamera`; `start` fails with the SDK's camera error, mapped to `cameraUnavailable` | `checkAvailability` reports `noCamera`; `start` fails with `cameraUnavailable` before any UI (for example the simulator) |

## Orientation

| | Android | iOS |
|---|---|---|
| Landscape | The SDK locks portrait; rotation never recreates the screen | The SDK shows a "rotate your device" view |
| Rotating during the check | No effect | `sessionInterrupted` |
| Cancelling on the rotate view | — | `LivenessCancelled(user)` |

## Backgrounding

| | Android | iOS |
|---|---|---|
| App sent to the background while the screen is visible | `sessionInterrupted` (`onStop` without a configuration change) | `sessionInterrupted` (scene or app background notification) |
| Process death | The liveness screen closes without a result; Dart is gone too | — |
| Screen recreated while Dart waits | `sessionInterrupted` | — |

## Credentials

| | Android | iOS |
|---|---|---|
| Calls to `credentialsProvider` | At least once per attempt; again after a clock-skew reconnect | Once per attempt |
| Provider fails or times out | `credentialsUnavailable` | `credentialsUnavailable` (the SDK itself would report `socketClosed`) |
| Native guard timeout | `credentialsTimeout` + 5 s | `credentialsTimeout` + 5 s |

## Theme

| | Android | iOS |
|---|---|---|
| Colour tokens | 9 shared tokens; `onSurface` follows `onBackground` | 9 shared tokens |
| `LivenessThemeMode.system` | Follows the system setting | Dynamic colours that follow the system setting |
| Forced light or dark | Picks the matching colour scheme | Overrides the screen's interface style |
| Fonts, shapes | Not exposed | Not exposed |

## Localization

| | Android | iOS |
|---|---|---|
| SDK strings | Override in `res/values-<lang>/strings.xml` | Override in the app's `Localizable.strings` |
| Plugin strings | Cancel label and its content description (en, tr) | None (the SDK draws its own close button) |

Details: [localization.md](localization.md).

## Cancel

| | Android | iOS |
|---|---|---|
| On-screen control | The plugin's button in the SDK's cancel slot; also drawn by the plugin during the start view and while connecting | The SDK's close button |
| System back | Cancels (`LivenessCancelled(user)`) | — |
| `AwsLiveness.cancel()` | Closes the SDK session properly, `LivenessCancelled(app)` | Dismisses the screen, `LivenessCancelled(app)` |
| Cancel before the screen appears | Finishes at once | Skips the presentation |

## Timeout

| | Android | iOS |
|---|---|---|
| `LivenessRequest.timeout` | Dart asks native to close the screen; `LivenessFailed(timedOut)`; Dart completes by itself after a further 5 s if native does not answer | Same |
| SDK session timeout | `sessionTimedOut` | `sessionTimedOut` |
| Face not in the oval in time | `faceFitTimedOut` | `faceFitTimedOut` |

## Error codes only one SDK reports

| Code | Platform | Why |
|---|---|---|
| `faceTooClose`, `multipleFaces`, `noFaceDetected` | iOS | Android shows these situations as on-screen hints instead |
| `unsupportedChallenge` | Android | Only the Android SDK reports it |
| `videoEncodingFailed` | Android | Encoding and muxing happen in the Android SDK |
| `invalidRegion` | iOS | Android's behaviour for an unsupported region is not observed yet; expected `unknown` |
| `missingCameraUsageDescription` | iOS | Info.plist requirement |
