import Foundation

/// A `FaceLivenessDetectionError` reduced to plain values, so the mapping compiles and is
/// tested without the FaceLiveness package (CocoaPods builds, Linux checks).
///
/// `code` is the SDK's error code (0–19 in amplify-ui-swift-liveness 1.5.1), or -1 when the
/// error matches none of the known cases.
struct SdkError: Equatable {
  let code: Int
  let message: String
}

/// Maps a FaceLiveness error to the wire outcome (design §4.2 and §4.4).
enum ErrorMapper {
  /// `FaceLivenessDetectionError` case names, indexed by the SDK's error code.
  static let caseNames: [String] = [
    "unknown",
    "sessionNotFound",
    "sessionTimedOut",
    "faceInOvalMatchExceededTimeLimitError",
    "accessDenied",
    "cameraPermissionDenied",
    "userCancelled",
    "socketClosed",
    "countdownFaceTooClose",
    "countdownMultipleFaces",
    "countdownNoFace",
    "invalidRegion",
    "validation",
    "internalServer",
    "throttling",
    "serviceQuotaExceeded",
    "serviceUnavailable",
    "invalidSignature",
    "cameraNotAvailable",
    "sessionInterrupted",
  ]

  static let userCancelledCode = 6

  /// - Parameters:
  ///   - pluginEnd: the result of a plugin-initiated end that already started (rule 2).
  ///   - credentialsFailed: whether our credentials provider failed for this attempt (rule 3).
  ///   - permissionStatus: re-reads the camera permission; only called for a permission error.
  static func map(
    _ error: SdkError,
    pluginEnd: OutcomeMessage?,
    credentialsFailed: Bool,
    permissionStatus: () -> CameraPermissionStatusMessage
  ) -> OutcomeMessage {
    if let pluginEnd = pluginEnd {
      return pluginEnd
    }
    if error.code == userCancelledCode {
      return Outcomes.cancelled(.user)
    }
    let code: ErrorCodeMessage
    if credentialsFailed {
      // iOS reports a failing provider as socketClosed; only the plugin knows the cause.
      code = .credentialsUnavailable
    } else {
      code = errorCode(for: error.code, permissionStatus: permissionStatus)
    }
    return Outcomes.failed(code, nativeCode: caseName(for: error.code), nativeMessage: error.message)
  }

  /// The design §4.4 table, without the user-cancel and credentials rules.
  static func errorCode(
    for sdkCode: Int,
    permissionStatus: () -> CameraPermissionStatusMessage
  ) -> ErrorCodeMessage {
    switch sdkCode {
    case 1: return .sessionNotFound
    case 2: return .sessionTimedOut
    case 3: return .faceFitTimedOut
    case 4: return .accessDenied
    case 5:
      switch permissionStatus() {
      case .permanentlyDenied, .restricted:
        return .cameraPermissionPermanentlyDenied
      case .granted, .notDetermined, .denied:
        return .cameraPermissionDenied
      }
    case 7: return .sessionInterrupted
    case 8: return .faceTooClose
    case 9: return .multipleFaces
    case 10: return .noFaceDetected
    case 11: return .invalidRegion
    case 12: return .validation
    case 13: return .internalServerError
    case 14, 15: return .throttled
    case 16: return .serviceUnavailable
    case 17: return .invalidSignature
    case 18: return .cameraUnavailable
    case 19: return .sessionInterrupted
    default: return .unknown
    }
  }

  /// For example `sessionNotFound`, or `FaceLivenessDetectionError(42)` for an unknown code.
  static func caseName(for sdkCode: Int) -> String {
    guard caseNames.indices.contains(sdkCode) else {
      return "FaceLivenessDetectionError(\(sdkCode))"
    }
    return caseNames[sdkCode]
  }
}
