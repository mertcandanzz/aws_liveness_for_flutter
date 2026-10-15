import Foundation
import XCTest

@testable import aws_liveness_for_flutter

// Unit tests for the iOS host (design §11.3). Everything here runs without a camera, a
// FaceLiveness session or UIKit: the host talks to fakes through its protocols.

// MARK: - ErrorMapper

final class ErrorMapperTests: XCTestCase {
  private func map(
    _ code: Int,
    pluginEnd: OutcomeMessage? = nil,
    credentialsFailed: Bool = false,
    permission: CameraPermissionStatusMessage = .granted
  ) -> OutcomeMessage {
    ErrorMapper.map(
      SdkError(code: code, message: "sdk message"),
      pluginEnd: pluginEnd,
      credentialsFailed: credentialsFailed,
      permissionStatus: { permission })
  }

  func testMapsEverySdkCodeToTheDesignTable() {
    let expected: [Int: ErrorCodeMessage] = [
      0: .unknown, 1: .sessionNotFound, 2: .sessionTimedOut, 3: .faceFitTimedOut,
      4: .accessDenied, 7: .sessionInterrupted, 8: .faceTooClose, 9: .multipleFaces,
      10: .noFaceDetected, 11: .invalidRegion, 12: .validation, 13: .internalServerError,
      14: .throttled, 15: .throttled, 16: .serviceUnavailable, 17: .invalidSignature,
      18: .cameraUnavailable, 19: .sessionInterrupted,
    ]
    for (code, errorCode) in expected {
      let outcome = map(code)
      XCTAssertEqual(outcome.kind, .failed, "code \(code)")
      XCTAssertEqual(outcome.errorCode, errorCode, "code \(code)")
      XCTAssertEqual(outcome.nativeCode, ErrorMapper.caseNames[code], "code \(code)")
      XCTAssertEqual(outcome.nativeMessage, "sdk message", "code \(code)")
    }
  }

  func testCaseNamesCoverCodesZeroToNineteen() {
    XCTAssertEqual(ErrorMapper.caseNames.count, 20)
    XCTAssertEqual(ErrorMapper.caseNames[ErrorMapper.userCancelledCode], "userCancelled")
  }

  func testUserCancelIsCancelledByUserEvenAfterACredentialsFailure() {
    XCTAssertEqual(map(6), Outcomes.cancelled(.user))
    XCTAssertEqual(map(6, credentialsFailed: true), Outcomes.cancelled(.user))
  }

  func testUnknownCodesMapToUnknownWithTheRawCode() {
    for code in [-1, 20, 99] {
      let outcome = map(code)
      XCTAssertEqual(outcome.errorCode, .unknown)
      XCTAssertEqual(outcome.nativeCode, "FaceLivenessDetectionError(\(code))")
    }
  }

  func testCredentialsFailureTakesPrecedenceOverTheSdkError() {
    XCTAssertEqual(map(7, credentialsFailed: true).errorCode, .credentialsUnavailable)
    XCTAssertEqual(map(4, credentialsFailed: true).errorCode, .credentialsUnavailable)
    XCTAssertEqual(map(7, credentialsFailed: true).nativeCode, "socketClosed")
  }

  func testPluginEndTakesPrecedenceOverEverything() {
    let timedOut = Outcomes.failed(.timedOut)
    XCTAssertEqual(map(7, pluginEnd: timedOut, credentialsFailed: true), timedOut)
    XCTAssertEqual(map(6, pluginEnd: Outcomes.cancelled(.app)), Outcomes.cancelled(.app))
  }

  func testCameraPermissionErrorRereadsThePermission() {
    XCTAssertEqual(
      map(5, permission: .permanentlyDenied).errorCode, .cameraPermissionPermanentlyDenied)
    XCTAssertEqual(map(5, permission: .restricted).errorCode, .cameraPermissionPermanentlyDenied)
    XCTAssertEqual(map(5, permission: .notDetermined).errorCode, .cameraPermissionDenied)
    XCTAssertEqual(map(5, permission: .granted).errorCode, .cameraPermissionDenied)
  }

