/// Whether liveness can run in this build and on this device.
final class LivenessAvailability {
  /// Creates an availability report.
  const LivenessAvailability({required this.isAvailable, this.reason});

  /// True when the native SDK is linked and the device can run a check.
  final bool isAvailable;

  /// Why liveness is unavailable; null when [isAvailable] is true.
  final LivenessUnavailableReason? reason;

  @override
  String toString() =>
      'LivenessAvailability(isAvailable: $isAvailable, reason: ${reason?.name})';
}

/// Why liveness cannot run.
enum LivenessUnavailableReason {
  /// The native SDK is not linked: an iOS build that uses CocoaPods instead of
  /// Swift Package Manager, or an unsupported platform.
  sdkUnavailable,

  /// The device has no usable camera.
  noCamera,

  /// The iOS app's `Info.plist` has no `NSCameraUsageDescription`.
  missingCameraUsageDescription,
}

/// Camera permission state as reported by the platform.
enum CameraPermissionStatus {
  /// The app may use the camera.
  granted,

  /// The user has not been asked yet. On Android this may also mean a
  /// permanent denial until the permission is requested once.
  notDetermined,

  /// Android only: the user denied the permission; the app may ask again.
  denied,

  /// The permission can only be changed in the system settings; see
  /// `AwsLiveness.openAppSettings`. On iOS every denial is permanent.
  permanentlyDenied,

  /// iOS only: blocked by parental controls or device management.
  restricted,
}
