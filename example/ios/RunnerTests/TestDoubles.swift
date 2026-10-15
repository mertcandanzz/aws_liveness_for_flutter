import Foundation
import XCTest

@testable import aws_liveness_for_flutter

// Test doubles and helpers shared by RunnerTests.swift.

// MARK: - Fakes

@MainActor
final class ManualScheduler: Scheduler {
  private struct Item {
    let id: Int
    let at: TimeInterval
    let action: @MainActor () -> Void
  }

  private(set) var now: TimeInterval = 0
  private var items: [Item] = []
  private var nextId = 0

  var pendingCount: Int { items.count }

  @discardableResult
  func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellation {
    nextId += 1
    let id = nextId
    items.append(Item(id: id, at: now + delay, action: action))
    return Cancellation { [weak self] in
      self?.items.removeAll { $0.id == id }
    }
  }

  func advance(by seconds: TimeInterval) {
    now += seconds
    while let index = items.indices.filter({ items[$0].at <= now })
      .min(by: { items[$0].at < items[$1].at })
    {
      let item = items.remove(at: index)
      item.action()
    }
  }
}

@MainActor
final class FakeCamera: CameraAccess {
  var authorization: CameraAuthorization = .authorized
  var hasVideoDevice = true
  var usageDescription: String? = "Used to check that you are a live person."
  private(set) var requestCount = 0
  private var pending: (@MainActor (Bool) -> Void)?

  func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) {
    requestCount += 1
    pending = completion
  }

  func answer(granted: Bool) {
    authorization = granted ? .authorized : .denied
    let completion = pending
    pending = nil
    completion?(granted)
  }
}

@MainActor
final class FakePresenter: LivenessPresenting {
  var canPresent = true
  private(set) var presented: [ActiveAttempt] = []
  private(set) var events: LivenessEvents?
  private(set) var credentials: CredentialsBroker?
  private(set) var closeCount = 0
  private var pendingDismissal: (@MainActor () -> Void)?

  func present(_ attempt: ActiveAttempt, credentials: CredentialsBroker, events: LivenessEvents)
    -> Bool
  {
    guard canPresent else {
      return false
    }
    presented.append(attempt)
    self.events = events
    self.credentials = credentials
    attempt.closeUI = { [weak self] completion in
      self?.closeCount += 1
      self?.pendingDismissal = completion
    }
    return true
  }

  func finishDismissal() {
    let completion = pendingDismissal
    pendingDismissal = nil
    completion?()
  }
}

@MainActor
final class FakeSettings: SettingsOpening {
  func open(_ completion: @escaping @MainActor (Bool) -> Void) {
    completion(true)
  }
}

/// Dart's side of `fetchCredentials`: requests wait until the test answers them.
@MainActor
final class FakeDart {
  private(set) var requests: [Int64] = []
  private var pending: [(Result<CredentialsResultMessage, Error>) -> Void] = []

  var fetcher: CredentialsFetcher {
    { [weak self] attemptId, completion in
      MainActor.assumeIsolated {
        self?.requests.append(attemptId)
        self?.pending.append(completion)
      }
    }
  }

  func reply(_ result: Result<CredentialsResultMessage, Error>) {
    guard !pending.isEmpty else {
      return
    }
    pending.removeFirst()(result)
  }
}

struct ChannelFailure: Error {}

final class Engine {}

func makeRequest(attemptId: Int64 = 1, credentialsTimeoutMillis: Int64 = 15_000)
  -> StartRequestMessage
{
  StartRequestMessage(
    attemptId: attemptId,
    sessionId: "00000000-0000-0000-0000-000000000000",
    region: "eu-west-1",
    faceMovementCamera: .front,
    showStartView: true,
    theme: ThemeMessage(mode: .system),
    credentialsTimeoutMillis: credentialsTimeoutMillis)
}

func validCredentials(expiresIn seconds: TimeInterval = 900) -> CredentialsResultMessage {
  CredentialsResultMessage(
    credentials: CredentialsMessage(
      accessKeyId: "ASIAEXAMPLE",
      secretAccessKey: "secret-value",
      sessionToken: "token-value",
      expirationEpochSeconds: Int64(Date().timeIntervalSince1970 + seconds)))
}

// MARK: - Helpers

/// `XCTUnwrap` without `throws`, so call sites stay single expressions.
@MainActor
func XCTUnwrapAttempt(
  _ attempt: ActiveAttempt?, file: StaticString = #filePath, line: UInt = #line
) -> ActiveAttempt {
  guard let attempt = attempt else {
    XCTFail("expected an attempt", file: file, line: line)
    return ActiveAttempt(engine: Engine(), request: makeRequest()) { _ in }
  }
  return attempt
}