  func testPermissionIsOnlyReadForPermissionErrors() {
    var reads = 0
    _ = ErrorMapper.map(
      SdkError(code: 1, message: ""), pluginEnd: nil, credentialsFailed: false,
      permissionStatus: {
        reads += 1
        return .granted
      })
    XCTAssertEqual(reads, 0)
  }
}

// MARK: - SessionCoordinator

final class SessionCoordinatorTests: XCTestCase {
  @MainActor
  func testFinishDeliversExactlyOnce() async {
    let sessions = SessionCoordinator(scheduler: ManualScheduler())
    var outcomes: [OutcomeMessage] = []
    let attempt = sessions.begin(engine: Engine(), request: makeRequest()) { outcomes.append($0) }

    XCTAssertTrue(sessions.finish(XCTUnwrapAttempt(attempt), with: Outcomes.completed()))
    XCTAssertFalse(sessions.finish(XCTUnwrapAttempt(attempt), with: Outcomes.failed(.unknown)))

    XCTAssertEqual(outcomes, [Outcomes.completed()])
    XCTAssertNil(sessions.active)
  }

  @MainActor
  func testSlotIsProcessWideAndReleasedOnDelivery() async {
    let sessions = SessionCoordinator(scheduler: ManualScheduler())
    let first = sessions.begin(engine: Engine(), request: makeRequest()) { _ in }

    XCTAssertNil(sessions.begin(engine: Engine(), request: makeRequest()) { _ in })

    sessions.finish(XCTUnwrapAttempt(first), with: Outcomes.completed())
    XCTAssertNotNil(sessions.begin(engine: Engine(), request: makeRequest(attemptId: 2)) { _ in })
  }

  @MainActor
  func testDeliveryWaitsForTheUiToClose() async {
    let sessions = SessionCoordinator(scheduler: ManualScheduler())
    var outcomes: [OutcomeMessage] = []
    let attempt = XCTUnwrapAttempt(
      sessions.begin(engine: Engine(), request: makeRequest()) { outcomes.append($0) })
    var dismissal: (@MainActor () -> Void)?
    attempt.closeUI = { dismissal = $0 }

    sessions.finish(attempt, with: Outcomes.completed())
    XCTAssertTrue(outcomes.isEmpty)
    XCTAssertNotNil(sessions.active)

    dismissal?()
    dismissal?()
    XCTAssertEqual(outcomes, [Outcomes.completed()])
    XCTAssertNil(sessions.active)
  }

  @MainActor
  func testGraceDeliversWhenTheDismissalNeverCompletes() async {
    let scheduler = ManualScheduler()
    let sessions = SessionCoordinator(scheduler: scheduler)
    var outcomes: [OutcomeMessage] = []
    let attempt = XCTUnwrapAttempt(
      sessions.begin(engine: Engine(), request: makeRequest()) { outcomes.append($0) })
    var dismissal: (@MainActor () -> Void)?
    attempt.closeUI = { dismissal = $0 }

    sessions.finish(attempt, with: Outcomes.completed())
    scheduler.advance(by: SessionCoordinator.dismissalGrace - 0.5)
    XCTAssertTrue(outcomes.isEmpty)
    scheduler.advance(by: 0.5)
    XCTAssertEqual(outcomes.count, 1)

    dismissal?()
    XCTAssertEqual(outcomes.count, 1)
  }

  @MainActor
  func testDetachDropsTheAttemptWithoutAResult() async {
    let sessions = SessionCoordinator(scheduler: ManualScheduler())
    let engine = Engine()
    var outcomes: [OutcomeMessage] = []
    let attempt = XCTUnwrapAttempt(
      sessions.begin(engine: engine, request: makeRequest()) { outcomes.append($0) })
    var closed = false
    attempt.closeUI = { _ in closed = true }

    sessions.detach(engine: Engine())
    XCTAssertNotNil(sessions.active)

    sessions.detach(engine: engine)
    XCTAssertTrue(closed)
    XCTAssertNil(sessions.active)
    XCTAssertFalse(sessions.finish(attempt, with: Outcomes.completed()))
    XCTAssertTrue(outcomes.isEmpty)
  }

