import Foundation

/// Builders for the `OutcomeMessage` shapes described in pigeons/messages.dart.
enum Outcomes {
  static func completed() -> OutcomeMessage {
    OutcomeMessage(kind: .completed)
  }

  static func cancelled(_ reason: CancelReasonMessage) -> OutcomeMessage {
    OutcomeMessage(kind: .cancelled, cancelReason: reason)
  }

  static func failed(
    _ code: ErrorCodeMessage,
    nativeCode: String? = nil,
    nativeMessage: String? = nil
  ) -> OutcomeMessage {
    OutcomeMessage(
      kind: .failed, errorCode: code, nativeCode: nativeCode, nativeMessage: nativeMessage)
  }

  /// The result of a plugin-initiated end requested by Dart (design §6.3, §6.4).
  static func forCancelRequest(_ reason: CancelRequestReasonMessage) -> OutcomeMessage {
    switch reason {
    case .app:
      return cancelled(.app)
    case .timeout:
      return failed(.timedOut)
    }
  }
}
