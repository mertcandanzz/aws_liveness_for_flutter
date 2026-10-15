// Pigeon contract between the Dart API and the native hosts.
//
// Regenerate after editing (from the package root):
//   dart run pigeon --input pigeons/messages.dart
//   dart format lib/src/messages.g.dart
//
// Generated files are committed; never edit them by hand.
//
// Security: CredentialsMessage carries temporary AWS credentials. Never log or
// print it (generated toString/description include all fields) and drop every
// reference once the native SDK has received the credentials.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'aws_liveness_for_flutter',
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/io/github/mertcandanzz/aws_liveness_for_flutter/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'io.github.mertcandanzz.aws_liveness_for_flutter',
      errorClassName: 'AwsLivenessFlutterError',
    ),
    swiftOut:
        'ios/aws_liveness_for_flutter/Sources/aws_liveness_for_flutter/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AwsLivenessPigeonError'),
  ),
)
/// Camera used by the FaceMovement challenge. FaceMovementAndLight is always
/// front-facing.
enum CameraMessage { front, back }

/// Light/dark selection for the native liveness UI.
enum ThemeModeMessage { system, light, dark }

/// Colour overrides as ARGB32 integers. A null field keeps the SDK default.
class ColorsMessage {
  ColorsMessage({
    this.primary,
    this.onPrimary,
    this.background,
    this.onBackground,
    this.surface,
    this.error,
    this.onError,
    this.errorContainer,
    this.onErrorContainer,
  });

  int? primary;
  int? onPrimary;
  int? background;
  int? onBackground;
  int? surface;
  int? error;
  int? onError;
  int? errorContainer;
  int? onErrorContainer;
}

/// Theme for the native liveness UI.
class ThemeMessage {
  ThemeMessage({required this.mode, this.light, this.dark});

  ThemeModeMessage mode;
  ColorsMessage? light;
  ColorsMessage? dark;
}

/// Everything the native host needs to run one liveness attempt.
class StartRequestMessage {
  StartRequestMessage({
    required this.attemptId,
    required this.sessionId,
    required this.region,
    required this.faceMovementCamera,
    required this.showStartView,
    required this.theme,
    required this.credentialsTimeoutMillis,
  });

  /// Dart-generated, increasing per start. Echoed by fetchCredentials and
  /// targeted by cancel.
  int attemptId;
  String sessionId;
  String region;
  CameraMessage faceMovementCamera;
  bool showStartView;
  ThemeMessage theme;

  /// Dart enforces this limit; native fails the credential request after this
  /// value + 5000 ms without a reply.
  int credentialsTimeoutMillis;
}

/// Why Dart asks the native host to end an attempt.
enum CancelRequestReasonMessage { app, timeout }

/// Who cancelled a finished attempt.
enum CancelReasonMessage { user, app }

/// Kind of a finished attempt.
enum OutcomeKindMessage { completed, cancelled, failed }

/// Wire mirror of the public LivenessErrorCode. Append-only: names and order
/// must match LivenessErrorCode exactly (enforced by a Dart test).
enum ErrorCodeMessage {
  cameraPermissionDenied,
  cameraPermissionPermanentlyDenied,
  credentialsUnavailable,
  accessDenied,
  invalidSignature,
  sessionNotFound,
  invalidRegion,
  validation,
  unsupportedChallenge,
  sdkUnavailable,
  missingCameraUsageDescription,
  throttled,
  serviceUnavailable,
  internalServerError,
  sessionInterrupted,
  faceTooClose,
  multipleFaces,
  noFaceDetected,
  cameraUnavailable,
  videoEncodingFailed,
  presenterUnavailable,
  alreadyActive,
  timedOut,
  sessionTimedOut,
  faceFitTimedOut,
  unknown,
}

/// Result of one attempt, delivered exactly once per start call.
///
/// completed: no other field set. cancelled: cancelReason set. failed:
/// errorCode set; nativeCode/nativeMessage optional and never contain
/// credentials.
class OutcomeMessage {
  OutcomeMessage({
    required this.kind,
    this.cancelReason,
    this.errorCode,
    this.nativeCode,
    this.nativeMessage,
  });

  OutcomeKindMessage kind;
  CancelReasonMessage? cancelReason;
  ErrorCodeMessage? errorCode;
  String? nativeCode;
  String? nativeMessage;
}

/// Why liveness cannot run in this build or on this device.
enum UnavailableReasonMessage {
  sdkUnavailable,
  noCamera,
  missingCameraUsageDescription,
}

/// Result of checkAvailability.
class AvailabilityMessage {
  AvailabilityMessage({required this.isAvailable, this.reason});

  bool isAvailable;
  UnavailableReasonMessage? reason;
}

/// Camera permission state. denied is Android-only (can ask again);
/// restricted is iOS-only.
enum CameraPermissionStatusMessage {
  granted,
  notDetermined,
  denied,
  permanentlyDenied,
  restricted,
}

/// Temporary AWS credentials scoped to rekognition:StartFaceLivenessSession.
/// Sensitive: never log, print or persist.
class CredentialsMessage {
  CredentialsMessage({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expirationEpochSeconds,
  });

  String accessKeyId;
  String secretAccessKey;
  String sessionToken;
  int expirationEpochSeconds;
}

/// Why Dart could not supply credentials.
enum CredentialsFailureMessage {
  providerError,
  timedOut,
  invalid,
  staleAttempt,
}

/// Exactly one of credentials or failure is non-null. Native treats any other
/// combination as a failure.
class CredentialsResultMessage {
  CredentialsResultMessage({this.credentials, this.failure});

  CredentialsMessage? credentials;
  CredentialsFailureMessage? failure;
}

/// Implemented natively, called from Dart.
@HostApi()
abstract class LivenessHostApi {
  /// Native SDK linked, camera present, iOS NSCameraUsageDescription set.
  AvailabilityMessage checkAvailability();

  /// Runs one attempt: permission pre-check, native UI, result. Replies
  /// exactly once and never with a channel error for runtime failures.
  @async
  OutcomeMessage start(StartRequestMessage request);

  /// Ends attempt [attemptId] if it is still active; otherwise no-op.
  void cancel(int attemptId, CancelRequestReasonMessage reason);

  CameraPermissionStatusMessage getCameraPermissionStatus();

  @async
  CameraPermissionStatusMessage requestCameraPermission();

  /// Opens this app's system settings page. Returns whether it was opened.
  @async
  bool openAppSettings();
}

/// Implemented in Dart, called from native code.
@FlutterApi()
abstract class LivenessFlutterApi {
  /// Called each time the native SDK needs credentials for [attemptId].
  /// Never replies with a channel error; failures are values.
  @async
  CredentialsResultMessage fetchCredentials(int attemptId);
}