  /// Review P1: a detach while the UI is closing must suppress the pending result.
  @MainActor
  func testDetachWhileClosingSuppressesTheDismissalDelivery() async {
    let scheduler = ManualScheduler()
    let sessions = SessionCoordinator(scheduler: scheduler)
    let engine = Engine()
    var outcomes: [OutcomeMessage] = []
    let attempt = XCTUnwrapAttempt(
      sessions.begin(engine: engine, request: makeRequest()) { outcomes.append($0) })
    var dismissal: (@MainActor () -> Void)?
    attempt.closeUI = { dismissal = $0 }

    sessions.finish(attempt, with: Outcomes.completed())
    sessions.detach(engine: engine)
    dismissal?()
    scheduler.advance(by: SessionCoordinator.dismissalGrace)

    XCTAssertTrue(outcomes.isEmpty)
    XCTAssertNil(sessions.active)
    XCTAssertEqual(scheduler.pendingCount, 0)
  }

  @MainActor
  func testDetachWhileClosingCancelsTheGraceTimer() async {
    let scheduler = ManualScheduler()
    let sessions = SessionCoordinator(scheduler: scheduler)
    let engine = Engine()
    var outcomes: [OutcomeMessage] = []
    let attempt = XCTUnwrapAttempt(
      sessions.begin(engine: engine, request: makeRequest()) { outcomes.append($0) })
    attempt.closeUI = { _ in }

    sessions.end(attempt, with: Outcomes.failed(.timedOut))
    sessions.detach(engine: engine)

    XCTAssertEqual(scheduler.pendingCount, 0)
    scheduler.advance(by: SessionCoordinator.dismissalGrace * 2)
    XCTAssertTrue(outcomes.isEmpty)
    XCTAssertNil(sessions.active)
    XCTAssertNotNil(sessions.begin(engine: Engine(), request: makeRequest(attemptId: 2)) { _ in })
  }

  @MainActor
  func testLookupIsScopedToTheEngineAndAttempt() async {
    let sessions = SessionCoordinator(scheduler: ManualScheduler())
    let engine = Engine()
    let attempt = sessions.begin(engine: engine, request: makeRequest(attemptId: 7)) { _ in }

    XCTAssertTrue(sessions.attempt(engine: engine, attemptId: 7) === attempt)
    XCTAssertNil(sessions.attempt(engine: engine, attemptId: 6))
    XCTAssertNil(sessions.attempt(engine: Engine(), attemptId: 7))
  }

  @MainActor
  func testEndRecordsThePluginEndAndRunsEndHandlers() async {
    let sessions = SessionCoordinator(scheduler: ManualScheduler())
    let attempt = XCTUnwrapAttempt(sessions.begin(engine: Engine(), request: makeRequest()) { _ in })
    var ended = 0
    attempt.onEnd { ended += 1 }

    sessions.end(attempt, with: Outcomes.failed(.timedOut))
    sessions.end(attempt, with: Outcomes.cancelled(.app))

    XCTAssertEqual(attempt.pluginEnd, Outcomes.failed(.timedOut))
    XCTAssertEqual(ended, 1)
    attempt.onEnd { ended += 1 }
    XCTAssertEqual(ended, 2)
  }
}

// MARK: - CredentialsBroker

final class CredentialsBrokerTests: XCTestCase {
  @MainActor
  private func makeBroker(
    timeoutMillis: Int64 = 15_000
  ) -> (CredentialsBroker, ActiveAttempt, SessionCoordinator, FakeDart, ManualScheduler) {
    let scheduler = ManualScheduler()
    let sessions = SessionCoordinator(scheduler: scheduler)
    let attempt = XCTUnwrapAttempt(
      sessions.begin(
        engine: Engine(), request: makeRequest(credentialsTimeoutMillis: timeoutMillis)
      ) { _ in })
    let dart = FakeDart()
    let broker = CredentialsBroker(attempt: attempt, fetcher: dart.fetcher, scheduler: scheduler)
    return (broker, attempt, sessions, dart, scheduler)
  }

