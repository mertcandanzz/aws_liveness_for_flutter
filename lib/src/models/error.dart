/// Broad groups of [LivenessErrorCode]s.
enum LivenessErrorCategory {
  /// Camera permission problems.
  permission,

  /// Missing, invalid or rejected AWS credentials.
  credentials,

  /// Session, region, build or app configuration problems.
  configuration,

  /// Errors reported by the Rekognition service.
  service,

  /// The check was interrupted before it finished.
  interrupted,

  /// Device, camera or presentation problems.
  device,

  /// A time limit elapsed.
  timeout,

  /// Anything not covered by the other categories.
  unknown,
}

/// Stable error codes reported in [LivenessError.code].
///
/// Code names are a public contract: they are not renamed or removed without
/// a deprecation cycle, and new codes are appended. Map them to your own
/// user-facing text; [message] and [recoverySuggestion] are English and meant
/// for developers and logs.
enum LivenessErrorCode {
  /// The user denied the camera permission; the app may ask again.
  cameraPermissionDenied(
    LivenessErrorCategory.permission,
    isRetryable: true,
    message: 'Camera permission was denied.',
    recoverySuggestion:
        'Explain why the camera is needed and start a new attempt to ask again.',
  ),

  /// The camera permission can only be granted in the system settings.
  cameraPermissionPermanentlyDenied(
    LivenessErrorCategory.permission,
    isRetryable: false,
    message: 'Camera permission is permanently denied.',
    recoverySuggestion:
        'Ask the user to allow camera access in the system settings '
        '(AwsLiveness.openAppSettings).',
  ),

  /// The credentials provider threw, timed out or returned invalid
  /// credentials, or the plugin could not deliver them.
  credentialsUnavailable(
    LivenessErrorCategory.credentials,
    isRetryable: true,
    message: 'Temporary AWS credentials could not be obtained.',
    recoverySuggestion:
        'Check the credentials provider and the backend that vends the '
        'credentials, then retry with a new session.',
  ),

  /// IAM denied `StartFaceLivenessSession`, or the access key is unknown.
  accessDenied(
    LivenessErrorCategory.credentials,
    isRetryable: false,
    message: 'AWS denied access to the Face Liveness session.',
    recoverySuggestion:
        'Allow rekognition:StartFaceLivenessSession for the credentials and '
        'make sure the access key is valid.',
  ),

  /// The request signature was rejected: expired credentials or clock skew.
  invalidSignature(
    LivenessErrorCategory.credentials,
    isRetryable: true,
    message: 'AWS rejected the request signature.',
    recoverySuggestion:
        'Return fresh credentials and check that the device clock is correct.',
  ),

  /// The session is unknown, expired, already used or from another region.
  sessionNotFound(
    LivenessErrorCategory.configuration,
    isRetryable: true,
    message: 'The Face Liveness session was not found.',
    recoverySuggestion:
        'Create a new session for every attempt and use the region it was '
        'created in.',
  ),

  /// The region is not valid for Face Liveness.
  invalidRegion(
    LivenessErrorCategory.configuration,
    isRetryable: false,
    message: 'The region is not valid for Face Liveness.',
    recoverySuggestion:
        'Use a region that supports Face Liveness streaming '
        '(see AwsLiveness.knownSupportedRegions).',
  ),

  /// The service rejected the request as invalid.
  validation(
    LivenessErrorCategory.configuration,
    isRetryable: false,
    message: 'The Face Liveness request was invalid.',
    recoverySuggestion:
        'Check the session settings on the backend and the native details.',
  ),

  /// The session asks for a challenge the client does not support.
  unsupportedChallenge(
    LivenessErrorCategory.configuration,
    isRetryable: false,
    message: 'The session requested an unsupported challenge.',
    recoverySuggestion:
        'Check ChallengePreferences in CreateFaceLivenessSession and update '
        'the plugin.',
  ),

  /// The native SDK is not available in this build or on this platform.
  sdkUnavailable(
    LivenessErrorCategory.configuration,
    isRetryable: false,
    message: 'The native Face Liveness SDK is not available.',
    recoverySuggestion:
        'On iOS, build with Swift Package Manager enabled. Only Android and '
        'iOS are supported.',
  ),

  /// The iOS app's `Info.plist` has no `NSCameraUsageDescription`.
  missingCameraUsageDescription(
    LivenessErrorCategory.configuration,
    isRetryable: false,
    message: 'NSCameraUsageDescription is missing from Info.plist.',
    recoverySuggestion:
        'Add an NSCameraUsageDescription entry to the iOS app Info.plist.',
  ),

  /// Too many requests or a service quota was exceeded.
  throttled(
    LivenessErrorCategory.service,
    isRetryable: true,
    message: 'The request was throttled by AWS.',
    recoverySuggestion: 'Retry later with a new session; check service quotas.',
  ),

  /// The service is temporarily unavailable.
  serviceUnavailable(
    LivenessErrorCategory.service,
    isRetryable: true,
    message: 'The Face Liveness service is unavailable.',
    recoverySuggestion: 'Retry later with a new session.',
  ),

  /// The service hit an internal error.
  internalServerError(
    LivenessErrorCategory.service,
    isRetryable: true,
    message: 'The Face Liveness service reported an internal error.',
    recoverySuggestion: 'Retry with a new session.',
  ),

