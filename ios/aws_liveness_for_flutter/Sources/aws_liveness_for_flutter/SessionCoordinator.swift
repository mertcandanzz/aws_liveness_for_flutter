import Foundation

/// One liveness attempt owned by one Flutter engine (design §6.1).
///
/// Main-actor confined: every Pigeon handler, UIKit callback and SDK completion is moved to
/// the main thread before it touches an attempt.
@MainActor
final class ActiveAttempt {
  let engine: AnyObject
  let request: StartRequestMessage
  private let deliver: (OutcomeMessage) -> Void

  private(set) var isFinished = false

  /// Set when the owning engine detached (design §6.9). Nothing is delivered afterwards,
  /// even if the attempt was already finishing.
  private(set) var isDetached = false

  /// The grace timer of a delivery that waits for the UI to close.
  fileprivate var pendingDelivery: Cancellation?

  /// Set when our credentials provider failed for this attempt (design §4.2, rule 3).
  var credentialsFailed = false

  /// The result of a plugin-initiated end (design §4.2, rule 2).
  fileprivate(set) var pluginEnd: OutcomeMessage?

  /// Closes the native UI and calls its argument once the UI is gone. Set while it is shown.
  var closeUI: ((@escaping @MainActor () -> Void) -> Void)?

  private var endHandlers: [@MainActor () -> Void] = []

  init(engine: AnyObject, request: StartRequestMessage, deliver: @escaping (OutcomeMessage) -> Void) {
    self.engine = engine
    self.request = request
    self.deliver = deliver
  }

  /// Runs [handler] when the attempt finishes or is dropped; at once if it already has.
  func onEnd(_ handler: @escaping @MainActor () -> Void) {
    if isFinished {
      handler()
    } else {
      endHandlers.append(handler)
    }
  }

  /// Returns true only for the first caller; later calls are dropped.
  fileprivate func markFinished() -> Bool {
    if isFinished {
      return false
    }
    isFinished = true
    let handlers = endHandlers
    endHandlers = []
    handlers.forEach { $0() }
    return true
  }

  fileprivate func takeCloseUI() -> ((@escaping @MainActor () -> Void) -> Void)? {
    let close = closeUI
    closeUI = nil
    return close
  }

  /// Delivers [outcome] unless the engine detached.
  fileprivate func send(_ outcome: OutcomeMessage) {
    guard !isDetached else {
      return
    }
    deliver(outcome)
  }

  /// Suppresses every later delivery and cancels a pending one.
  fileprivate func markDetached() {
    isDetached = true
    pendingDelivery?.cancel()
    pendingDelivery = nil
  }
}

/// Process-wide single slot for the active attempt (design §6.1, §6.2).
///
/// Every result goes through [finish], which delivers at most once per attempt. When the
/// native UI is shown, the result is delivered from the dismissal completion, so the next
/// presentation starts cleanly; [dismissalGrace] bounds that wait. The slot is released right
/// before delivery.
@MainActor
final class SessionCoordinator {
  static let shared = SessionCoordinator(scheduler: MainQueueScheduler())

  /// Longest wait for the UI to finish closing before the result is delivered anyway.
  static let dismissalGrace: TimeInterval = 3

  private let scheduler: Scheduler
  private(set) var active: ActiveAttempt?

  init(scheduler: Scheduler) {
    self.scheduler = scheduler
  }

  /// Claims the slot, or returns nil when another attempt (from any engine) holds it.
  func begin(
    engine: AnyObject,
    request: StartRequestMessage,
    deliver: @escaping (OutcomeMessage) -> Void
  ) -> ActiveAttempt? {
    if active != nil {
      return nil
    }
    let attempt = ActiveAttempt(engine: engine, request: request, deliver: deliver)
    active = attempt
    return attempt
  }

  /// The unfinished attempt for [attemptId] started by [engine], if any.
  func attempt(engine: AnyObject, attemptId: Int64) -> ActiveAttempt? {
    guard let attempt = active, attempt.engine === engine,
      attempt.request.attemptId == attemptId, !attempt.isFinished
    else {
      return nil
    }
    return attempt
  }

  /// A plugin-initiated end: app cancel, timeout, backgrounding, presenter loss (rule 2).
  @discardableResult
  func end(_ attempt: ActiveAttempt, with outcome: OutcomeMessage) -> Bool {
    if !attempt.isFinished {
      attempt.pluginEnd = outcome
    }
    return finish(attempt, with: outcome)
  }

  /// Delivers [outcome] if [attempt] has not finished yet. Returns whether it will be delivered.
  @discardableResult
  func finish(_ attempt: ActiveAttempt, with outcome: OutcomeMessage) -> Bool {
    guard attempt.markFinished() else {
      return false
    }
    var delivered = false
    let deliverOnce: @MainActor () -> Void = { [weak self] in
      guard !delivered else {
        return
      }
      delivered = true
      attempt.pendingDelivery?.cancel()
      attempt.pendingDelivery = nil
      self?.release(attempt)
      attempt.send(outcome)
    }
    guard let close = attempt.takeCloseUI() else {
      deliverOnce()
      return true
    }
    attempt.pendingDelivery = scheduler.schedule(after: Self.dismissalGrace, deliverOnce)
    close(deliverOnce)
    return true
  }

  /// Ends the attempt of a detaching engine without a result: its Dart side is gone
  /// (design §6.9). This also covers an attempt that already finished and is waiting for
  /// its UI to close: that pending result is dropped and its grace timer cancelled. Pending
  /// credential requests fail through the end handlers, and the native UI is closed.
  func detach(engine: AnyObject) {
    guard let attempt = active, attempt.engine === engine else {
      return
    }
    attempt.markDetached()
    release(attempt)
    _ = attempt.markFinished()
    attempt.takeCloseUI()?({})
  }

  private func release(_ attempt: ActiveAttempt) {
    if active === attempt {
      active = nil
    }
  }
}