  @MainActor
  func testHandsOverValidCredentials() async {
    let (broker, attempt, _, dart, _) = makeBroker()
    var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
    broker.fetch { results.append($0) }

    XCTAssertEqual(dart.requests, [1])
    dart.reply(.success(validCredentials()))

    XCTAssertEqual(results.count, 1)
    guard case .success(let credentials) = results.first else {
      return XCTFail("expected credentials")
    }
    XCTAssertEqual(credentials.accessKeyId, "ASIAEXAMPLE")
    XCTAssertEqual(credentials.sessionToken, "token-value")
    XCTAssertFalse(attempt.credentialsFailed)
  }

  @MainActor
  func testDartFailureValueSetsTheCredentialsFlag() async {
    let (broker, attempt, _, dart, _) = makeBroker()
    var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
    broker.fetch { results.append($0) }

    dart.reply(.success(CredentialsResultMessage(failure: .providerError)))

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(failureReason(results.first), .providerError)
    XCTAssertTrue(attempt.credentialsFailed)
  }

  @MainActor
  func testInvalidOrExpiredCredentialsFail() async {
    let blank = CredentialsResultMessage(
      credentials: CredentialsMessage(
        accessKeyId: "ASIAEXAMPLE", secretAccessKey: " ", sessionToken: "token",
        expirationEpochSeconds: Int64(Date().timeIntervalSince1970 + 900)))
    for message in [blank, validCredentials(expiresIn: -1), CredentialsResultMessage()] {
      let (broker, attempt, _, dart, _) = makeBroker()
      var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
      broker.fetch { results.append($0) }
      dart.reply(.success(message))
      XCTAssertEqual(failureReason(results.first), .invalid)
      XCTAssertTrue(attempt.credentialsFailed)
    }
  }

  @MainActor
  func testChannelErrorFails() async {
    let (broker, attempt, _, dart, _) = makeBroker()
    var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
    broker.fetch { results.append($0) }

    dart.reply(.failure(ChannelFailure()))

    XCTAssertEqual(failureReason(results.first), .channelError)
    XCTAssertTrue(attempt.credentialsFailed)
  }

  @MainActor
  func testTimesOutFiveSecondsAfterTheDartTimeout() async {
    let (broker, attempt, _, dart, scheduler) = makeBroker(timeoutMillis: 1_000)
    var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
    broker.fetch { results.append($0) }

    scheduler.advance(by: 5.5)
    XCTAssertTrue(results.isEmpty)
    scheduler.advance(by: 0.5)
    XCTAssertEqual(failureReason(results.first), .timedOut)
    XCTAssertTrue(attempt.credentialsFailed)

    dart.reply(.success(validCredentials()))
    XCTAssertEqual(results.count, 1)
  }

  @MainActor
  func testAttemptEndFailsAPendingRequestAndDropsTheLateReply() async {
    let (broker, _, sessions, dart, scheduler) = makeBroker()
    var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
    broker.fetch { results.append($0) }

    sessions.detach(engine: XCTUnwrapAttempt(sessions.active).engine)
    XCTAssertEqual(failureReason(results.first), .attemptEnded)

    dart.reply(.success(validCredentials()))
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(scheduler.pendingCount, 0)
  }

  @MainActor
  func testRequestAfterTheAttemptEndedNeverReachesDart() async {
    let (broker, attempt, sessions, dart, _) = makeBroker()
    sessions.finish(attempt, with: Outcomes.completed())
    var results: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []

    broker.fetch { results.append($0) }

    XCTAssertEqual(failureReason(results.first), .attemptEnded)
    XCTAssertTrue(dart.requests.isEmpty)
  }

