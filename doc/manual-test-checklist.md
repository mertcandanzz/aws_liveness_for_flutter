# Manual test checklist

Run on real devices before a release. Nothing on this list has been run yet: every row is
**PENDING**. Record the date, device, OS version, plugin commit and the observed result
when you run an item; never mark an item as passed without running it.

- Android device: Samsung Galaxy S25 Ultra (planned).
- iOS device: none available yet. iOS rows stay PENDING until a device run exists; macOS CI
  covers only the build and unit tests.

Setup: run [`examples/backend-express`](../examples/backend-express), forward the port with
`adb reverse tcp:8787 tcp:8787` and use the [example app](../example). Use a new session for
every row.

## Automated on a device (`example/integration_test/liveness_test.dart`)

| # | Check | Expected | Android | iOS |
|---|---|---|---|---|
| A1 | `checkAvailability()` | available, no reason | PENDING | PENDING |
| A2 | Camera permission revoked and set to "don't ask again" | `cameraPermissionPermanentlyDenied` | PENDING | PENDING |
| A3 | Unknown session id | `sessionNotFound` | PENDING | PENDING |
| A4 | Invalid or expired credentials | `accessDenied` or `invalidSignature` | PENDING | PENDING |
| A5 | Credentials provider throws | `credentialsUnavailable`, `cause` is the thrown object | PENDING | PENDING |
| A6 | `cancel()` during the check | `LivenessCancelled(app)` | PENDING | PENDING |
| A7 | `timeout` elapses | `LivenessFailed(timedOut)` | PENDING | PENDING |

## Manual (needs a person and a real face)

| # | Check | Expected | Android | iOS |
|---|---|---|---|---|
| M1 | Successful check with a real face (FaceMovement) | `LivenessCompleted`; backend `isLive` true above the threshold | PENDING | PENDING |
| M2 | Successful check with FaceMovementAndLight | Same as M1; photosensitivity warning shown on the start view | PENDING | PENDING |
| M3 | FaceMovement with the back camera | Check runs with the back camera | PENDING | PENDING |
| M4 | Rotate the device before starting | Android: portrait, no restart. iOS: rotate prompt | PENDING | PENDING |
| M5 | Rotate the device during the check | Android: no effect. iOS: `sessionInterrupted` | PENDING | PENDING |
| M6 | Send the app to the background during the check, come back | `sessionInterrupted`, retryable; screen brightness restored | PENDING | PENDING |
| M7 | Another app takes the camera, or a phone call arrives | `cameraUnavailable` or `sessionInterrupted`, retryable | PENDING | PENDING |
| M8 | Airplane mode during the check | Typed, retryable error (`sessionInterrupted` expected) | PENDING | PENDING |
| M9 | User closes the screen (close button, Android back) | `LivenessCancelled(user)` | PENDING | PENDING |
| M10 | First camera prompt: deny | Android: `cameraPermissionDenied`. iOS: `cameraPermissionPermanentlyDenied` | PENDING | PENDING |
| M11 | `openAppSettings()` after a permanent denial | App settings page opens | PENDING | PENDING |
| M12 | Theme: light, dark and system with colour overrides | Colours and mode applied | PENDING | PENDING |
| M13 | Large font / largest display size | Text readable, cancel control reachable | PENDING | PENDING |
| M14 | TalkBack (Android) / VoiceOver (iOS) | Cancel control announced ("Cancel the face liveness check" on Android) | PENDING | PENDING |
| M15 | Device language Turkish, then English | SDK text and plugin cancel label follow the language | PENDING | PENDING |
| M16 | App string override of one SDK key | Overridden text shown | PENDING | PENDING |
| M17 | Immediate second check after a result ("Try again") | Starts normally with a new session; no `presenterUnavailable` | PENDING | PENDING |
| M18 | R8 release build of the example: one full check and one error | Same results as debug; error codes mapped (not `unknown`) | PENDING | — |
| M19 | CocoaPods build of the example | `checkAvailability` reports `sdkUnavailable`; `start` fails with `sdkUnavailable`; no crash | — | PENDING |
| M20 | Tablet | Same behaviour as a phone | PENDING | PENDING |

## Results log

| Date | Device / OS | Commit | Rows | Notes |
|---|---|---|---|---|
| — | — | — | — | No runs yet |
