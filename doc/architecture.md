# Architecture

How `aws_liveness_for_flutter` is put together. The decisions behind it are in
[design.md](design.md).

## Components

```mermaid
flowchart TB
  subgraph Dart["Dart (lib/)"]
    Facade["AwsLiveness<br/>static facade"]
    Controller["LivenessController<br/>validation, attempt ids,<br/>timeout, exactly-once"]
    Converters["wire_converters"]
    Generated["messages.g.dart<br/>(Pigeon)"]
    Facade --> Controller --> Converters --> Generated
  end

  subgraph Android["Android (android/)"]
    APlugin["AwsLivenessForFlutterPlugin"]
    AHost["LivenessHostApiImpl"]
    ARegistry["SessionRegistry<br/>process-wide slot"]
    AActivity["LivenessActivity<br/>Compose, FaceLivenessDetector"]
    ACreds["PluginCredentialsProvider"]
    APlugin --> AHost --> ARegistry
    AHost --> AActivity --> ACreds
  end

  subgraph IOS["iOS (ios/)"]
    IPlugin["AwsLivenessForFlutterPlugin"]
    IHost["LivenessHost"]
    ICoord["SessionCoordinator<br/>process-wide slot"]
    IView["LivenessViewController<br/>FaceLivenessDetectorView"]
    ICreds["CredentialsBroker"]
    IPlugin --> IHost --> ICoord
    IHost --> IView --> ICreds
  end

  Generated <-->|"LivenessHostApi<br/>LivenessFlutterApi"| AHost
  Generated <-->|"LivenessHostApi<br/>LivenessFlutterApi"| IHost
  AActivity --> AmplifyA["com.amplifyframework.ui:liveness"]
  IView --> AmplifyI["amplify-ui-swift-liveness"]
```

- **Dart.** `AwsLiveness` is the only public entry point. `LivenessController` validates the
  request, gives every attempt an increasing `attemptId`, completes each attempt exactly
  once, runs the timeout and answers native credential requests.
- **Channel.** [Pigeon](https://pub.dev/packages/pigeon) generates typed Dart, Kotlin and
  Swift code from `pigeons/messages.dart`. `LivenessHostApi` goes from Dart to native;
  `LivenessFlutterApi.fetchCredentials` goes from native to Dart.
- **Native hosts.** Each shows the SDK screen full screen without touching the app's own
  Activity or view controllers: a plugin-owned `ComponentActivity` on Android and a
  `UIHostingController` on iOS. A process-wide single slot makes sure only one attempt runs
  at a time, even with several Flutter engines.
- **SDKs.** The official Amplify UI liveness components do the camera work, the challenge
  and the streaming to Rekognition.

## One liveness check

```mermaid
sequenceDiagram
  autonumber
  participant App as Flutter app
  participant BE as Your backend
  participant Plugin as AwsLiveness (Dart)
  participant Host as Native host
  participant SDK as Amplify SDK
  participant Rek as Rekognition

  App->>BE: create session
  BE->>Rek: CreateFaceLivenessSession
  Rek-->>BE: sessionId
  BE-->>App: sessionId, region
  App->>Plugin: start(LivenessRequest)
  Plugin->>Host: start(attemptId, sessionId, region, options)
  Host->>Host: camera permission pre-check
  Host->>SDK: show liveness screen
  SDK->>Host: need credentials
  Host->>Plugin: fetchCredentials(attemptId)
  Plugin->>App: credentialsProvider()
  App->>BE: get credentials
  BE-->>App: temporary credentials (StartFaceLivenessSession only)
  App-->>Plugin: LivenessCredentials
  Plugin-->>Host: credentials (memory only)
  SDK->>Rek: StartFaceLivenessSession (video stream)
  Rek-->>SDK: done
  SDK-->>Host: completed
  Host->>Host: close UI, then deliver once
  Host-->>Plugin: outcome
  Plugin-->>App: LivenessCompleted
  App->>BE: read result
  BE->>Rek: GetFaceLivenessSessionResults
  Rek-->>BE: status, confidence
  BE-->>App: isLive (decided with the server's threshold)
```

Notes:

- The provider may run more than once on Android (after a reconnect). On iOS it runs once
  per attempt.
- The result is delivered after the native screen has closed (at most 3 seconds later), so
  the next `start` finds the app in the foreground.
- The app never sees a confidence score from the plugin; only the backend reads it.

## Errors and ending an attempt

```mermaid
flowchart TD
  Start["start(request)"] --> Validate{"valid input and<br/>no active attempt?"}
  Validate -- no --> Throw["throws ArgumentError / StateError<br/>(programming error)"]
  Validate -- yes --> Native["native host runs the attempt"]
  Native --> Ends{"how does it end?"}
  Ends -->|"user closes the screen"| Cancelled["LivenessCancelled(user)"]
  Ends -->|"cancel() or timeout"| PluginEnd["plugin-initiated end:<br/>LivenessCancelled(app) or<br/>LivenessFailed(timedOut)"]
  Ends -->|"credentialsProvider failed"| Creds["LivenessFailed(credentialsUnavailable)<br/>cause = the thrown object"]
  Ends -->|"SDK error"| Map["map native error<br/>(design §4.3, §4.4)"] --> Failed["LivenessFailed(code)"]
  Ends -->|"video streamed"| Completed["LivenessCompleted"]
  Ends -->|"plugin missing / channel error"| Unavailable["LivenessFailed(sdkUnavailable or unknown)"]
```

The order of precedence when several things happen at once (design §4.2):

1. A user cancel reported by the SDK.
2. A plugin-initiated end (app cancel, timeout, backgrounding, presenter loss, engine detach).
   A real completion that raced the cancel is kept.
3. A failure of your `credentialsProvider`, whatever the SDK reports afterwards.
4. The mapped SDK error.
5. `unknown`, with the native details.

Every attempt produces exactly one result. Three guards make sure of that: the native slot,
the Dart completer and the `attemptId` that native code echoes back. When a Flutter engine
detaches, its attempt is dropped and no result is sent.