  func testCredentialsAreRedactedInEveryTextualForm() {
    let credentials = PluginTemporaryCredentials(
      accessKeyId: "ASIAEXAMPLE", secretAccessKey: "secret-value", sessionToken: "token-value",
      expiration: Date())
    var dumped = ""
    dump(credentials, to: &dumped)
    let forms = [
      credentials.description, credentials.debugDescription, String(describing: credentials),
      String(reflecting: credentials), "\(credentials)", dumped,
    ]
    for form in forms {
      XCTAssertFalse(form.contains("ASIAEXAMPLE"), form)
      XCTAssertFalse(form.contains("secret-value"), form)
      XCTAssertFalse(form.contains("token-value"), form)
    }
  }

  private func failureReason(
    _ result: Result<PluginTemporaryCredentials, CredentialsUnavailableError>?
  ) -> CredentialsUnavailableError.Reason? {
    guard case .failure(let error) = result else {
      return nil
    }
    return error.reason
  }
}

// MARK: - CameraPermission

final class CameraPermissionTests: XCTestCase {
  func testStatusTable() {
    XCTAssertEqual(CameraPermission.status(for: .authorized), .granted)
    XCTAssertEqual(CameraPermission.status(for: .notDetermined), .notDetermined)
    XCTAssertEqual(CameraPermission.status(for: .denied), .permanentlyDenied)
    XCTAssertEqual(CameraPermission.status(for: .restricted), .restricted)
  }

  @MainActor
  func testMissingUsageDescriptionNeverPrompts() async {
    for description in [nil, "", "  \n"] as [String?] {
      let camera = FakeCamera()
      camera.authorization = .notDetermined
      camera.usageDescription = description
      let permission = CameraPermission(camera: camera)
      var status: CameraPermissionStatusMessage?
      var error: ErrorCodeMessage?

      permission.request { status = $0 }
      permission.ensureAccess { error = $0 }

      XCTAssertEqual(status, .notDetermined)
      XCTAssertEqual(error, .missingCameraUsageDescription)
      XCTAssertEqual(camera.requestCount, 0)
    }
  }

  @MainActor
  func testRequestPromptsOnlyWhenUndetermined() async {
    let camera = FakeCamera()
    camera.authorization = .denied
    let permission = CameraPermission(camera: camera)
    var statuses: [CameraPermissionStatusMessage] = []

    permission.request { statuses.append($0) }
    XCTAssertEqual(camera.requestCount, 0)

    camera.authorization = .notDetermined
    permission.request { statuses.append($0) }
    camera.answer(granted: true)

    XCTAssertEqual(statuses, [.permanentlyDenied, .granted])
    XCTAssertEqual(camera.requestCount, 1)
  }
}

// MARK: - LivenessHost

final class LivenessHostTests: XCTestCase {
  @MainActor
  private final class Fixture {
    let scheduler = ManualScheduler()
    lazy var sessions = SessionCoordinator(scheduler: scheduler)
    let camera = FakeCamera()
    let presenter = FakePresenter()
    let dart = FakeDart()
    let engine = Engine()
    var isLinked = true
    var isModelBundled = true
    var outcomes: [OutcomeMessage] = []

    lazy var host = makeHost(engine: engine)

    func makeHost(engine: AnyObject) -> LivenessHost {
      LivenessHost(
        engine: engine,
        sessions: sessions,
        sdk: LivenessHost.SdkStatus(
          isLinked: isLinked, isFaceDetectorModelBundled: { [unowned self] in self.isModelBundled }),
        camera: camera,
        presenter: presenter,
        settings: FakeSettings(),
        fetcher: dart.fetcher,
        scheduler: scheduler)
    }

    func start(attemptId: Int64 = 1) {
      host.start(makeRequest(attemptId: attemptId)) { [unowned self] in self.outcomes.append($0) }
    }
  }

