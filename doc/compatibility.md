# Compatibility

For `aws_liveness_for_flutter` 0.1.0. "Tested" means a build or test ran in this
repository; "untested" means the value comes from the SDKs' metadata or documentation and
has not been exercised here yet.

## Native SDKs

| Platform | Dependency | Version | How it is declared |
|---|---|---|---|
| Android | `com.amplifyframework.ui:liveness` | 1.12.0 | normal Gradle version |
| Android | `com.amplifyframework:aws-predictions` (transitive) | 2.41.0 | from `liveness` |
| iOS | `amplify-ui-swift-liveness` (product `FaceLiveness`) | from 1.5.1 | SwiftPM `from:` |
| iOS | `amplify-swift` (transitive) | from 2.60.2 | from `amplify-ui-swift-liveness` |

## Toolchain and platform minimums

| Requirement | Minimum | State | Source |
|---|---|---|---|
| Flutter | 3.38 | tested with 3.38.7 | `pubspec.yaml`; UIScene registrar APIs |
| Dart | 3.10 | tested with 3.10.7 | `pubspec.yaml` |
| Android `minSdk` | 24 | build tested | `liveness` 1.12.0 |
| Android `compileSdk` | 36 | build tested | AAR metadata (`okhttp-android` 5.4.0) |
| Android Gradle Plugin | 8.6.0 | builds tested with 8.11.1 | AAR metadata (`androidx.core` 1.16.0, Compose UI) |
| Gradle | — | tested with 8.14 | example app |
| Kotlin (host app) | 2.1.0 | debug build tested with 2.1.0, 2.2.20 and 2.3.0; R8 release with 2.2.20; 2.0.21 fails fast with a clear message | Amplify metadata targets Kotlin 2.2 |
| Core library desugaring | required | build tested | AAR metadata (Amplify core libraries) |
| iOS | 15.0 | **untested**: no Xcode build yet | `amplify-ui-swift-liveness` `Package.swift` |
| Swift tools | 5.9 | syntax and Linux unit tests with Swift 5.10 and 6.1 only | `Package.swift` |
| Xcode | — | **untested** | — |

The Kotlin and AGP results come from local builds on 2026-10-15; the CI matrix will repeat
them. See [design.md §9.1–9.2](design.md).

## Build systems on iOS

| Mode | Behaviour | State |
|---|---|---|
| Swift Package Manager | Full support: the SDK is linked | **untested** (macOS CI pending) |
| CocoaPods | Builds without the SDK; `checkAvailability()` returns `sdkUnavailable`, `start` fails with `sdkUnavailable`. Needs `platform :ios, '15.0'` in the Podfile | **untested** (macOS CI pending) |

The Amplify liveness SDK is published only through SwiftPM. The plugin keeps a podspec so
CocoaPods apps still build and can show a fallback.

On Flutter 3.44 and later, SwiftPM is on by default and Flutter may warn that the plugin
does not depend on the generated `FlutterFramework` package. That dependency does not
exist on Flutter 3.38, the minimum this plugin supports, so it is left out for now
([design.md §9.5](design.md)).

## Regions

Face Liveness streaming is available in a subset of regions. See
[troubleshooting.md](troubleshooting.md#regions) for the list the plugin knows about.
`start` does not reject other regions, because AWS adds regions over time.

## Why versions are not pinned strictly

- **Android:** `liveness` is declared with a normal version, so Gradle can resolve a newer
  patch release that another library in the app needs. A strict pin would turn every such
  case into a resolution failure in the host app.
- **iOS:** SwiftPM's `from: "1.5.1"` allows 1.x updates and blocks 2.0, which is the
  SDK's own SemVer promise.
- **Risk:** a minor SDK update could change behaviour (for example error messages the
  Android mapper falls back to). The CI and the release checklist rebuild against the
  latest allowed versions, and the error mapping prefers class names and typed cases over
  messages.

Dependabot proposes updates for the Amplify dependencies as a group.
