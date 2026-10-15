# iOS SDK surface used by the plugin

The iOS host was written without a Mac, so every FaceLiveness and Amplify symbol it uses
was copied from the tagged sources below rather than from compiler feedback. Read on
2026-10-15. If an SDK upgrade changes one of these, `tool/ios_linux_check.sh` will not
notice; only the macOS CI jobs will.

- FaceLiveness: [amplify-ui-swift-liveness `1.5.1`](https://github.com/aws-amplify/amplify-ui-swift-liveness/tree/1.5.1),
  paths below relative to `Sources/FaceLiveness/`.
- Credentials protocols: [amplify-swift `2.60.2`](https://github.com/aws-amplify/amplify-swift/tree/2.60.2)
  (the minimum that liveness 1.5.1 requires), unchanged in `2.62.1`.

| Symbol | Used as | Source |
|---|---|---|
| Package product `FaceLiveness`, package identity `amplify-ui-swift-liveness`, iOS 15, dependency `amplify-swift` from 2.60.2 | `Package.swift` | `Package.swift` (repository root) |
| `FaceLivenessDetectorView.init(sessionID:credentialsProvider:region:disableStartView:challengeOptions:isPresented:onCompletion:)` | `credentialsProvider: AWSCredentialsProvider? = nil`, `region: String`, `disableStartView: Bool = false`, `challengeOptions: ChallengeOptions = .init()`, `isPresented: Binding<Bool>`, `onCompletion: @escaping (Result<Void, FaceLivenessDetectionError>) -> Void` | `Views/Liveness/FaceLivenessDetectionView.swift` |
| `try! FaceDetectorShortRange.Model()` in that initialiser; the model is `face_detection_short_range.mlmodelc` from `Bundle.module` | the model pre-check (design §8) | `Views/Liveness/FaceLivenessDetectionView.swift`, `FaceDetection/BlazeFace/FaceDetectorShortRange+Model.swift`, `FaceDetection/BlazeFace/face_detection_short_range.swift` |
| The view sets `isPresented = false` and calls `onCompletion` once a terminal state is reached; `onCompletion` is also called from the session's completion | constant binding; results moved to the main thread | `Views/Liveness/FaceLivenessDetectionView.swift` (`onReceive(viewModel.$livenessState)`, `map(detectionCompletion:)`) |
| `ChallengeOptions(faceMovementChallengeOption:faceMovementAndLightChallengeOption:)` (both defaulted), `FaceMovementChallengeOption(camera:)`, `LivenessCamera.front` / `.back` | camera selection | `Views/Liveness/FaceLivenessDetectionView.swift` |
| `FaceLivenessDetectionError`: `Error, Equatable`; `code: UInt8` is **internal**; public `message`, `recoverySuggestion`; `==` compares `code`; static cases `unknown` (0) … `sessionInterrupted` (19) | `SdkError(_:)` compares against the 20 static cases | `Views/Liveness/FaceLivenessDetectionError.swift` |
| `@MainActor public final class FaceLivenessDetectorTheme`: `nonisolated init()` (system colours), `nonisolated init(colorScheme: ColorScheme)`, `public var colors: Colors` | `ThemeMapper.theme(for:)` | `Theming/FaceLivenessDetectorTheme.swift` |
| `FaceLivenessDetectorTheme.Colors` public vars `primary`, `onPrimary`, `error`, `onError`, `background`, `onBackground`, `surface`, `errorContainer`, `onErrorContainer` (`Color`); no public initialiser | `ThemeMapper.tokens()` | `Theming/FaceLivenessDetectorTheme.swift` |
| `View.faceLivenessDetectorTheme(_:)` | `LivenessContainer` | `Theming/View+FaceLivenessDetectorTheme.swift` |
| `.cancelButton { configuration in … }`, `.hidesCancelButton(_:)` | not used (design §9.7 correction) | `Views/Liveness/FaceLivenessDetectorView+CancelButton.swift` |
| `@_exported import protocol AWSPluginsCore.AWSCredentialsProvider` / `AWSCredentials` / `AWSTemporaryCredentials` | `import FaceLiveness` is enough | `Views/Liveness/FaceLivenessDetectionView.swift` |
| `protocol AWSCredentialsProvider { func fetchAWSCredentials() async throws -> AWSCredentials }` | `PluginCredentialsProvider` | amplify-swift `AmplifyPlugins/Core/AWSPluginsCore/Auth/AuthAWSCredentialsProvider.swift` |
| `protocol AWSCredentials: Sendable { var accessKeyId: String { get }; var secretAccessKey: String { get } }`, `protocol AWSTemporaryCredentials: AWSCredentials { var sessionToken: String { get }; var expiration: Date { get } }` | `PluginTemporaryCredentials` | same file |

Flutter APIs (local Flutter 3.38.7 SDK,
`engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterPlugin.h`):
`FlutterPluginRegistrar.viewController` (nullable), `publish(_:)`, `messenger()`, and
`FlutterPlugin.detachFromEngine(for:)`, which is called only for plugins that published
themselves.