  @MainActor
  func testCheckAvailabilityReasons() async {
    let fixture = Fixture()
    XCTAssertEqual(fixture.host.checkAvailability(), AvailabilityMessage(isAvailable: true))

    fixture.camera.hasVideoDevice = false
    XCTAssertEqual(fixture.host.checkAvailability().reason, .noCamera)

    fixture.camera.usageDescription = nil
    XCTAssertEqual(fixture.host.checkAvailability().reason, .missingCameraUsageDescription)

    fixture.isModelBundled = false
    XCTAssertEqual(fixture.host.checkAvailability().reason, .sdkUnavailable)

    let unlinked = Fixture()
    unlinked.isLinked = false
    XCTAssertEqual(
      unlinked.host.checkAvailability(),
      AvailabilityMessage(isAvailable: false, reason: .sdkUnavailable))
  }

  /// The CocoaPods build: no prompt, no UI, slot untouched.
  @MainActor
  func testStartWithoutTheSdkRepliesSdkUnavailable() async {
    let fixture = Fixture()
    fixture.isLinked = false
    fixture.camera.authorization = .notDetermined

    fixture.start()

    XCTAssertEqual(fixture.outcomes.map(\.errorCode), [.sdkUnavailable])
    XCTAssertEqual(fixture.outcomes.first?.nativeCode, "FaceLivenessNotLinked")
    XCTAssertEqual(fixture.camera.requestCount, 0)
    XCTAssertTrue(fixture.presenter.presented.isEmpty)
    XCTAssertNil(fixture.sessions.active)
  }

  @MainActor
  func testMissingModelRepliesSdkUnavailableBeforeCreatingTheUi() async {
    let fixture = Fixture()
    fixture.isModelBundled = false

    fixture.start()

    XCTAssertEqual(fixture.outcomes.first?.nativeCode, "FaceDetectorModelNotFound")
    XCTAssertTrue(fixture.presenter.presented.isEmpty)
  }

  @MainActor
  func testPresentsAfterThePermissionIsGrantedAndCompletes() async {
    let fixture = Fixture()
    fixture.camera.authorization = .notDetermined

    fixture.start()
    XCTAssertTrue(fixture.presenter.presented.isEmpty)
    fixture.camera.answer(granted: true)
    XCTAssertEqual(fixture.presenter.presented.count, 1)

    fixture.presenter.events?.completed()
    XCTAssertTrue(fixture.outcomes.isEmpty, "delivered after the UI closed")
    fixture.presenter.finishDismissal()
    XCTAssertEqual(fixture.outcomes, [Outcomes.completed()])
  }

  @MainActor
  func testDeniedPermissionIsPermanentlyDeniedWithoutUi() async {
    let fixture = Fixture()
    fixture.camera.authorization = .notDetermined

    fixture.start()
    fixture.camera.answer(granted: false)

    XCTAssertEqual(fixture.outcomes.map(\.errorCode), [.cameraPermissionPermanentlyDenied])
    XCTAssertTrue(fixture.presenter.presented.isEmpty)
  }

  @MainActor
  func testMissingUsageDescriptionFailsBeforePrompting() async {
    let fixture = Fixture()
    fixture.camera.authorization = .notDetermined
    fixture.camera.usageDescription = nil

    fixture.start()

    XCTAssertEqual(fixture.outcomes.map(\.errorCode), [.missingCameraUsageDescription])
    XCTAssertEqual(fixture.camera.requestCount, 0)
  }

  @MainActor
  func testCancelDuringThePermissionPromptSkipsPresentation() async {
    let fixture = Fixture()
    fixture.camera.authorization = .notDetermined

    fixture.start()
    fixture.host.cancel(attemptId: 1, reason: .app)
    XCTAssertEqual(fixture.outcomes, [Outcomes.cancelled(.app)])

    fixture.camera.answer(granted: true)
    XCTAssertTrue(fixture.presenter.presented.isEmpty)
    XCTAssertEqual(fixture.outcomes.count, 1)
  }

  @MainActor
  func testTimeoutClosesTheUiAndWinsOverLaterSdkResults() async {
    let fixture = Fixture()
    fixture.start()

    fixture.host.cancel(attemptId: 1, reason: .timeout)
    XCTAssertEqual(fixture.presenter.closeCount, 1)
    fixture.presenter.events?.failed(SdkError(code: 7, message: "closed"))
    fixture.presenter.finishDismissal()

    XCTAssertEqual(fixture.outcomes, [Outcomes.failed(.timedOut)])
  }