  /// The check was interrupted: backgrounding, a call, a lost connection,
  /// rotation during the check or the UI being dismissed.
  sessionInterrupted(
    LivenessErrorCategory.interrupted,
    isRetryable: true,
    message: 'The liveness check was interrupted.',
    recoverySuggestion:
        'Keep the app in the foreground and online, then retry with a new '
        'session.',
  ),

  /// iOS only: the face was too close to the camera during the countdown.
  faceTooClose(
    LivenessErrorCategory.interrupted,
    isRetryable: true,
    message: 'The face was too close to the camera.',
    recoverySuggestion:
        'Ask the user to hold the phone further away and retry.',
  ),

  /// iOS only: more than one face was detected during the countdown.
  multipleFaces(
    LivenessErrorCategory.interrupted,
    isRetryable: true,
    message: 'More than one face was detected.',
    recoverySuggestion: 'Ask the user to be alone in the frame and retry.',
  ),

  /// iOS only: no face was detected during the countdown.
  noFaceDetected(
    LivenessErrorCategory.interrupted,
    isRetryable: true,
    message: 'No face was detected.',
    recoverySuggestion:
        'Ask the user to face the camera in good light and retry.',
  ),

  /// The camera is busy or failed.
  cameraUnavailable(
    LivenessErrorCategory.device,
    isRetryable: true,
    message: 'The camera is not available.',
    recoverySuggestion: 'Close other apps that use the camera and retry.',
  ),

  /// Android only: video encoding or muxing failed.
  videoEncodingFailed(
    LivenessErrorCategory.device,
    isRetryable: true,
    message: 'The liveness video could not be encoded.',
    recoverySuggestion: 'Retry with a new session.',
  ),

  /// No foreground Activity or view controller to present the UI from.
  presenterUnavailable(
    LivenessErrorCategory.device,
    isRetryable: true,
    message: 'There is no foreground screen to present the liveness UI from.',
    recoverySuggestion: 'Start the check while the app is in the foreground.',
  ),

  /// Another Flutter engine in this process owns the active session.
  alreadyActive(
    LivenessErrorCategory.device,
    isRetryable: true,
    message: 'Another liveness check is already running in this app.',
    recoverySuggestion: 'Wait for the other check to finish, then retry.',
  ),

  /// `LivenessRequest.timeout` elapsed.
  timedOut(
    LivenessErrorCategory.timeout,
    isRetryable: true,
    message: 'The liveness attempt timed out.',
    recoverySuggestion:
        'Retry with a new session or increase LivenessRequest.timeout.',
  ),

  /// The SDK reported that the session timed out.
  sessionTimedOut(
    LivenessErrorCategory.timeout,
    isRetryable: true,
    message: 'The Face Liveness session timed out.',
    recoverySuggestion: 'Retry with a new session.',
  ),

  /// The face did not fit the oval in time.
  faceFitTimedOut(
    LivenessErrorCategory.timeout,
    isRetryable: true,
    message: 'The face did not fit the oval in time.',
    recoverySuggestion:
        'Ask the user to move closer and center the face, then retry.',
  ),

  /// Anything not mapped to another code; see [LivenessError.nativeDetails].
  unknown(
    LivenessErrorCategory.unknown,
    isRetryable: true,
    message: 'An unknown liveness error occurred.',
    recoverySuggestion:
        'Retry with a new session and check LivenessError.nativeDetails.',
  );

  const LivenessErrorCode(
    this.category, {
    required this.isRetryable,
    required this.message,
    required this.recoverySuggestion,
  });

  /// The group this code belongs to.
  final LivenessErrorCategory category;

  /// Whether a new attempt, with a new session, may succeed without any code
  /// or configuration change.
  final bool isRetryable;

  /// Default English, developer-facing description.
  final String message;

  /// Default English, developer-facing next step.
  final String recoverySuggestion;
}

/// Platform that reported [LivenessNativeDetails].
enum LivenessPlatform {
  /// Android.
  android,

  /// iOS.
  ios,
}

/// Raw details from the native side, for logs and bug reports.
final class LivenessNativeDetails {
  /// Creates native details.
  const LivenessNativeDetails({
    required this.platform,
    this.code,
    this.message,
  });

  /// The platform that reported the error.
  final LivenessPlatform platform;

  /// Native exception class or error case name.
  final String? code;

  /// Native message. Never contains credentials.
  final String? message;

  @override
  String toString() =>
      'LivenessNativeDetails(platform: ${platform.name}, code: $code, '
      'message: $message)';
}

/// A typed liveness failure, delivered in `LivenessFailed.error`.
final class LivenessError implements Exception {
  /// Creates an error for [code]. [message] overrides the code's default text.
  LivenessError(this.code, {String? message, this.nativeDetails, this.cause})
    : message = message ?? code.message,
      recoverySuggestion = code.recoverySuggestion;

  /// The stable error code.
  final LivenessErrorCode code;

  /// English, developer-facing description.
  final String message;

  /// English, developer-facing next step.
  final String recoverySuggestion;

  /// Raw native details, when the error came from the native side.
  final LivenessNativeDetails? nativeDetails;

  /// Dart-side cause, for example the exception thrown by the credentials
  /// provider. Never sent across the channel and not included in [toString].
  final Object? cause;

  /// The group of [code].
  LivenessErrorCategory get category => code.category;

  /// Whether a new attempt, with a new session, may succeed.
  bool get isRetryable => code.isRetryable;

  @override
  String toString() {
    final details = nativeDetails == null ? '' : ', $nativeDetails';
    return 'LivenessError(${code.name}: $message$details)';
  }
}
