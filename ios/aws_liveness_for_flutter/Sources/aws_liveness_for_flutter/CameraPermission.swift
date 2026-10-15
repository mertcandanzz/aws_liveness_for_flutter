import Foundation

/// `AVAuthorizationStatus` for video, without AVFoundation so the logic is testable anywhere.
enum CameraAuthorization {
  case notDetermined
  case restricted
  case denied
  case authorized
}

/// The device camera and the app's camera permission; tests use a fake.
@MainActor
protocol CameraAccess: AnyObject {
  var authorization: CameraAuthorization { get }
  /// Whether the device has any video camera (the simulator has none).
  var hasVideoDevice: Bool { get }
  /// The app's `NSCameraUsageDescription`, if any.
  var usageDescription: String? { get }
  /// Shows the system prompt. Only called when [usageDescription] is set.
  func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void)
}

/// Camera permission rules shared by `start` and the permission helpers (design §3.5, §6.6).
@MainActor
struct CameraPermission {
  let camera: CameraAccess

  nonisolated static func status(for authorization: CameraAuthorization)
    -> CameraPermissionStatusMessage
  {
    switch authorization {
    case .authorized:
      return .granted
    case .notDetermined:
      return .notDetermined
    // iOS cannot prompt again after a denial; only the Settings app helps.
    case .denied:
      return .permanentlyDenied
    case .restricted:
      return .restricted
    }
  }

  /// `requestAccess` crashes the app when `NSCameraUsageDescription` is missing.
  var hasUsageDescription: Bool {
    guard let description = camera.usageDescription else {
      return false
    }
    return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func status() -> CameraPermissionStatusMessage {
    Self.status(for: camera.authorization)
  }

  /// The permission helper: prompts only when the status is undetermined and the usage
  /// description is set, then reports the new status.
  func request(_ completion: @escaping @MainActor (CameraPermissionStatusMessage) -> Void) {
    guard camera.authorization == .notDetermined, hasUsageDescription else {
      completion(status())
      return
    }
    let camera = self.camera
    camera.requestAccess { _ in
      completion(Self.status(for: camera.authorization))
    }
  }

  /// The pre-check before the liveness UI: nil when the camera may be used, otherwise the
  /// error to report. Prompts when the status is undetermined.
  func ensureAccess(_ completion: @escaping @MainActor (ErrorCodeMessage?) -> Void) {
    guard hasUsageDescription else {
      completion(.missingCameraUsageDescription)
      return
    }
    switch camera.authorization {
    case .authorized:
      completion(nil)
    case .denied, .restricted:
      completion(.cameraPermissionPermanentlyDenied)
    case .notDetermined:
      camera.requestAccess { granted in
        completion(granted ? nil : .cameraPermissionPermanentlyDenied)
      }
    }
  }
}
