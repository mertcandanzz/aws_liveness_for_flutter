# Security

What the plugin protects, what it relies on you to do, and how the example backend does it.
To report a vulnerability, see [SECURITY.md](../SECURITY.md).

## Trust model

| Part | Trusted to |
|---|---|
| Your backend | Create sessions, vend scoped credentials, decide the result |
| The app and this plugin | Show the check and stream the video; nothing else |
| Amazon Rekognition | Judge liveness and keep the result for your backend |

The device is not trusted: an attacker can change the app, hook the plugin or replay
network traffic. Everything that matters for the decision therefore stays on the server.

## Rules for integrators

1. **Decide on the server.** Call `GetFaceLivenessSessionResults` from your backend and
   compare `Confidence` with a threshold that only the backend knows. `LivenessCompleted`
   only means the video was streamed. The plugin never returns a score or `isLive`.
2. **Bind sessions to users.** Store which user created each session and only accept that
   user's result reads. A session created for user A must not log in user B.
3. **One session per attempt.** Sessions are single use and expire about three minutes after
   creation. Create a new one for every retry. Never reuse a session id from a client, and
   accept each session's result once (mark it consumed), so a recorded success cannot be
   replayed to sign in again.
4. **Scope the credentials.** Give the app temporary credentials that allow only
   `rekognition:StartFaceLivenessSession`, for the shortest duration STS allows (900
   seconds). Never ship long-lived access keys, and never give the app permission to call
   `CreateFaceLivenessSession` or `GetFaceLivenessSessionResults`.
5. **Authenticate the backend calls.** Your session, credentials and result endpoints must
   require your own user authentication and HTTPS.
6. **Rate-limit.** Each check costs money (about 0.015 USD) and creates load. Limit session
   creation per user and per IP.
7. **Keep images private.** Reference and audit images (if you store them in S3) are
   biometric data. Encrypt them, restrict access and set a retention period that matches
   your privacy notice. Many laws treat face data as a special category (for example the
   EU GDPR and the Illinois BIPA): get the consent they require, tell users what you keep
   and for how long, and check your obligations with your own counsel.
8. **Use a supported region.** Face Liveness streaming exists only in some regions (see
   [troubleshooting.md](troubleshooting.md#regions)). Keep the video and results in the
   region your privacy notice names.

## Rooted and jailbroken devices

The plugin does not detect rooted or jailbroken devices, and liveness does not depend on
the device being intact: Rekognition judges the video stream on the server. A modified
device can still tamper with the app around the check, which is why the decision, the
session binding and the single-use rule must live on your backend. If your threat model
needs device integrity, add Play Integrity or App Attest checks in your app and verify
them on the backend.

## What the plugin does

- **Credentials in memory only.** They cross the channel only as the reply to a native
  `fetchCredentials` request, are converted to SDK types at once and are never stored.
  `LivenessCredentials.toString()` is redacted on Dart, `PluginTemporaryCredentials` is
  redacted in every Swift description, and no plugin code logs credentials or the Pigeon
  credential messages (whose generated `toString`/`description` would print them).
- **Provider errors stay in Dart.** If your `credentialsProvider` throws, the thrown object
  becomes `LivenessError.cause`. It is never sent to native code or logged.
- **Stale requests are refused.** Credential requests carry the `attemptId`; Dart answers
  requests for any other attempt with `staleAttempt`, and native code drops a reply that
  arrives after the attempt has ended.
- **No logging, no images.** Plugin code contains no log calls. The plugin never receives
  video frames or images: the SDK streams them straight to Rekognition.
- **Native details are safe to log.** `nativeDetails` holds error names and SDK messages,
  never credentials.
- **Android components are private.** Both plugin activities are `exported="false"`. The
  liveness Activity's Intent carries only a process-unique token; the request stays in
  memory.
- **R8.** `consumer-rules.pro` keeps only the class names the error mapper reads.

## The example backends

[`examples/backend-express`](../examples/backend-express) follows the rules above:

- `AssumeRole` with an inline session policy that allows only
  `rekognition:StartFaceLivenessSession`, `DurationSeconds: 900`;
- bearer tokens compared in constant time; each token is a separate caller;
- sessions bound in memory to the caller that created them, for credentials and results;
- `isLive` decided from `LIVENESS_CONFIDENCE_THRESHOLD`; a threshold from the client is
  ignored and images are never returned;
- AWS error messages are not forwarded; logs hold method, path, status and duration only;
- a per-IP rate limit and `Cache-Control: no-store` on credentials and results.

It is an example: in-memory state, one process, static bearer tokens, and results can be
read more than once. Put your real user authentication, a database, a shared rate limiter
and a consumed-result flag (rule 3) in place before production use.

[`examples/backend-lambda`](../examples/backend-lambda) applies the same rules with
production-shaped pieces: sessions bound to the caller in DynamoDB (10-minute TTL) and a
final result handed out once through a conditional update; a Lambda authorizer that stores
only SHA-256 digests of tokens (swap in a JWT authorizer for real users); HTTP API stage
throttling; and one IAM role per function with only the actions it calls.

[`examples/cognito`](../examples/cognito) gives signed-in users identity pool credentials
whose role allows only `rekognition:StartFaceLivenessSession`. Those credentials last about
an hour (the identity pool's enhanced flow), and session creation and results still go
through a backend: the app never gets `CreateFaceLivenessSession` or
`GetFaceLivenessSessionResults`.

The example app enforces HTTPS for the backend in `BackendClient`: `http://` is accepted
only for `localhost`, `127.0.0.1` and `::1` in debug builds, and redirects are never
followed.

## Privacy

- The video goes from the SDK directly to Rekognition in the region you choose. The plugin
  itself collects, stores and sends nothing.
- iOS: the plugin's `PrivacyInfo.xcprivacy` declares no collected data, no tracking and no
  required-reason API. Describe the camera use and the biometric processing in your own app
  privacy details and policy.
- Android: declare camera and biometric data handling in the Play Console data safety form
  according to how your backend stores results and images.