  @MainActor
  func testCancelForAnotherAttemptIsIgnored() async {
    let fixture = Fixture()
    fixture.start(attemptId: 2)

    fixture.host.cancel(attemptId: 1, reason: .app)

    XCTAssertEqual(fixture.presenter.closeCount, 0)
    XCTAssertTrue(fixture.outcomes.isEmpty)
  }

  @MainActor
  func testSecondEngineGetsAlreadyActive() async {
    let fixture = Fixture()
    fixture.start()
    var other: [OutcomeMessage] = []

    fixture.makeHost(engine: Engine()).start(makeRequest()) { other.append($0) }

    XCTAssertEqual(other.map(\.errorCode), [.alreadyActive])
    XCTAssertTrue(fixture.outcomes.isEmpty)
  }

  @MainActor
  func testNoForegroundViewControllerIsPresenterUnavailable() async {
    let fixture = Fixture()
    fixture.presenter.canPresent = false

    fixture.start()

    XCTAssertEqual(fixture.outcomes.map(\.errorCode), [.presenterUnavailable])
    XCTAssertNil(fixture.sessions.active)
  }

  @MainActor
  func testNoVideoDeviceIsCameraUnavailable() async {
    let fixture = Fixture()
    fixture.camera.hasVideoDevice = false

    fixture.start()

    XCTAssertEqual(fixture.outcomes.map(\.errorCode), [.cameraUnavailable])
    XCTAssertTrue(fixture.presenter.presented.isEmpty)
  }

  @MainActor
  func testFailingCredentialsTurnTheSdkErrorIntoCredentialsUnavailable() async {
    let fixture = Fixture()
    fixture.start()
    var credentials: [Result<PluginTemporaryCredentials, CredentialsUnavailableError>] = []
    fixture.presenter.credentials?.fetch { credentials.append($0) }

    fixture.dart.reply(.success(CredentialsResultMessage(failure: .providerError)))
    fixture.presenter.events?.failed(SdkError(code: 7, message: "socket closed"))
    fixture.presenter.finishDismissal()

    XCTAssertEqual(credentials.count, 1)
    XCTAssertEqual(fixture.outcomes.map(\.errorCode), [.credentialsUnavailable])
    XCTAssertEqual(fixture.outcomes.first?.nativeCode, "socketClosed")
  }

  @MainActor
  func testUserCancelAndInterruption() async {
    let fixture = Fixture()
    fixture.start()
    fixture.presenter.events?.failed(SdkError(code: 6, message: "cancelled"))
    fixture.presenter.finishDismissal()
    XCTAssertEqual(fixture.outcomes, [Outcomes.cancelled(.user)])

    fixture.start(attemptId: 2)
    fixture.presenter.events?.interrupted("AppBackgrounded")
    fixture.presenter.events?.interrupted("ViewDisappeared")
    fixture.presenter.finishDismissal()
    XCTAssertEqual(
      fixture.outcomes.last,
      Outcomes.failed(.sessionInterrupted, nativeCode: "AppBackgrounded"))
    XCTAssertEqual(fixture.outcomes.count, 2)
  }

  @MainActor
  func testDisposeDropsTheAttemptWithoutAReply() async {
    let fixture = Fixture()
    fixture.start()

    fixture.host.dispose()
    fixture.presenter.finishDismissal()
    fixture.presenter.events?.completed()

    XCTAssertEqual(fixture.presenter.closeCount, 1)
    XCTAssertTrue(fixture.outcomes.isEmpty)
    XCTAssertNil(fixture.sessions.active)
  }

