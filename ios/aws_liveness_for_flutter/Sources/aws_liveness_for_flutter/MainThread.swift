import Foundation

/// Runs main-actor work from callbacks that arrive on other queues, such as AVFoundation and
/// FaceLiveness completions.
enum MainThread {
  static func run(_ block: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async {
      MainActor.assumeIsolated(block)
    }
  }
}

/// Cancels one scheduled action. Cancelling twice, or after the action ran, does nothing.
@MainActor
final class Cancellation {
  private var onCancel: (() -> Void)?

  init(_ onCancel: @escaping () -> Void) {
    self.onCancel = onCancel
  }

  func cancel() {
    let onCancel = self.onCancel
    self.onCancel = nil
    onCancel?()
  }
}

/// Delayed main-actor work; tests replace it with a manual clock.
@MainActor
protocol Scheduler: AnyObject {
  @discardableResult
  func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellation
}

@MainActor
final class MainQueueScheduler: Scheduler {
  @discardableResult
  func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellation {
    let item = DispatchWorkItem {
      MainActor.assumeIsolated(action)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return Cancellation { item.cancel() }
  }
}
