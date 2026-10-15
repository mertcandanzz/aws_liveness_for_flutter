import Foundation

/// What the native UI reports back for one attempt. All closures run on the main actor.
struct LivenessEvents {
  /// The SDK reported success.
  let completed: @MainActor () -> Void
  /// The SDK reported an error.
  let failed: @MainActor (SdkError) -> Void
  /// The UI went away without an SDK result: app backgrounded, dismissed by someone else.
  let interrupted: @MainActor (_ nativeCode: String) -> Void
}

/// Shows the FaceLiveness UI for an attempt.
@MainActor
protocol LivenessPresenting: AnyObject {
  /// Presents the UI and sets `attempt.closeUI`. Returns false when no view controller is in
  /// the foreground; the UI is then not created at all.
  func present(_ attempt: ActiveAttempt, credentials: CredentialsBroker, events: LivenessEvents)
    -> Bool
}

/// Opens this app's page in the Settings app.
@MainActor
protocol SettingsOpening: AnyObject {
  func open(_ completion: @escaping @MainActor (Bool) -> Void)
}

/// The iOS host for one Flutter engine (design §6, §8). Platform-free: UIKit, AVFoundation
/// and FaceLiveness come in through the protocols above, so XCTest drives it with fakes.
@MainActor
final class LivenessHost {
  struct SdkStatus {
    var isLinked: Bool
    /// Evaluated on first use, not at engine registration: it scans the app bundle.
    var isFaceDetectorModelBundled: () -> Bool
  }

  private let engine: AnyObject
  private let sessions: SessionCoordinator
  private let sdk: SdkStatus
  private let permission: CameraPermission
  private let presenter: LivenessPresenting
  private let settings: SettingsOpening
  private let fetcher: CredentialsFetcher
  private let scheduler: Scheduler

  init(
    engine: AnyObject,
    sessions: SessionCoordinator,
    sdk: SdkStatus,
    camera: CameraAccess,
    presenter: LivenessPresenting,
    settings: SettingsOpening,
    fetcher: @escaping CredentialsFetcher,
    scheduler: Scheduler
  ) {
    self.engine = engine
    self.sessions = sessions
    self.sdk = sdk
    self.permission = CameraPermission(camera: camera)
    self.presenter = presenter
    self.settings = settings
    self.fetcher = fetcher
    self.scheduler = scheduler
  }

  func checkAvailability() -> AvailabilityMessage {
    if !sdk.isLinked || !sdk.isFaceDetectorModelBundled() {
      return AvailabilityMessage(isAvailable: false, reason: .sdkUnavailable)
    }
    if !permission.hasUsageDescription {
      return AvailabilityMessage(isAvailable: false, reason: .missingCameraUsageDescription)
    }
    if !permission.camera.hasVideoDevice {
      return AvailabilityMessage(isAvailable: false, reason: .noCamera)
    }
    return AvailabilityMessage(isAvailable: true)
  }

  /// Replies exactly once (design §5): availability and slot checks, the camera permission
  /// pre-check, then the native UI.
  func start(_ request: StartRequestMessage, reply: @escaping (OutcomeMessage) -> Void) {
    if let unavailable = sdkUnavailableOutcome() {
      reply(unavailable)
      return
    }
    guard let attempt = sessions.begin(engine: engine, request: request, deliver: reply) else {
      reply(Outcomes.failed(.alreadyActive))
      return
    }
    permission.ensureAccess { [weak self] error in
      // Cancelled, timed out or detached during the prompt: skip presentation.
      guard let self = self, !attempt.isFinished else {
        return
      }
      if let error = error {
        self.sessions.finish(attempt, with: Outcomes.failed(error))
        return
      }
      self.present(attempt)
    }
  }

  func cancel(attemptId: Int64, reason: CancelRequestReasonMessage) {
    guard let attempt = sessions.attempt(engine: engine, attemptId: attemptId) else {
      return
    }
    sessions.end(attempt, with: Outcomes.forCancelRequest(reason))
  }

  func cameraPermissionStatus() -> CameraPermissionStatusMessage {
    permission.status()
  }

  func requestCameraPermission(_ reply: @escaping @MainActor (CameraPermissionStatusMessage) -> Void) {
    permission.request(reply)
  }

  func openAppSettings(_ reply: @escaping @MainActor (Bool) -> Void) {
    settings.open(reply)
  }

  /// The engine is detaching: drop its attempt and close the UI (design §6.9).
  func dispose() {
    sessions.detach(engine: engine)
  }

  private func sdkUnavailableOutcome() -> OutcomeMessage? {
    if !sdk.isLinked {
      return Outcomes.failed(
        .sdkUnavailable, nativeCode: "FaceLivenessNotLinked",
        nativeMessage: "This build does not include the FaceLiveness Swift package.")
    }
    if !sdk.isFaceDetectorModelBundled() {
      return Outcomes.failed(
        .sdkUnavailable, nativeCode: "FaceDetectorModelNotFound",
        nativeMessage: "The app bundle does not contain \(LivenessSDK.faceDetectorModelName).")
    }
    return nil
  }

  private func present(_ attempt: ActiveAttempt) {
    guard permission.camera.hasVideoDevice else {
      sessions.finish(attempt, with: Outcomes.failed(.cameraUnavailable, nativeCode: "NoVideoDevice"))
      return
    }
    let credentials = CredentialsBroker(attempt: attempt, fetcher: fetcher, scheduler: scheduler)
    let presented = presenter.present(attempt, credentials: credentials, events: events(for: attempt))
    if !presented {
      sessions.end(
        attempt, with: Outcomes.failed(.presenterUnavailable, nativeCode: "NoForegroundViewController"))
    }
  }

  private func events(for attempt: ActiveAttempt) -> LivenessEvents {
    let sessions = self.sessions
    let permission = self.permission
    return LivenessEvents(
      completed: {
        sessions.finish(attempt, with: Outcomes.completed())
      },
      failed: { error in
        let outcome = ErrorMapper.map(
          error,
          pluginEnd: attempt.pluginEnd,
          credentialsFailed: attempt.credentialsFailed,
          permissionStatus: { permission.status() })
        sessions.finish(attempt, with: outcome)
      },
      interrupted: { nativeCode in
        sessions.end(attempt, with: Outcomes.failed(.sessionInterrupted, nativeCode: nativeCode))
      })
  }
}
