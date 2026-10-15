import 'theme.dart';

/// Returns temporary AWS credentials for one liveness attempt.
///
/// Called every time a native SDK asks for credentials: at least once per
/// attempt, and Android may ask again after a reconnect. Fetch the credentials
/// from your own backend; never embed long-lived keys in the app.
typedef LivenessCredentialsProvider = Future<LivenessCredentials> Function();

/// Temporary AWS credentials scoped to `rekognition:StartFaceLivenessSession`.
///
/// The plugin keeps them in memory only, never logs them and does not cache
/// them between requests.
final class LivenessCredentials {
  /// Creates temporary credentials. All string fields must be non-empty and
  /// [expiration] must be in the future when the plugin receives them.
  const LivenessCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
  });

  /// The AWS access key id of the temporary credentials.
  final String accessKeyId;

  /// The AWS secret access key of the temporary credentials.
  final String secretAccessKey;

  /// The session token that makes these credentials temporary.
  final String sessionToken;

  /// When the credentials expire.
  final DateTime expiration;

  @override
  String toString() => 'LivenessCredentials(<redacted>)';
}

/// Camera used by the FaceMovement challenge.
enum LivenessCamera {
  /// The front-facing camera.
  front,

  /// The rear-facing camera.
  back,
}

/// Client-side options for the challenge chosen by the backend.
///
/// The backend picks `FaceMovementAndLightChallenge` or `FaceMovementChallenge`
/// through `ChallengePreferences` in `CreateFaceLivenessSession`.
/// FaceMovementAndLight always uses the front camera.
final class LivenessChallengeOptions {
  /// Creates challenge options.
  const LivenessChallengeOptions({
    this.faceMovementCamera = LivenessCamera.front,
  });

  /// Camera for the FaceMovement challenge. Ignored by FaceMovementAndLight.
  final LivenessCamera faceMovementCamera;
}

/// Everything needed to run one liveness attempt.
final class LivenessRequest {
  /// Creates a request for one attempt.
  ///
  /// Sessions are single use: create a new session with
  /// `CreateFaceLivenessSession` for every attempt, including retries.
  const LivenessRequest({
    required this.sessionId,
    required this.region,
    required this.credentialsProvider,
    this.challengeOptions = const LivenessChallengeOptions(),
    this.showStartView = true,
    this.theme = const LivenessTheme(),
    this.timeout,
    this.credentialsTimeout = const Duration(seconds: 15),
  });

  /// The session id returned by `CreateFaceLivenessSession` on your backend.
  final String sessionId;

  /// The AWS region of the session, for example `eu-west-1`.
  final String region;

  /// Supplies temporary credentials whenever the native SDK needs them.
  final LivenessCredentialsProvider credentialsProvider;

  /// Client-side challenge options.
  final LivenessChallengeOptions challengeOptions;

  /// Whether the SDK shows its introduction screen before the check.
  final bool showStartView;

  /// Colours and light/dark mode of the native liveness UI.
  final LivenessTheme theme;

  /// Upper bound for the whole attempt, measured from the `start` call and
  /// including the permission prompt and the start view. `null` means no
  /// plugin-side timeout.
  final Duration? timeout;

  /// How long [credentialsProvider] may take before the attempt fails with
  /// `credentialsUnavailable`.
  final Duration credentialsTimeout;
}
