import 'package:flutter/foundation.dart';

import 'liveness_controller.dart';
import 'models/availability.dart';
import 'models/request.dart';
import 'models/result.dart';
import 'wire_converters.dart';

LivenessController? _controller;

LivenessController get _instance =>
    _controller ??= LivenessController.forCurrentPlatform();

/// Replaces the controller behind [AwsLiveness]; `null` restores the default.
/// Not exported from the package.
@visibleForTesting
set debugLivenessController(LivenessController? controller) =>
    _controller = controller;

/// Runs Amazon Rekognition Face Liveness checks with the native AWS Amplify
/// UI on Android and iOS.
///
/// Your backend creates the session with `CreateFaceLivenessSession`, the app
/// runs the check with [start], and your backend reads the verdict with
/// `GetFaceLivenessSessionResults`. The plugin never decides whether the user
/// is live.
abstract final class AwsLiveness {
  /// Regions with a Rekognition streaming endpoint for Face Liveness, as of
  /// 2026-10-15. Informational only: [start] does not reject other regions.
  ///
  /// See https://docs.aws.amazon.com/general/latest/gr/rekognition.html.
  static const List<String> knownSupportedRegions = <String>[
    'us-east-1',
    'us-west-2',
    'ap-south-1',
    'ap-northeast-1',
    'eu-west-1',
    'sa-east-1',
    'ap-southeast-5',
    'ap-southeast-7',
  ];

  /// Shows the native liveness UI and completes with the outcome.
  ///
  /// Asks for the camera permission when needed. The returned future
  /// completes exactly once and never completes with an error: runtime
  /// failures are [LivenessFailed] results.
  ///
  /// Throws [ArgumentError] synchronously if `sessionId` is blank, `region` is
  /// not a region code such as `eu-west-1`, or a timeout is not positive.
  /// Throws [StateError] synchronously while an earlier attempt from this
  /// isolate is still active (see [isActive]).
  static Future<LivenessResult> start(LivenessRequest request) =>
      _instance.start(request);

  /// Ends the active attempt; its [start] future completes with
  /// [LivenessCancelled] and [LivenessCancelReason.app]. No-op when idle;
  /// never throws.
  static Future<void> cancel() => _instance.cancel();

  /// True from a [start] call until its future completes.
  static bool get isActive => _instance.isActive;

  /// Reports whether liveness can run in this build and on this device:
  /// native SDK linked, a camera present and, on iOS,
  /// `NSCameraUsageDescription` set. Never prompts the user.
  static Future<LivenessAvailability> checkAvailability() async {
    try {
      return toAvailability(await _instance.hostApi.checkAvailability());
    } catch (error) {
      if (!isPluginMissing(error)) rethrow;
      return const LivenessAvailability(
        isAvailable: false,
        reason: LivenessUnavailableReason.sdkUnavailable,
      );
    }
  }

  /// Reads the camera permission without prompting.
  ///
  /// On Android this may report [CameraPermissionStatus.notDetermined] for a
  /// permanent denial until the permission has been requested once.
  static Future<CameraPermissionStatus> getCameraPermissionStatus() async =>
      toPermissionStatus(await _instance.hostApi.getCameraPermissionStatus());

  /// Requests the camera permission, for apps that show their own rationale
  /// before [start]. [start] performs the same request itself.
  static Future<CameraPermissionStatus> requestCameraPermission() async =>
      toPermissionStatus(await _instance.hostApi.requestCameraPermission());

  /// Opens this app's page in the system settings, for example after
  /// [CameraPermissionStatus.permanentlyDenied]. Returns whether it opened.
  static Future<bool> openAppSettings() => _instance.hostApi.openAppSettings();
}
