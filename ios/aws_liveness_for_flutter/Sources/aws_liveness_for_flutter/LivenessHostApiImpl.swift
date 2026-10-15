import Flutter
import Foundation

/// iOS side of `LivenessHostApi` for one Flutter engine.
///
/// Pigeon calls these handlers on the platform (main) thread, so each one enters the main
/// actor with `assumeIsolated` and forwards to [LivenessHost]. Runtime failures are replied
/// as values, never as channel errors (design §4.5); nothing here throws.
final class LivenessHostApiImpl: LivenessHostApi {
  private let host: LivenessHost

  init(host: LivenessHost) {
    self.host = host
  }

  func checkAvailability() throws -> AvailabilityMessage {
    MainActor.assumeIsolated {
      host.checkAvailability()
    }
  }

  func start(
    request: StartRequestMessage, completion: @escaping (Result<OutcomeMessage, Error>) -> Void
  ) {
    MainActor.assumeIsolated {
      host.start(request) { outcome in
        completion(.success(outcome))
      }
    }
  }

  func cancel(attemptId: Int64, reason: CancelRequestReasonMessage) throws {
    MainActor.assumeIsolated {
      host.cancel(attemptId: attemptId, reason: reason)
    }
  }

  func getCameraPermissionStatus() throws -> CameraPermissionStatusMessage {
    MainActor.assumeIsolated {
      host.cameraPermissionStatus()
    }
  }

  func requestCameraPermission(
    completion: @escaping (Result<CameraPermissionStatusMessage, Error>) -> Void
  ) {
    MainActor.assumeIsolated {
      host.requestCameraPermission { status in
        completion(.success(status))
      }
    }
  }

  func openAppSettings(completion: @escaping (Result<Bool, Error>) -> Void) {
    MainActor.assumeIsolated {
      host.openAppSettings { opened in
        completion(.success(opened))
      }
    }
  }
}