  @MainActor
  func testDisposeResolvesAPendingCredentialRequestAndRepliesNothing() async throws {
    let fixture = Fixture()
    fixture.start()
    let credentials = try XCTUnwrap(fixture.presenter.credentials)
    let request = Task { @MainActor in try await credentials.fetch() }
    while fixture.dart.requests.isEmpty {
      await Task.yield()
    }

    fixture.host.dispose()

    do {
      _ = try await request.value
      XCTFail("expected the credential request to fail")
    } catch let error as CredentialsUnavailableError {
      XCTAssertEqual(error.reason, .attemptEnded)
    }
    fixture.dart.reply(.success(validCredentials()))
    fixture.presenter.events?.failed(SdkError(code: 7, message: "socket closed"))
    fixture.presenter.finishDismissal()
    fixture.scheduler.advance(by: SessionCoordinator.dismissalGrace)
    XCTAssertTrue(fixture.outcomes.isEmpty)
  }

  @MainActor
  func testDisposeWhileClosingRepliesNothing() async {
    let fixture = Fixture()
    fixture.start()

    fixture.host.cancel(attemptId: 1, reason: .app)
    fixture.host.dispose()
    fixture.presenter.finishDismissal()
    fixture.scheduler.advance(by: SessionCoordinator.dismissalGrace)

    XCTAssertTrue(fixture.outcomes.isEmpty)
    XCTAssertNil(fixture.sessions.active)
  }

  /// The ios-cocoapods CI job sets `AWS_LIVENESS_EXPECT_SDK=0` and ios-spm sets `1`
  /// (through `TEST_RUNNER_AWS_LIVENESS_EXPECT_SDK`).
  func testBuildLinksFaceLivenessAsTheCiJobExpects() throws {
    guard let expected = ProcessInfo.processInfo.environment["AWS_LIVENESS_EXPECT_SDK"] else {
      throw XCTSkip("AWS_LIVENESS_EXPECT_SDK is not set")
    }
    XCTAssertEqual(LivenessSDK.isLinked, expected == "1")
  }
}

// MARK: - Presenter, theme, model lookup

final class PresenterTests: XCTestCase {
  @MainActor
  private final class Node: PresentationNode {
    var nextPresented: PresentationNode?
    var isDismissing = false
  }

  @MainActor
  func testTopmostFollowsThePresentationChain() async {
    let root = Node()
    let modal = Node()
    let sheet = Node()
    root.nextPresented = modal
    modal.nextPresented = sheet

    XCTAssertTrue(Presenter.topmost(from: root) === sheet)
    XCTAssertTrue(Presenter.topmost(from: sheet) === sheet)
  }

  @MainActor
  func testTopmostSkipsAControllerBeingDismissed() async {
    let root = Node()
    let modal = Node()
    let closing = Node()
    root.nextPresented = modal
    modal.nextPresented = closing
    closing.isDismissing = true

    XCTAssertTrue(Presenter.topmost(from: root) === modal)
  }
}

final class ThemeAndSdkTests: XCTestCase {
  func testArgbColorComponents() {
    let color = ArgbColor(argb: 0x80FF_4000)
    XCTAssertEqual(color.alpha, 128.0 / 255, accuracy: 0.0001)
    XCTAssertEqual(color.red, 1, accuracy: 0.0001)
    XCTAssertEqual(color.green, 64.0 / 255, accuracy: 0.0001)
    XCTAssertEqual(color.blue, 0, accuracy: 0.0001)
  }

  func testFaceDetectorModelLookup() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    let assets = root.appendingPathComponent("Frameworks/App.framework/flutter_assets")
    try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: assets.appendingPathComponent(LivenessSDK.faceDetectorModelName),
      withIntermediateDirectories: true)
    XCTAssertFalse(LivenessSDK.containsFaceDetectorModel(in: root), "flutter_assets is skipped")

    let model = root.appendingPathComponent(
      "Frameworks/Some.framework/AmplifyUILiveness_FaceLiveness.bundle/"
        + LivenessSDK.faceDetectorModelName)
    try fileManager.createDirectory(at: model, withIntermediateDirectories: true)
    XCTAssertTrue(LivenessSDK.containsFaceDetectorModel(in: root))
  }
}

#if canImport(UIKit)
  final class PluginTests: XCTestCase {
    func testPluginTypeIsLinked() {
      XCTAssertNotNil(AwsLivenessForFlutterPlugin.self)
    }
  }
#endif
