import 'package:flutter/services.dart';

import 'messages.g.dart';
import 'models/availability.dart';
import 'models/error.dart';
import 'models/request.dart';
import 'models/result.dart';
import 'models/theme.dart';

/// Pigeon's error code when no native handler answers a channel.
const _channelErrorCode = 'channel-error';

/// Builds the wire request for one attempt.
StartRequestMessage toStartRequestMessage(
  LivenessRequest request, {
  required int attemptId,
}) => StartRequestMessage(
  attemptId: attemptId,
  sessionId: request.sessionId,
  region: request.region,
  faceMovementCamera: switch (request.challengeOptions.faceMovementCamera) {
    LivenessCamera.front => CameraMessage.front,
    LivenessCamera.back => CameraMessage.back,
  },
  showStartView: request.showStartView,
  theme: toThemeMessage(request.theme),
  credentialsTimeoutMillis: request.credentialsTimeout.inMilliseconds,
);

/// Converts the theme; colours become ARGB32 integers.
ThemeMessage toThemeMessage(LivenessTheme theme) => ThemeMessage(
  mode: switch (theme.mode) {
    LivenessThemeMode.system => ThemeModeMessage.system,
    LivenessThemeMode.light => ThemeModeMessage.light,
    LivenessThemeMode.dark => ThemeModeMessage.dark,
  },
  light: _toColorsMessage(theme.light),
  dark: _toColorsMessage(theme.dark),
);

ColorsMessage? _toColorsMessage(LivenessColors? colors) {
  if (colors == null) return null;
  return ColorsMessage(
    primary: _argb(colors.primary),
    onPrimary: _argb(colors.onPrimary),
    background: _argb(colors.background),
    onBackground: _argb(colors.onBackground),
    surface: _argb(colors.surface),
    error: _argb(colors.error),
    onError: _argb(colors.onError),
    errorContainer: _argb(colors.errorContainer),
    onErrorContainer: _argb(colors.onErrorContainer),
  );
}

int? _argb(Color? color) => color?.toARGB32();

/// Converts credentials for the reply to a native credential request.
CredentialsMessage toCredentialsMessage(LivenessCredentials credentials) =>
    CredentialsMessage(
      accessKeyId: credentials.accessKeyId,
      secretAccessKey: credentials.secretAccessKey,
      sessionToken: credentials.sessionToken,
      expirationEpochSeconds:
          credentials.expiration.millisecondsSinceEpoch ~/ 1000,
    );

/// Converts the native outcome of an attempt.
///
/// A cancel without a reason is treated as a user cancel and a failure
/// without a code as [LivenessErrorCode.unknown].
LivenessResult toLivenessResult(
  OutcomeMessage outcome, {
  required String sessionId,
  required LivenessPlatform platform,
}) {
  switch (outcome.kind) {
    case OutcomeKindMessage.completed:
      return LivenessCompleted(sessionId: sessionId);
    case OutcomeKindMessage.cancelled:
      return LivenessCancelled(
        sessionId: sessionId,
        reason: outcome.cancelReason == CancelReasonMessage.app
            ? LivenessCancelReason.app
            : LivenessCancelReason.user,
      );
    case OutcomeKindMessage.failed:
      final hasDetails =
          outcome.nativeCode != null || outcome.nativeMessage != null;
      return LivenessFailed(
        sessionId: sessionId,
        error: LivenessError(
          toErrorCode(outcome.errorCode ?? ErrorCodeMessage.unknown),
          nativeDetails: hasDetails
              ? LivenessNativeDetails(
                  platform: platform,
                  code: outcome.nativeCode,
                  message: outcome.nativeMessage,
                )
              : null,
        ),
      );
  }
}

/// Maps the wire error code to the public code with the same name.
LivenessErrorCode toErrorCode(ErrorCodeMessage code) =>
    LivenessErrorCode.values.byName(code.name);

/// Converts the native availability report.
LivenessAvailability toAvailability(AvailabilityMessage message) =>
    LivenessAvailability(
      isAvailable: message.isAvailable,
      reason: switch (message.reason) {
        null => null,
        UnavailableReasonMessage.sdkUnavailable =>
          LivenessUnavailableReason.sdkUnavailable,
        UnavailableReasonMessage.noCamera => LivenessUnavailableReason.noCamera,
        UnavailableReasonMessage.missingCameraUsageDescription =>
          LivenessUnavailableReason.missingCameraUsageDescription,
      },
    );

/// Converts the native camera permission status.
CameraPermissionStatus toPermissionStatus(
  CameraPermissionStatusMessage status,
) => switch (status) {
  CameraPermissionStatusMessage.granted => CameraPermissionStatus.granted,
  CameraPermissionStatusMessage.notDetermined =>
    CameraPermissionStatus.notDetermined,
  CameraPermissionStatusMessage.denied => CameraPermissionStatus.denied,
  CameraPermissionStatusMessage.permanentlyDenied =>
    CameraPermissionStatus.permanentlyDenied,
  CameraPermissionStatusMessage.restricted => CameraPermissionStatus.restricted,
};

/// Whether [error] means no native implementation answered: an unsupported
/// platform or an unregistered plugin. Pigeon reports this as a
/// `channel-error` [PlatformException].
bool isPluginMissing(Object error) =>
    error is MissingPluginException ||
    (error is PlatformException && error.code == _channelErrorCode);

/// Converts a failed channel call into a typed error (design §4.5).
LivenessError toChannelError(
  Object error, {
  required LivenessPlatform platform,
}) {
  if (isPluginMissing(error)) {
    return LivenessError(LivenessErrorCode.sdkUnavailable, cause: error);
  }
  if (error is PlatformException) {
    return LivenessError(
      LivenessErrorCode.unknown,
      nativeDetails: LivenessNativeDetails(
        platform: platform,
        code: error.code,
        message: error.message,
      ),
      cause: error,
    );
  }
  return LivenessError(LivenessErrorCode.unknown, cause: error);
}
