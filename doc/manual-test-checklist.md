# Manual test checklist

Run on real devices before a release. Only the explicitly dated results below have been
run; all other checks remain **PENDING**. Record the date, device, OS version, plugin commit
and observed result for each run; never infer a device pass from a build or mock test.

- Android device: Samsung Galaxy S25 Ultra (`SM-S938B`), Android 17; first run 2026-10-15.
- iOS device: none available yet. iOS rows stay PENDING until a device run exists; macOS CI
  covers only the build and unit tests.

For the AWS-dependent rows, run [`examples/backend-express`](../examples/backend-express), forward the port with
`adb reverse tcp:8787 tcp:8787` and use the [example app](../example). Use a new session for
every row.

## Automated on a device (`example/integration_test/liveness_test.dart`)

| # | Check | Expected | Android | iOS |
|---|---|---|---|---|
| A1 | `checkAvailability()` | available, no reason | PASS — 2026-10-15, step 1 | PENDING |
| A2 | Camera permission revoked and set to "don't ask again" | `cameraPermissionPermanentlyDenied` | PASS — 2026-10-15, ADB revoke + user-fixed | PENDING |
| A3 | Unknown session id | `sessionNotFound` | PENDING | PENDING |
| A4 | Invalid or expired credentials | `accessDenied` or `invalidSignature` | PENDING | PENDING |
| A5 | Credentials provider throws | `credentialsUnavailable`, `cause` is the thrown object | PASS — 2026-10-15, dummy session, throwing provider | PENDING |
| A6 | `cancel()` during the check | `LivenessCancelled(app)` | PASS — 2026-10-15, start view, no credentials | PENDING |
| A7 | `timeout` elapses | `LivenessFailed(timedOut)` | PASS — 2026-10-15, 5 s timeout, start view | PENDING |

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
| 2026-10-15 | Galaxy S25 Ultra / SM-S938B / Android 17 | `3079c45f7f50c9fe7262cdaa8a74d1105a7c055d` | A1, A2, A5, A6, A7 | PASS; real device, no backend or AWS session. A3/A4 skipped: backend URL/token not configured. |
| 2026-10-15 | Same device and source revision | `3079c45` | S1/S2 below | PASS; temporary start-view probe and host ADB controls. Does not complete the physical-rotation/full-check/close-button rows M4/M5/M9. |

### P8 step 1: start-view probes (no AWS)

Device serial: `R5GYC5D549Z`, in ADB `device` state. Source tree was clean at the
recorded revision. The normal example debug APK was built and installed successfully.

| ID | Actual action | Observed result | Android | iOS |
|---|---|---|---|---|
| S1 | While the native start view was open, request 90-degree rotation using `adb shell wm user-rotation lock 1`, then restore portrait and the original rotation settings | Portrait remained enforced; client `Local Activity d242fe6` and PID 22082 were unchanged, resumed and not finishing before/after; no Activity recreation observed | PASS | PENDING |
| S2 | Send Android Back with `adb shell input keyevent KEYCODE_BACK` on the native start view | `LivenessCancelled(user)`; `AwsLiveness.isActive == false` | PASS | PENDING |

The ordinary integration file ran twice without backend URL/token defines:

- With camera permission revoked and `user-fixed` set, using
  `--dart-define=EXPECT_CAMERA_PERMANENTLY_DENIED=true`: 2 passed, 5 skipped, 0 failed.
  A2 asserted the exact error code and the `permission` category. Other camera tests
  skipped explicitly because permission was not granted.
- After reinstalling the APK and granting camera permission with ADB, without that
  define: 4 passed, 3 skipped, 0 failed. A1/A5/A6/A7 passed; A2 was disabled for this
  phase and A3/A4 skipped explicitly because backend URL/token were unset.
- A separate temporary integration probe for S1/S2 passed (1 test). It used a dummy
  session, `showStartView: true` and a credentials provider that never resolves.
  Its source and filtered dumpsys output are retained in local QA evidence; it was
  removed from the working tree after the run. No successful liveness result was faked.

Reproduction for the two ordinary phases: run from `example/` with
`flutter test integration_test/liveness_test.dart -d R5GYC5D549Z --reporter expanded`,
adding the permission define for the first phase. Reinstall before setting permissions
between runs: this host's Flutter integration runner removes the app during teardown.
No system permission dialog or user face input was needed.

Only package-filtered ActivityTaskManager lines and AndroidRuntime crash lines were
requested from logcat; the retained filtered output was empty (no matching crash
observed). Rotation settings were restored to `accelerometer_rotation=1` and
`user_rotation=0`. `stay_on_while_plugged_in` was **3** before and after this step and
was not changed; reset it to 0 at the end of P8, not at the end of this step.

Backend/AWS checks, real-face checks, all remaining manual rows and every iOS device
row remain PENDING. Step 1 does not establish release/R8 behaviour or an end-to-end
liveness decision. Local evidence: `build/qa-p8-step1/` (gitignored).

### P8 step 2: AWS preflight blocked (2026-10-15)

Source revision: `768d54a5c34c10a7ec533e006357a9c34003cb34` on `main`.
The intended device is the Galaxy S25 Ultra / SM-S938B / Android 17 from step 1;
it was not present in the current ADB device list, so its OS was not re-read.

The authorized local configuration contains AWS access credentials but no IAM role
ARN for the backend's `LIVENESS_CREDENTIALS_ROLE_ARN`. The credentials endpoint needs
an existing, assumable role with `rekognition:StartFaceLivenessSession` permission
and a trust policy allowing the backend caller. No IAM resource was created.

| Check | Result | Reason |
|---|---|---|
| A3: unknown session | PENDING — not run | No assumable role configured; device not detected |
| A4: invalid/expired credentials | PENDING — not run | Backend and device prerequisites unavailable |
| SDK operation without `Amplify.configure()` against AWS | PENDING — not run | No AWS request made |
| M1/M2: real-face checks and server decision | PENDING — not run | Await role, device and guided user input |
| M18: release/R8 with real AWS | PENDING — not run | Needs HTTPS; release rejects HTTP loopback |

The backend was not started, no demo token or ADB reverse was created, and no
credentials were written to files or logs. No device settings were changed.
P8 remains in progress; the end-of-P8 reset of `stay_on_while_plugged_in` is still
pending. PR #5 was merged before this preflight; post-merge CI run `38741987057`
was scheduled and is separate from the completed PR validation.
